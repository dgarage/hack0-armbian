#!/bin/bash

set -e

source /opt/btcpay/btcpay-common.sh

if ! [ -f /etc/ssh/ssh_host_rsa_key ]; then
    dpkg-reconfigure openssh-server
    systemctl restart ssh
    echo -e "[ \e[32mOK\e[0m ] SSH Host keys generated"
fi

if ! mountpoint -q "$MOUNT_DIR"; then
    echo -e "[ \e[31mFailed\e[0m ] The mount directory $MOUNT_DIR does not exists, is the external drive plugged?"
    exit 1
fi

cd /root
new_key_file=false
authorized_keys_file="/root/.ssh/authorized_keys"
if $SETUP_MODE || ! [ -f "$SSHKEYFILE" ]; then
    new_key_file=true
    sed -i '/btcpay$/d' "$authorized_keys_file"
    rm -rf "$SSHKEYFILE" "$SSHKEYFILE.pub"
    echo "Creating BTCPay server key pair"
    ssh-keygen -t rsa -f "$SSHKEYFILE" -q -P "" -m PEM -C btcpay
    echo -e "[ \e[32mOK\e[0m ] BTCPay Server SSH keypair created"
    systemctl restart ssh
else
    echo -e "[ \e[32mOK\e[0m ] Do not create BTCPay Server SSH keys: $SSHKEYFILE already exists"
fi

if grep -q "btcpay$" "$authorized_keys_file"; then
    echo -e "[ \e[32mOK\e[0m ] Do not add BTCPayServer key file to $authorized_keys_file: Already added"
else
    cat "$SSHKEYFILE.pub" >> "$authorized_keys_file"
    echo -e "[ \e[32mOK\e[0m ] BTCPayServer key file added to $authorized_keys_file"
fi

$SETUP_MODE && rm -rf /root/.not_logged_in_yet
if $SETUP_MODE && [ -f "docker-images.tar" ]; then
    echo "Loading docker images..."
    docker load < "docker-images.tar"
    echo -e "[ \e[32mOK\e[0m ] Docker images loaded."
fi

if $SETUP_MODE && [ -f utxo-snapshot-*.tar ]; then
    BITCOIN_DATA_DIR=/var/lib/docker/volumes/generated_bitcoin_datadir/_data
    rm -rf "$BITCOIN_DATA_DIR"
    source /etc/profile.d/btcpay-env.sh
    echo "Loading UTXO set"
    SNAPSHOT_TAR="$(readlink -f utxo-snapshot-*.tar)"
    pushd . &> /dev/null
    cd btcpayserver-docker/contrib/FastSync
    ./load-utxo-set.sh $SNAPSHOT_TAR
    popd
    echo -e "[ \e[32mOK\e[0m ] UTXO Set preloaded."
fi

source /etc/profile.d/btcpay-env.sh
BTCPAY_HOST_SSHKEYFILE="$SSHKEYFILE"
. btcpay-setup.sh -i --no-systemd-reload