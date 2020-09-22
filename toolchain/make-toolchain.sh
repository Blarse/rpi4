#!/bin/bash

# TODO: log instead of '> /dev/null'
# TODO: setup clean environment

TARGET_ARCH=arm64
HOST=x86_64-pc-linux-gnu
TARGET=aarch64-rpi4-linux-gnu

GCC_ARCH=armv8-a
GCC_CPU=cortex-a72

PREFIX="$PWD/the-toolchain"
WORKDIR="$PWD/work"

SYSROOT="$PREFIX/$TARGET/sysroot"

BUILDTOOLS="$WORKDIR/host-tools"
DOWNLOADDIR="$WORKDIR/tarballs"
SOURCEDIR="$WORKDIR/sources"
BUILDDIR="$WORKDIR/build"

BINUTILSVERSION=2.35
GCCVERSION=10.2.0
GLIBCVERSION=2.32
GDBVERSION=9.2
GMPVERSION=6.2.0
MPCVERSION=1.2.0
MPFRVERSION=4.1.0
LINUXVERSION=4.19.146


panic()
{
	echo "$1" >&2
	exit 1
}

clean()
{
	rm -rf $BUILDDIR
}

download()
{
	FILE="$(basename "$1")"

	if [[ ! -f "$DOWNLOADDIR/$FILE" ]]; then
		echo "Downloading $FILE..."
		wget "$1" -P $DOWNLOADDIR 2> /dev/null
	else
		echo "$FILE is already here"
	fi
}

extract()
{
	if [[ -z $2 ]]; then
		DESTDIR=$SOURCEDIR
	else
		DESTDIR=$2
	fi
	echo "Extracting $1 -> $DESTDIR/${1%.*.*}"
	[[ ! -d "$DESTDIR/${1%.*.*}" ]] && tar -xf "$DOWNLOADDIR/$1" -C "$DESTDIR"

}

# get sources
[[ ! -d "$DOWNLOADDIR" ]] && mkdir -p "$DOWNLOADDIR"

echo "Source code download:"
download https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILSVERSION.tar.xz
download https://ftp.gnu.org/gnu/gcc/gcc-$GCCVERSION/gcc-$GCCVERSION.tar.xz
download https://ftp.gnu.org/gnu/gmp/gmp-$GMPVERSION.tar.xz
download https://ftp.gnu.org/gnu/mpc/mpc-$MPCVERSION.tar.gz
download https://ftp.gnu.org/gnu/mpfr/mpfr-$MPFRVERSION.tar.xz
download https://ftp.gnu.org/gnu/glibc/glibc-$GLIBCVERSION.tar.xz
download https://ftp.gnu.org/gnu/gdb/gdb-$GDBVERSION.tar.xz
download https://cdn.kernel.org/pub/linux/kernel/v${LINUXVERSION:0:1}.x/linux-$LINUXVERSION.tar.xz


[[ ! -d "$SOURCEDIR" ]] && mkdir "$SOURCEDIR"

echo ""
echo "Extracting sources:"
extract binutils-$BINUTILSVERSION.tar.xz
extract gcc-$GCCVERSION.tar.xz

extract gmp-$GMPVERSION.tar.xz # $SOURCEDIR/gcc-$GCCVERSION
extract mpc-$MPCVERSION.tar.gz # $SOURCEDIR/gcc-$GCCVERSION
extract mpfr-$MPFRVERSION.tar.xz # $SOURCEDIR/gcc-$GCCVERSION

#mv $SOURCEDIR/gcc-$GCCVERSION/{gmp-$GMPVERSION,gmp}
#mv $SOURCEDIR/gcc-$GCCVERSION/{mpc-$MPCVERSION,mpc}
#mv $SOURCEDIR/gcc-$GCCVERSION/{mpfr-$MPFRVERSION,mpfr}

extract glibc-$GLIBCVERSION.tar.xz
extract gdb-$GDBVERSION.tar.xz

extract linux-$LINUXVERSION.tar.xz

[[ ! -d "$BUILDDIR" ]] && mkdir "$BUILDDIR"

echo ""
echo "Building Host Tools:"

echo "Building gmp-$GMPVERSION..."
mkdir -p $BUILDDIR/build-gmp-$GMPVERSION
pushd $BUILDDIR/build-gmp-$GMPVERSION > /dev/null

$SOURCEDIR/gmp-$GMPVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
make -j$(nproc) > /dev/null
make install > /dev/null

popd > /dev/null

echo "Building mpfr-$MPFRVERSION..."
mkdir -p $BUILDDIR/build-mpfr-$MPFRVERSION
pushd $BUILDDIR/build-mpfr-$MPFRVERSION > /dev/null

$SOURCEDIR/mpfr-$MPFRVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
make -j$(nproc) > /dev/null
make install > /dev/null

popd > /dev/null

echo "Building mpc-$MPCVERSION..."
mkdir -p $BUILDDIR/build-mpc-$MPCVERSION
pushd $BUILDDIR/build-mpc-$MPCVERSION > /dev/null

$SOURCEDIR/mpc-$MPCVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
make -j$(nproc) &> /dev/null
make install > /dev/null

popd > /dev/null

echo "Building binutils-$BINUTILSVERSION..."
mkdir -p $BUILDDIR/build-binutils-$BINUTILSVERSION
pushd $BUILDDIR/build-binutils-$BINUTILSVERSION > /dev/null

$SOURCEDIR/binutils-$BINUTILSVERSION/configure \
	--prefix=$PREFIX --with-sysroot=$SYSROOT \
	--build=$HOST --host=$HOST --target=$TARGET \
	--enable-shared --enable-ld=yes --enable-gold=yes --enable-plugins \
	--disable-nls --disable-werror --disable-multilib &> /dev/null
make configure-host &> /dev/null
make -j$(nproc) &> /dev/null
make install &> /dev/null

popd > /dev/null

echo "Building linux-$LINUXVERSION headers..."
pushd $SOURCEDIR/linux-$LINUXVERSION > /dev/null
make mrproper > /dev/null
make ARCH=$TARGET_ARCH headers_check > /dev/null
make ARCH=$TARGET_ARCH INSTALL_HDR_PATH=$SYSROOT/usr headers_install > /dev/null

popd > /dev/null


# GCC
echo "Building initial gcc-$GCCVERSION..."
mkdir -p $BUILDDIR/build-gcc-$GCCVERSION
pushd $BUILDDIR/build-gcc-$GCCVERSION > /dev/null
read -p "config"
$SOURCEDIR/gcc-$GCCVERSION/configure \
	--prefix=$BUILDTOOLS --with-sysroot=$SYSROOT --with-local-prefix=$SYSROOT \
	--build=$HOST --host=$HOST --target=$TARGET \
	--disable-nls --disable-shared --without-headers --with-newlib \
	--disable-decimal-float --disable-libgomp --disable-libmudflap \
	--disable-libssp --disable-libatomic --disable-threads --disable-libmpx \
	--disable-libquadmath-support --disable-libquadmath --disable-multilib \
	--with-gmp=$BUILDTOOLS --with-mpfr=$BUILDTOOLS --with-mpc=$BUILDTOOLS \
	--with-arch=$GCC_ARCH --with-cpu=$GCC_CPU \
	--enable-languages=c --with-gnu-as --with-gnu-ld

make -j$(nproc) all-gcc all-target-libgcc
make install-gcc install-target-libgcc


popd > /dev/null
