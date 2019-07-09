#!/bin/bash

set -e

source /opt/btcpay/btcpay-common.sh

if ! [[ "$DEVICE_NAME" ]]; then
    echo -e "[ \e[31mFailed\e[0m ] The external device is not found"
else
    if lsblk $PARTITION_NAME &> /dev/null; then
        echo -e "[ \e[32mOK\e[0m ] Partitioning of external drive $DEVICE_NAME skipped: The disk is already partitioned"
    else
        echo "Partitioning the external drive $DEVICE_NAME..."
        ### DANGER ZONE ###
        (
            echo o # Create a new empty DOS partition table
            echo n # Add a new partition
            echo p # Primary partition
            echo 1 # Partition number
            echo   # First sector (Accept default: 1)
            echo   # Last sector (Accept default: varies)
            echo w # Write changes
        ) | fdisk ${DEVICE_NAME}
        partprobe ${DEVICE_NAME}
        while ! lsblk $PARTITION_NAME &> /dev/null; do
            sleep 1
        done
    fi
    if $SETUP_MODE || ! blkid -t "TYPE=ext4" "$PARTITION_NAME" &> /dev/null; then
        if mountpoint -q "$MOUNT_DIR"; then
            umount "$MOUNT_DIR"
        fi
        if mountpoint -q "$DOCKER_VOLUMES"; then
            umount "$DOCKER_VOLUMES"
        fi
        mkfs.ext4 -F "$PARTITION_NAME"
    fi
    mkdir -p "$MOUNT_DIR"
    if mountpoint -q "$MOUNT_DIR"; then
        echo -e "[ \e[32mOK\e[0m ] The partition $PARTITION_NAME is already mounted on $MOUNT_DIR"
    else
        echo "Mounting $PARTITION_NAME on $MOUNT_DIR"
        mount -o defaults,noatime "$PARTITION_NAME" "$MOUNT_DIR"
        if grep -qF "$MOUNT_DIR" /etc/fstab; then
            echo -e "[ \e[32mOK\e[0m ] /etc/fstab is up-to-date"
        else
            echo "$PARTITION_NAME $MOUNT_DIR ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
            echo -e "[ \e[32mOK\e[0m ] Updated /etc/fstab"
        fi
    fi

    # We need to use mount bind instead of symbolic link because docker would complain when running `docker volume rm`
    if mountpoint -q "$DOCKER_VOLUMES"; then
        echo -e "[ \e[32mOK\e[0m ] $DOCKER_VOLUMES is already a mount point"
    else
        echo "Creating a mount point on the docker volumes directory $DOCKER_VOLUMES to the external drive $MOUNT_DIR..."
        rm -rf "$DOCKER_VOLUMES"
        mkdir -p "$DOCKER_VOLUMES"
        mount --bind "$MOUNT_DIR" "$DOCKER_VOLUMES"
        if grep -qF "$DOCKER_VOLUMES" /etc/fstab; then
            echo -e "[ \e[32mOK\e[0m ] /etc/fstab is up-to-date"
        else
            echo "$MOUNT_DIR $DOCKER_VOLUMES none bind,nobootwait 0 2" >> /etc/fstab
            echo -e "[ \e[32mOK\e[0m ] Updated /etc/fstab for the mount point"
        fi
    fi

    docker_service="/lib/systemd/system/docker.service"
    if ! grep -qF "After=$MOUNT_UNIT" "$docker_service"; then
        sed -i "s/After=/After=$MOUNT_UNIT /g" "$docker_service"
        echo -e "[ \e[32mOK\e[0m ] Update $docker_service: Docker needs now to start after $MOUNT_UNIT"
    fi
    if ! grep -qF "Requires=$MOUNT_UNIT" "$docker_service"; then
        sed -i "s/Requires=/Requires=$MOUNT_UNIT /g" "$docker_service"
        echo -e "[ \e[32mOK\e[0m ] Update $docker_service: Docker must now requires $MOUNT_UNIT to start"
    fi
fi