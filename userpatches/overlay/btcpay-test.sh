#!/bin/bash

set -e

source /opt/btcpay/btcpay-common.sh

if [ -f /sys/devices/platform/leds/leds/diy-led/brightness ]; then
    red_led=/sys/devices/platform/leds/leds/diy-led/brightness
    red_led_on=255
    red_led_off=0
elif [ -f /sys/devices/platform/leds/leds/diy/brightness ]; then
    red_led=/sys/devices/platform/leds/leds/diy/brightness
    red_led_on=255
    red_led_off=0
else
    red_led=/sys/devices/platform/leds/leds/standby-led/brightness
    red_led_on=0
    red_led_off=255
fi

if [ -f /sys/devices/platform/leds/leds/power-led/brightness ]; then
    white_led=/sys/devices/platform/leds/leds/power-led/brightness
elif [ -f /sys/devices/platform/leds/leds/work/brightness ]; then
    white_led=/sys/devices/platform/leds/leds/work/brightness
    echo "none" > /sys/devices/platform/leds/leds/work/trigger
else
    white_led=/sys/devices/platform/leds/leds/work-led/brightness
fi

echo '255' > $white_led
echo "$red_led_on" > $red_led

white_led_value=255
drive_mounted=false
docker_running=false
container_started=false
btcpay_init_exited=false
btcpayserver_pinged=false
fancontrol_running=false

blink_speed=1
timeout=$(((60*20)))

total_wait=0
success=false
while true; do
    echo "$white_led_value" > $white_led
    if ! $drive_mounted && [ "$(systemctl show -p SubState --value mnt-external.mount)" == "mounted" ]; then
        drive_mounted=true
        echo -e "[ \e[32mOK\e[0m ] The external drive is correctly mounted"
    fi

    if ! $docker_running && [ "$(systemctl show -p SubState --value docker.service)" == "running" ]; then
        docker_running=true
        echo -e "[ \e[32mOK\e[0m ] Docker started"
    fi

    if ! $container_started && [ "$(docker ps -aq -f status=running -f name=generated_btcpayserver_1)" ]; then
        container_started=true
        echo -e "[ \e[32mOK\e[0m ] BTCPayServer container is started"
    fi

    if ! $btcpayserver_pinged && [ "$(curl -sL -w "%{http_code}\\n" "http://localhost/" -o /dev/null)" == "200" ]; then
        btcpayserver_pinged=true
        echo -e "[ \e[32mOK\e[0m ] BTCPayServer is online"
    fi

    if ! $btcpay_init_exited && [ "$(systemctl show -p SubState --value btcpay-init)" == "dead" ]; then
        btcpay_init_exited=true
        echo -e "[ \e[32mOK\e[0m ] BTCPay-Init exited"
    fi

    if ! $fancontrol_running && [ "$(systemctl show -p SubState --value fancontrol.service)" == "running" ]; then
        fancontrol_running=true
        echo -e "[ \e[32mOK\e[0m ] The Fan control service is running"
    elif $fancontrol_running && [ "$(systemctl show -p SubState --value fancontrol.service)" != "running" ]; then
        fancontrol_running=false
        echo -e "[ \e[31mFailed\e[0m ] The Fan control service is not running"
    fi

    if $drive_mounted && $docker_running && $container_started && $btcpayserver_pinged && $fancontrol_running && $btcpay_init_exited; then
        echo -e "[ \e[32mOK\e[0m ] All tests passed"
        success=true
        break
    elif [ $total_wait -ge $timeout ]; then
        success=false
        break
    fi

    white_led_value=$(((white_led_value==0?255:0)))
    sleep $blink_speed
    total_wait=$(((total_wait+blink_speed)))
done

if $success; then
    if $SETUP_MODE; then
        echo "0" > $white_led
        rm -rf /root/.setup-mode

        source /etc/profile.d/btcpay-env.sh
        docker-compose -f $BTCPAY_DOCKER_COMPOSE down -t 20 # calling btcpay-down.sh hangs
        docker volume ls -q | while read -r line ; do
            if [ "$line" != "generated_bitcoin_datadir" ]; then
                docker volume rm -f "$line"
            fi
        done

        rm -rf "$MOUNT_DIR/generated_bitcoin_datadir/_data/debug.log"
        echo "Deleted all volumes that are not related to bitcoin"

        rm -rf "$SSHKEYFILE" "$SSHKEYFILE.pub"
        sed -i '/btcpay$/d' /root/.ssh/authorized_keys

        echo "Deleted BTCPay SSH key to access SSH host"

        rm -f /etc/ssh/ssh_host*
        echo "Deleted SSH host keys"
    fi
    echo "255" > $white_led
    echo "$red_led_off" > $red_led
    exit 0
else
    echo "0" > $white_led
    echo "$red_led_on" > $red_led
    echo -e "[ \e[31mFailed\e[0m ] Some tests did not passed in less than $timeout seconds"
    exit 1
fi