#!/bin/bash
# completely uninstall / purge and remove all configs for netdata

# Netdata installed through Kickstarter.sh has a different directory structure from apt-get install netdata.
# this file gets them both gone, as well as any cloud affililations

sudo killall netdata

wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sudo sh /tmp/netdata-kickstart.sh --uninstall --non-interactive

sudo systemctl stop netdata
sudo systemctl disable netdata
sudo systemctl unmask netdata
sudo rm -rf /lib/systemd/system/netdata.service
sudo rm -rf /lib/systemd/system/netdata-updater.service
sudo rm -rf /lib/systemd/system/netdata-updater.timer
sudo rm -rf /etc/logrotate.d/netdata
sudo /usr/libexec/netdata/netdata-uninstaller.sh --yes --env /etc/netdata/.environment

sudo apt-get --purge remove netdata -y 

sudo rm /usr/lib/netdata*
sudo rm /var/lib/apt/lists/packagecloud.io_netdata_*
sudo rm /var/lib/apt/lists/repository.netdata*
sudo rm /etc/init.d/netdata
sudo rm /etc/rc0.d/K01netdata
sudo rm /etc/rc1.d/K01netdata
sudo rm /etc/rc2.d/K01netdata
sudo rm /etc/rc3.d/K01netdata
sudo rm /etc/rc4.d/K01netdata
sudo rm /etc/rc5.d/K01netdata
sudo rm /etc/rc6.d/K01netdata
sudo rm /etc/rc0.d/S01netdata
sudo rm /etc/rc1.d/S01netdata
sudo rm /etc/rc2.d/S01netdata
sudo rm /etc/rc3.d/S01netdata
sudo rm /etc/rc4.d/S01netdata
sudo rm /etc/rc5.d/S01netdata
sudo rm /etc/rc6.d/S01netdata
sudo rm /usr/sbin/netdata
sudo rm -rf /var/lib/dpkg/info/netdata*
sudo rm -rf /var/lib/apt/lists/packagecloud.io_netdata*
sudo rm -rf /var/lib/apt/lists/repository.netdata*
sudo rm -rf /usr/share/netdata
sudo rm -rf /usr/share/doc/netdata*
sudo rm /usr/share/lintian/overrides/netdata*
sudo rm /usr/share/man/man1/netdata.1.gz
sudo rm /var/lib/systemd/deb-systemd-helper-enabled/netdata.service.dsh-also
sudo rm /var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/netdata.service
sudo rm /var/lib/systemd/deb-systemd-helper-masked/netdata.service

sudo rm -rf /usr/lib/netdata
sudo rm -rf /etc/rc2.d/S01netdata
sudo rm -rf /etc/rc3.d/S01netdata
sudo rm -rf /etc/rc4.d/S01netdata
sudo rm -rf /etc/rc5.d/S01netdata
sudo rm -rf /etc/default/netdata
sudo rm -rf /etc/apt/sources.list.d/netdata.list
sudo rm -rf /etc/apt/sources.list.d/netdata-edge.list
sudo rm -rf /etc/apt/trusted.gpg.d/netdata-archive-keyring.gpg
sudo rm -rf /etc/apt/trusted.gpg.d/netdata-edge-archive-keyring.gpg
sudo rm -rf /etc/apt/trusted.gpg.d/netdata-repoconfig-archive-keyring.gpg
sudo rm -rf /SM_DATA/sm_virt_machines/media/netdata-uninstaller.sh
sudo rm -rf /SM_DATA/sm_virt_machines/media/netdata*
sudo rm -rf /SM_DATA/working/netdata-kickstart*
sudo rm -rf /usr/share/lintian/overrides/netdata
sudo rm -rf /var/cache/apt/archives/netdata*
sudo rm -rf /opt/netdata*
sudo rm -rf /etc/cron.daily/netdata-updater
sudo rm -rf /var/log/journal/*.netdata
sudo rm -rf /dev/shm/*netdata*
sudo rm -rf /run/systemd/*.netdata

sudo rm -rf /usr/libexec/netdata
sudo rm -rf /var/log/netdata
sudo rm -rf /var/cache/netdata
sudo rm -rf /var/lib/netdata
sudo rm -rf /etc/netdata
sudo rm -rf /opt/netdata

wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sudo sh /tmp/netdata-kickstart.sh --uninstall --non-interactive

sudo rm -rf /tmp/netdata*

systemctl daemon-reload

echo "Checking if Netdata package is installed..."
if dpkg -l | grep -q netdata; then
    echo "Netdata package is installed."
else
    echo "Netdata package is not installed."
fi

echo "Searching for leftover Netdata files/directories..."
leftovers=$(sudo find / -name '*netdata*' 2>/dev/null)
if [ -n "$leftovers" ]; then
    echo "Found Netdata related files/directories:"
    echo "$leftovers"
else
    echo "No Netdata related files/directories found."
fi

echo "Checking for running Netdata processes..."
process_count=$(pgrep netdata | wc -l)
if [ "$process_count" -eq "0" ]; then
    echo "No Netdata process running."
else
    echo "Netdata process is running."
fi
