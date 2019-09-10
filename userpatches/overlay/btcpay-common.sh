#!/bin/bash

DEVICE_NAME=""
PARTITION_NAME=""
if lsblk /dev/sda1 &> /dev/null; then
    DEVICE_NAME=/dev/sda
    PARTITION_NAME=/dev/sda1
elif lsblk /dev/nvme0n1 &> /dev/null; then
    DEVICE_NAME=/dev/nvme0n1
    PARTITION_NAME=/dev/nvme0n1p1
fi
MOUNT_DIR="/mnt/external"
MOUNT_UNIT="mnt-external.mount"
DOCKER_VOLUMES="/var/lib/docker/volumes"

if [ -f "/root/.setup-mode" ]; then
    SETUP_MODE=true
else
    SETUP_MODE=false
fi