#!/bin/bash

[ -z "$NOCLEAR" ] &&
	exec env -i NOCLEAR=1 HOME="$HOME" PATH="$PATH" "$0" "$@"

export HOST=aarch64-rpi4-linux-gnu
export CROSS_COMPILE=${HOST}-

SCRIPTDIR=$(dirname $0)
TOOLCHAINDIR=$SCRIPTDIR/../toolchain/$HOST/bin

export PATH=$TOOLCHAINDIR:$PATH


GCC_ARCH=armv8-a
GCC_CPU=cortex-a72

export CC=${CROSS_COMPILE}gcc
export CPP=${CROSS_COMPILE}cpp
export CFLAGS="-O2 -g -march=$GCC_ARCH -mcpu=$GCC_CPU"
export LDFLAGS=""
export LIBS=""
export CPPFLAGS=""

UBOOTVERSION=2020.10-rc5

[[ ! -f u-boot-$UBOOTVERSION.tar.bz2 ]] && \
	wget https://ftp.denx.de/pub/u-boot/u-boot-$UBOOTVERSION.tar.bz2

[[ ! -d u-boot-$UBOOTVERSION ]] && tar -xf u-boot-$UBOOTVERSION.tar.bz2

pushd u-boot-$UBOOTVERSION > /dev/null
make rpi_4_defconfig
make
popd
