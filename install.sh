#!/bin/bash
# netdata-secure-install.sh
# Instala ou reinstala o Netdata via kickstart e aplica configuração corporativa segura
# Uso:
#   sudo ./netdata-secure-install.sh --claim-token TOKEN --claim-rooms ROOM --claim-url URL

set -euo pipefail

# --- Verificação de privilégios ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "[\033[1;31m×\033[0m] Este script precisa ser executado como root."
  echo "Use: sudo $0 [argumentos]"
  exit 1
fi

# --- Funções auxiliares ---
log()  { echo -e "[\033[1;32m+\033[0m] $*"; }
warn() { echo -e "[\033[1;33m!\033[0m] $*" >&2; }
err()  { echo -e "[\033[1;31m×\033[0m] $*" >&2; exit 1; }

# --- Dependências mínimas ---
for bin in grep sed; do
  command -v "$bin" >/dev/null 2>&1 || err "Dependência ausente: $bin"
done

# --- Download helper (wget ou curl) ---
download_file() {
  local url="$1" dest="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url" || err "Falha no download com wget ($url)"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" || err "Falha no download com curl ($url)"
  else
    err "Nem wget nem curl disponíveis. Instale um deles e tente novamente."
  fi
}

# --- Parâmetros ---
KICKSTART_URL="https://get.netdata.cloud/kickstart.sh"
INSTALL_FLAGS="--non-interactive --stable-channel"
PASS_ARGS=("$@")

if [ ${#PASS_ARGS[@]} -eq 0 ]; then
  warn "Nenhum argumento de claim informado."
  echo "Exemplo:"
  echo "  sudo ./netdata-secure-install.sh --claim-token TOKEN --claim-rooms ROOM --claim-url URL"
fi

# --- Instalação silenciosa (sempre reinstala) ---
log "Baixando e executando instalador Netdata (modo silencioso)..."
download_file "$KICKSTART_URL" /tmp/netdata-kickstart.sh
chmod +x /tmp/netdata-kickstart.sh

LOGFILE="/tmp/netdata-install.log"
/tmp/netdata-kickstart.sh $INSTALL_FLAGS "${PASS_ARGS[@]}" > "$LOGFILE" 2>&1 || {
  err "Falha durante a instalação. Verifique o log em $LOGFILE"
}

log "Instalação concluída (detalhes em $LOGFILE)."
log "Aplicando configuração segura e política de retenção..."

# --- Detectar e criar configuração ---
CONFIG_DIRS=(
  "/etc/netdata"
  "/opt/netdata/etc/netdata"
)

CONFIG_PATH=""
for dir in "${CONFIG_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    CONFIG_PATH="$dir/netdata.conf"
    break
  fi
done

if [ -z "$CONFIG_PATH" ]; then
  err "Nenhum diretório de configuração encontrado. O instalador pode ter falhado."
fi

if [ ! -f "$CONFIG_PATH" ]; then
  log "netdata.conf não encontrado. Criando novo em $CONFIG_PATH"
  mkdir -p "$(dirname "$CONFIG_PATH")"
  touch "$CONFIG_PATH"
fi

# --- Backup e escrita ---
BACKUP="${CONFIG_PATH}.bak_$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_PATH" "$BACKUP"
log "Backup criado: $BACKUP"

# Remove seções antigas e recria [web] e [db]
sed -i '/^\[web\]/,/^\[/d' "$CONFIG_PATH" || true
sed -i '/^\[db\]/,/^\[/d' "$CONFIG_PATH" || true

cat <<'EOF' >> "$CONFIG_PATH"

[web]
    mode = none

[db]
    mode = dbengine
    update every = 1
    storage tiers = 3

    # Tier 0: per-second data for 30 days
    dbengine tier 0 retention time = 30d
    # No size limit - let time control retention

    # Tier 1: per-minute data for 6 months
    dbengine tier 1 update every iterations = 60
    dbengine tier 1 retention time = 6mo

    # Tier 2: per-hour data for 5 years
    dbengine tier 2 update every iterations = 60
    dbengine tier 2 retention time = 5y
EOF

log "Configurações aplicadas:"
log " - Dashboard desativado (mode = none)"
log " - DBEngine com 3 tiers de retenção (30d / 6mo / 5y)"

# --- Reiniciar Netdata ---
log "Reiniciando Netdata..."
RESTARTED=false

if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service | grep -q netdata.service; then
  systemctl restart netdata && RESTARTED=true
elif command -v service >/dev/null 2>&1 && service netdata status >/dev/null 2>&1; then
  service netdata restart && RESTARTED=true
else
  NETDATA_BIN=$(command -v netdata || true)
  if [ -n "$NETDATA_BIN" ]; then
    log "Executando reinício manual..."
    pkill -x netdata >/dev/null 2>&1 || true
    sleep 2
    nohup "$NETDATA_BIN" >/dev/null 2>&1 &
    RESTARTED=true
  fi
fi

if $RESTARTED; then
  log "Netdata reiniciado com sucesso."
else
  warn "Não foi possível reiniciar automaticamente. Reinicie manualmente."
fi

log "✅ Instalação e configuração segura concluídas."
