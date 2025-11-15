#!/bin/bash
# netdata-secure-install.sh
# Instala ou reinstala o Netdata via kickstart e aplica configuração corporativa segura
# Uso:
#   ./netdata-secure-install.sh --claim-token TOKEN --claim-rooms ROOM --claim-url URL
#   ./netdata-secure-install.sh --uninstall
#   ./netdata-secure-install.sh --nightly-channel --claim-token ... (para canal nightly)

set -euo pipefail

# --- Verificação de privilégios ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\n[\033[1;33m!\033[0m] Privilégios de administrador são necessários para executar este script."
  echo -e "[\033[1;34m→\033[0m] Tentando reexecutar automaticamente com sudo..."
  echo
  exec sudo bash "$0" "$@"
fi

# --- Funções auxiliares ---
log()  { echo -e "[\033[1;32m+\033[0m] $*"; }
warn() { echo -e "[\033[1;33m!\033[0m] $*" >&2; }
err()  { echo -e "[\033[1;31m×\033[0m] $*" >&2; exit 1; }

# --- Dependências mínimas ---
for bin in wget grep sed; do
  command -v "$bin" >/dev/null 2>&1 || err "Dependência ausente: $bin"
done

# --- Detectar se /tmp está com noexec ---
TMP_DIR="/tmp"
if mount | grep -E '\s/tmp\s' | grep -q 'noexec'; then
  warn "/tmp está montado com noexec — usando /root para arquivos temporários."
  TMP_DIR="/root"
fi

# --- Helper para libuv (usado só em instalação) ---
check_libuv() {
  if command -v ldconfig >/dev/null 2>&1; then
    if ldconfig -p 2>/dev/null | grep -q 'libuv\.so\.1'; then
      log "Biblioteca libuv.so.1 encontrada."
      return 0
    fi
  else
    warn "ldconfig não encontrado; pulando checagem de libuv."
    return 0
  fi

  warn "Biblioteca libuv.so.1 não encontrada. Tentando instalar libuv..."
  local PKG_MANAGER=""
  if command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  fi

  if [ -n "$PKG_MANAGER" ]; then
    case "$PKG_MANAGER" in
      dnf|yum)
        if [ -f /etc/os-release ] && grep -qiE "AlmaLinux|Rocky|Red Hat|CentOS" /etc/os-release 2>/dev/null; then
          $PKG_MANAGER install -y epel-release || true
          $PKG_MANAGER config-manager --set-enabled powertools 2>/dev/null || \
          $PKG_MANAGER config-manager --set-enabled crb 2>/dev/null || true
        fi
        $PKG_MANAGER install -y libuv || true
        ;;
      apt-get)
        apt-get update -qq || true
        apt-get install -y libuv1 || true
        ;;
      zypper)
        zypper --non-interactive install libuv1 || true
        ;;
    esac
  else
    warn "Nenhum gerenciador de pacotes detectado — não foi possível instalar automaticamente o libuv."
  fi

  # Se ainda não existir, tenta link simbólico de fallback
  if command -v ldconfig >/dev/null 2>&1; then
    if ! ldconfig -p 2>/dev/null | grep -q 'libuv\.so\.1'; then
      if [ -f /usr/lib64/libuv.so.0 ]; then
        ln -sf /usr/lib64/libuv.so.0 /usr/lib64/libuv.so.1
        ldconfig
        log "Symlink criado: /usr/lib64/libuv.so.1 → libuv.so.0 (modo compatibilidade)"
      elif [ -f /usr/lib/x86_64-linux-gnu/libuv.so.0 ]; then
        ln -sf /usr/lib/x86_64-linux-gnu/libuv.so.0 /usr/lib/x86_64-linux-gnu/libuv.so.1
        ldconfig
        log "Symlink criado: /usr/lib/x86_64-linux-gnu/libuv.so.1 → libuv.so.0 (modo compatibilidade)"
      else
        warn "libuv ainda não encontrada após tentativa de instalação."
      fi
    fi
  fi
}

# --- Parse de argumentos: uninstall / canal / claim ---
UNINSTALL_MODE="false"
CHANNEL_FLAG="--stable-channel"   # default
CLAIM_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --uninstall)
      UNINSTALL_MODE="true"
      ;;
    --nightly-channel)
      CHANNEL_FLAG="--nightly-channel"
      ;;
    --stable-channel)
      CHANNEL_FLAG="--stable-channel"
      ;;
    *)
      CLAIM_ARGS+=("$arg")
      ;;
  esac
done

# --- Parâmetros do kickstart ---
KICKSTART_URL="https://get.netdata.cloud/kickstart.sh"

# Aviso se for instalação sem claims (pra você lembrar, mas não quebra)
if [ "$UNINSTALL_MODE" = "false" ] && [ ${#CLAIM_ARGS[@]} -eq 0 ]; then
  warn "Nenhum argumento de claim informado."
  echo "Exemplo:"
  echo "  sudo ./netdata-secure-install.sh --claim-token TOKEN --claim-rooms ROOM --claim-url URL"
fi

# Em modo instalação, garante libuv antes de tentar subir Netdata
if [ "$UNINSTALL_MODE" = "false" ]; then
  check_libuv
fi

# --- Download helper ---
download_file() {
  local url="$1" dest="$2"
  wget -q -O "$dest" "$url" || err "Falha no download com wget ($url)"
}

# --- Baixar kickstart ---
log "Baixando e executando instalador Netdata (modo silencioso)..."
KICKSTART_FILE="$TMP_DIR/netdata-kickstart.sh"
LOGFILE="$TMP_DIR/netdata-install.log"

download_file "$KICKSTART_URL" "$KICKSTART_FILE"
chmod +x "$KICKSTART_FILE"

# --- Modo UNINSTALL ---
if [ "$UNINSTALL_MODE" = "true" ]; then
  "$KICKSTART_FILE" --uninstall > "$LOGFILE" 2>&1 || {
    err "Falha durante a desinstalação. Verifique o log em $LOGFILE"
  }
  log "Desinstalação concluída (detalhes em $LOGFILE)."
  exit 0
fi

# --- Modo INSTALL ---
"$KICKSTART_FILE" --non-interactive "$CHANNEL_FLAG" "${CLAIM_ARGS[@]}" > "$LOGFILE" 2>&1 || {
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
