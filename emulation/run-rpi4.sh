
[ -z "$NOCLEAR" ] &&
	exec env -i NOCLEAR=1 HOME="$HOME" PATH="$PATH" "$0" "$@"

SCRIPTDIR=$(dirname $(realpath $0))
TOOLCHAINDIR=$SCRIPTDIR/../toolchain/$HOST/bin
BOOTLOADERDIR=$SCRIPTDIR/../bootloader

CPU=cortex-a72
MEMORY_SIZE=1024

qemu-system-aarch64 -cpu $CPU -m $MEMORY_SIZE -smp 4 \
					-machine virt \
					-bios $BOOTLOADERDIR/u-boot/u-boot.bin \
					-nographic -no-reboot
