#!/bin/bash

set -e

echo "Running BTCPayServer armbian customization script..."

# Disable ssh password auth
echo root:root | chpasswd
sed -i '/PASSWORDAUTHENTICATION/Ic\PasswordAuthentication no' /etc/ssh/sshd_config

export LANG=C LC_ALL="en_US.UTF-8"
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

OVERLAY="/tmp/overlay"
DESTINATION="/root"

source "$OVERLAY/build.conf"
! [ -f "$OVERLAY/.production" ] && [ -f "$OVERLAY/build-local.conf" ] && source "$OVERLAY/build-local.conf"

$SETUP_MODE && touch "$DESTINATION/.setup-mode"
$SETUP_MODE && $SETUP_CLEANUP && echo "clean" > "$DESTINATION/.setup-mode"

if $HACK0_LOAD_AUTHORIZED_KEYS && [ -f "$OVERLAY/authorized_keys" ]; then
    mkdir -p "/root/.ssh"
    cp "$OVERLAY/authorized_keys" "/root/.ssh/authorized_keys"
    echo "SSH keys copied"
fi

apt update
apt upgrade -y
apt install -y git vim

# Customize the Motd with hack0 header
echo "MOTD_DISABLE='header'" >> /etc/default/armbian-motd
cp -af "$OVERLAY/10-hack0-header" /etc/update-motd.d/

####### Setup BTCPayServer
# Note that we can't install here because we can't use docker in the chroot
# Instead, we copy the images in a tar, and we will load them up
# during the first run.
cp -af "$OVERLAY/docker-images.tar" "$DESTINATION/docker-images.tar"
cp -af $OVERLAY/utxo-snapshot-*.tar "$DESTINATION/"
git clone "$OVERLAY/btcpayserver-docker" "$DESTINATION/btcpayserver-docker"
cd "$DESTINATION/btcpayserver-docker"
git remote set-url origin "$BTCPAY_REPOSITORY"
git checkout "$BTCPAY_BRANCH"
git pull
echo "$HACK0_HOSTNAME" > /etc/hostname
hostname -F /etc/hostname
BTCPAY_HOST="$HACK0_HOSTNAME.local"
REVERSEPROXY_DEFAULT_HOST="$BTCPAY_HOST"
source btcpay-setup.sh --docker-unavailable --install-only --no-startup-register
# Register btcpay-init
mkdir -p /opt/btcpay
cp -af "$OVERLAY/btcpay-init.sh" "/opt/btcpay/"
cp -af "$OVERLAY/btcpay-init.service" "/etc/systemd/system/"
systemctl --no-reload enable btcpay-init.service

cp -af "$OVERLAY/btcpay-setup-external-drive.sh" "/opt/btcpay/"
cp -af "$OVERLAY/btcpay-setup-external-drive.service" "/etc/systemd/system/"
systemctl --no-reload enable btcpay-setup-external-drive

cp -af "$OVERLAY/fancontrol.sh" "/opt/btcpay/"
cp -af "$OVERLAY/fancontrol.service" "/etc/systemd/system/"
systemctl --no-reload enable fancontrol
echo 'KERNEL=="thermal_zone0", SUBSYSTEM=="thermal", ATTR{mode}="disabled"' > /etc/udev/rules.d/10-thermalmode.rules

cp -af "$OVERLAY/btcpay-test.sh" "/opt/btcpay/"
cp -af "$OVERLAY/btcpay-test.service" "/etc/systemd/system/"
systemctl --no-reload enable btcpay-test

cp -af "$OVERLAY/btcpay-common.sh" "/opt/btcpay/btcpay-common.sh"
############

####### Setup WIFI (if supported by the board)
if [[ "$WIFI_SSID" ]]; then
    rm -f /boot/armbian_first_run.txt.template
    echo "FR_net_change_defaults=1
FR_net_wifi_enabled=1
FR_net_wifi_ssid='$WIFI_SSID'
FR_net_wifi_key='$WIFI_PW'
FR_general_delete_this_file_after_completion=1" > /boot/armbian_first_run.txt
fi
#######

#### Without this, port 53 (DNS) is taken by the OS and pihole can't work

sed -r -i 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf

####### Setup mdns
adduser --system --group          --disabled-login --home /var/run/avahi-daemon   avahi
apt install -y openssl net-tools fio libnss-mdns \
                avahi-daemon avahi-discover avahi-utils \
                fail2ban acl ifmetric
sed -i '/PUBLISH-WORKSTATION/Ic\publish-workstation=yes' /etc/avahi/avahi-daemon.conf
#######

