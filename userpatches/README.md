# Image customization

## Pre requisite

You need to have docker installed with experimental features enabled:

In your `/etc/docker/daemon.json`, make sure you have

```json
{
    "experimental": true
}
```

Then reload docker with ```systemctl restart docker```.

## Common workflow

The common development workflow is the following:

1. The first time you build an image for a board, run ```./btcpay-build.sh build --board rockpro64```, this will build the kernel, u-boot and the hack0 image for rockpro64.
2. Then, if you modify any document in this folder (`userpatches`), you can recreate an image without re-building the kernel and u-boot with ```./btcpay-build.sh update --board rockpro64```
3. You can also customize the environment variables documented in [BTCPay Server](https://github.com/btcpayserver/btcpayserver-docker) locally by adding them to `overlay/build-local.conf`, this will override [overlay/build.conf](overlay/build.conf) settings. Note that the `build-local.conf` file is ignored when building a production image.
4. Once you are satisfied with the image you can deploy to the device, for example, assuming your SD card is on `/dev/sdd` you would run ```./btcpay-build.sh deploy --deploy-on /dev/sdd```.

Note that you can run several actions at the same time, for example this will update the image and deploy: ```./btcpay-build.sh update deploy --board rockpro64 --deploy-on /dev/sdd```.

During the first start, hack0 is in `setup mode`, the setup mode will:

1. Format any attached SSD or NVMe disk
2. Load docker images
3. Set mount bind so bitcoin's data directory is saved on the SSD/NVMe disk
4. Deploy a UTXO set snapshot in this directory
5. Start BTCPay Server, and test if the connectivity works correctly
6. Stop BTCPay Server and delete data created during the setup mode

For 10 minutes, you will see the red light on and the white light blinking.
When the red light is off, and the white light stopped blinking and stays on, the setup ran successfully. Unplug the hack0, and the unit is ready to be shipped. The next boot will not run in setup mode.

If the red light does not get off, something failed and the hack0 could not be properly configured and you need to flash again the image on the SD Card.

## Architecture

hack0-armbian is a fork of [armbian](https://github.com/armbian/build) with patches specific to hack0.

Here are what our patches do:
1. Format any attached SSD or NVMe disk
2. Load docker images
3. Set mount bind so bitcoin's data directory is saved on the SSD/NVMe disk
4. Deploy a UTXO set snapshot in this directory
5. Setup fan to cool down the processor if it becomes too hot
6. Setup the btcpay-test which signal when the hack0 is ready to be used.
7. Setup mDNS so the local domain name `hack0.local` can be used to find your hack0

`btcpay-test` controls two leds (red and white) on the rock64. When starting, the red light is on, and the white led is blinking. Once hack0 is ready to be used, the red light is off and the white led stays on.

## Pre built images

> :warning: When you first boot a prebuilt images, the hack0 will be in  `setup mode`, which will wipe all data in the SSD drive to the board. Please read `Common workflow` section above.

### Version 0.6

Image: https://hack0-image.s3.amazonaws.com/hack0-rockpro64-0.7.img

sha256sum: 889ebbddfa8c355d570f6e57b68b81cf3dc9df99a069e2ab4d11c38cbc09d704

Release date: 22 July 2022

## FAQ

### How can I change the local domain name?

By default the hack0 will be named `hack0.local` on your network.
If you want to change to `example.local`, add `HACK0_HOSTNAME=example` to `overlay/build-local.conf`.

### How can I configure the image to allow SSH connection with my public key? 

1. Copy your ssh public key in a `overlay/authorized_keys`.
2. In `overlay/build-local.conf`, add `HACK0_LOAD_AUTHORIZED_KEYS=true`.

### How can I create a production image?

A production image will ignore `overlay/build-local.conf`, just run `./btcpay-build.sh build --production`.

### How to customize the BTCPay Server install

We are setting up BTCPay Server thanks to the [docker install](https://github.com/btcpayserver/btcpayserver-docker).
You can customize the environment variables documented in [the repository](https://github.com/btcpayserver/btcpayserver-docker) and add them to `overlay/build-local.conf` to customize your installation.
