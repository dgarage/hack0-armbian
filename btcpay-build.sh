#!/bin/bash

set -e

HELP=true
DEPLOY=false
BUILD=false
UPDATE=false
DEPLOY_ON=""
BOARD=""
PROD=false
while (( "$#" )); do
  case "$1" in
    deploy)
      HELP=false
      DEPLOY=true
      shift 1
      ;;
    build)
      BUILD=true
      HELP=false
      shift 1
      ;;
    update)
      BUILD=true
      UPDATE=true
      HELP=false
      shift 1
      ;;
    --production)
        PROD=true
        shift 1
        ;;
    --help)
        HELP=true
        shift 1
        ;;
    --deploy-on)
        DEPLOY_ON="$2"
        shift 2
        ;;
    --board)
        BOARD="$2"
        shift 2
        ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done


if $HELP; then cat <<-END
Usage:
------

Build, update or deploy the armbian image

    build: Build the kernel, u-boot and create the hack0 image
    update: Create the hack0 image without rebuilding the kernel and u-book
    deploy: Deploy the last built image on the --deploy-device
    --deploy-on /dev/sda: Flash the image on the device /dev/sda
    --board rock64: Create an image for rock64 (Available: rockpro64, rock64)
    --production: Create a production image (will ignore build-local.conf)
    --help: Show this help
END
fi

if $BUILD; then
    if ! [[ "$BOARD" ]]; then
        echo "The board should be specified with --board (See --help)"
        exit 1
    fi
    BUILD_ARGS="docker BOARD=${BOARD} KERNEL_ONLY=no KERNEL_CONFIGURE=no RELEASE=bullseye BRANCH=current BUILD_DESKTOP=no WIREGUARD=no BUILD_MINIMAL=yes FORCE_USE_RAMDISK=no "
    if $UPDATE; then
        BUILD_ARGS="${BUILD_ARGS} CLEAN_LEVEL=oldcache PROGRESS_LOG_TO_FILE=yes"
    fi
    pushd . 2>/dev/null
    cd "userpatches/overlay"
    OVERLAY_DIRECTORY="$(pwd)"
    cd "$OVERLAY_DIRECTORY"
    source build.conf

    if $PROD; then
        touch .production
        echo "Building production image..."
    else
        echo "Building debug image..."
        rm -rf .production
        [ -f "build-local.conf" ] && source build-local.conf && echo "build-local.conf loaded"
    fi
    ! [ -d "btcpayserver-docker" ] && git clone "$BTCPAY_REPOSITORY"
    cd btcpayserver-docker
    git checkout "$BTCPAY_BRANCH"
    git fetch origin
    if ! git diff --quiet remotes/origin/HEAD || ! [ -f ../docker-images.tar ]; then
        git pull
        rm -f ../docker-images.tar
        . ./build.sh -i
        cd Generated
        export BTCPAY_DOCKER_PULL_FLAGS="--platform arm64"
        # https://github.com/docker/docker-ce/blob/master/components/cli/experimental/README.md
        # Edit /etc/docker/daemon.json with "experimental": true
        ./pull-images.sh
        ./save-images.sh ../../docker-images.tar
        # Do not mess up the build environment
        export BTCPAY_DOCKER_PULL_FLAGS=""
        ./pull-images.sh
    else
        echo "docker-images.tar is up to date"
    fi
    cd "$OVERLAY_DIRECTORY"
    if ! [ -f "utxo-snapshot-bitcoin-mainnet-769818.tar" ]; then
        set +e
        rm utxo-snapshot-*.tar &> /dev/null
        set -e
        wget "http://utxosets.blob.core.windows.net/public/utxo-snapshot-bitcoin-mainnet-769818.tar" -c -q --show-progress
    fi
    popd

    # Make sure built images are deleted
    mkdir -p output/images
    rm -rf output/images

    time ./compile.sh ${BUILD_ARGS}
fi


if $DEPLOY; then
    IMAGE="$(echo output/images/*.img)"
    IMAGE_SHA="$(echo output/images/*.img.sha)"
    if ! [[ "$IMAGE" ]] || ! [ -f "$IMAGE" ]; then
        echo "No image were found in output/images"
        exit 1
    fi
    if ! [[ "$DEPLOY_ON" ]]; then
        echo "The deployment device target should be specified with --deploy-on (See --help)"
        exit 1
    fi

    if ! lsblk "$DEPLOY_ON" 2>/dev/null; then
        echo "Device $DEPLOY_ON is not available"
        exit 1
    fi

    echo "Writing image" "$DEPLOY_ON" "info"
    ifsha=$(cat $IMAGE_SHA | awk '{print $1}')

    [[ -x "$(command -v pv)" ]] || apt-get install -y pv

    pv -p -b -r -c -N "[ .... ] dd" $IMAGE | dd of=$DEPLOY_ON bs=1M iflag=fullblock oflag=direct status=none
    echo "Verifying. Please wait!"
    ofsha=$(dd if=$DEPLOY_ON count=$(du -b $IMAGE | cut -f1) status=none iflag=count_bytes oflag=direct | sha256sum | awk '{print $1}')

    if [[ $ifsha == $ofsha ]]; then
        echo "Writing succeeded" "$IMAGE" "info"
    else
        echo "Writing failed" "$IMAGE" "err"
        exit 1
    fi
fi
