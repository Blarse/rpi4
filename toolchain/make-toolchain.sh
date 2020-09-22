#!/bin/bash


HOST=x86_64-pc-linux-gnu
TARGET=aarch64-rpi4-linux-gnu
PREFIX="$PWD/$TARGET"
SYSROOT="$PREFIX/sysroot"

SOURCEDIR="$PWD/sources"
BUILDDIR="$PWD/build"

BINUTILSVERSION=2.35
GCCVERSION=10.2.0
GLIBCVERSION=2.32
GDBVERSION=9.2
GMPVERSION=6.2.0
MPCVERSION=1.2.0
MPFRVERSION=4.1.0
LINUXVERSION=4.19.146

[[ ! -d $SOURCEDIR ]] && mkdir -p $SOURCEDIR
echo "Sysroot: $SYSROOT"
panic()
{
	echo "$1" >&2
	exit 1
}

clean()
{
	rm -rf $BUILDDIR{,.old}
}

download()
{
	FILE="$(basename "$1")"

	if [[ ! -f "$SOURCEDIR/$FILE" ]]; then
		echo "Downloading $FILE..."
		wget "$1" -P $SOURCEDIR 2> /dev/null
	else
		echo "$FILE is already here"
	fi
}

extract()
{
	if [[ -z $2 ]]; then
		DESTDIR=$BUILDDIR
	else
		DESTDIR=$2
	fi
	echo "Extracting $1 -> $DESTDIR/${1%.*.*}"
	[[ ! -d "$DESTDIR/${1%.*.*}" ]] && tar -xf "$SOURCEDIR/$1" -C "$DESTDIR" #TODO: mb rm test

}

# get sources
echo "Source code download:"
download https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILSVERSION.tar.xz
download https://ftp.gnu.org/gnu/gcc/gcc-$GCCVERSION/gcc-$GCCVERSION.tar.xz
download https://ftp.gnu.org/gnu/gmp/gmp-$GMPVERSION.tar.xz
download https://ftp.gnu.org/gnu/mpc/mpc-$MPCVERSION.tar.gz
download https://ftp.gnu.org/gnu/mpfr/mpfr-$MPFRVERSION.tar.xz
download https://ftp.gnu.org/gnu/glibc/glibc-$GLIBCVERSION.tar.xz
download https://ftp.gnu.org/gnu/gdb/gdb-$GDBVERSION.tar.xz
download https://cdn.kernel.org/pub/linux/kernel/v$(echo $LINUXVERSION | cut - -c1).x/linux-$LINUXVERSION.tar.xz

[[ ! -d "$BUILDDIR" ]] && mkdir "$BUILDDIR"

echo ""
echo "Extracting sources:"
extract binutils-$BINUTILSVERSION.tar.xz
extract gcc-$GCCVERSION.tar.xz

extract gmp-$GMPVERSION.tar.xz $BUILDDIR/gcc-$GCCVERSION
extract mpc-$MPCVERSION.tar.gz $BUILDDIR/gcc-$GCCVERSION
extract mpfr-$MPFRVERSION.tar.xz $BUILDDIR/gcc-$GCCVERSION

mv $BUILDDIR/gcc-$GCCVERSION/{gmp-$GMPVERSION,gmp}
mv $BUILDDIR/gcc-$GCCVERSION/{mpc-$MPCVERSION,mpc}
mv $BUILDDIR/gcc-$GCCVERSION/{mpfr-$MPFRVERSION,mpfr}

extract glibc-$GLIBCVERSION.tar.xz
extract gdb-$GDBVERSION.tar.xz

extract linux-$LINUXVERSION.tar.xz


# Binutils
mkdir $BUILDDIR/binutils-$BINUTILSVERSION/build
pushd $BUILDDIR/binutils-$BINUTILSVERSION/build > /dev/null
../configure --prefix=$PREFIX --with-sysroot=$SYSROOT \
			 --target=$TARGET --host=$HOST --enable-shared \
			 --disable-nls --disable-werror --disable-multilib
make -j4
make install
popd > /dev/null
