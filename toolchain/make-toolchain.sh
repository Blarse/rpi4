#!/bin/bash

# TODO: log instead of '> /dev/null'

[ -z "$NOCLEAR" ] &&
	exec env -i NOCLEAR=1 HOME="$HOME" PATH="$PATH" "$0" "$@"

export ARCH=aarch64
export LINUX_ARCH=arm64
export HOST=x86_64-pc-linux-gnu
export TARGET=aarch64-rpi4-linux-gnu

SCRIPTDIR=$(dirname $(realpath $0))

export PREFIX="$SCRIPTDIR/$TARGET"


WORKDIR="$SCRIPTDIR/work"

SYSROOT="$PREFIX/$TARGET/sysroot"


BUILDTOOLS="$WORKDIR/buildtools"
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
LINUXVERSION=4.19.147

GCC_ARCH=armv8-a
GCC_CPU=cortex-a72

export PATH=$PREFIX/bin:$BUILDTOOLS/bin:$PATH

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
		echo "Using existing $FILE"
	fi
}

extract()
{
	if [[ ! -d "$SOURCEDIR/${1%.*.*}" ]]; then
		echo "Extracting $1 -> $SOURCEDIR/${1%.*.*}"
		tar -xf "$DOWNLOADDIR/$1" -C "$SOURCEDIR"
	else
		echo "Using Existing $SOURCEDIR/${1%.*.*}"
	fi
}

build-gmp()
{
	echo "Building gmp-$GMPVERSION..."
	mkdir -p $BUILDDIR/build-gmp-$GMPVERSION
	pushd $BUILDDIR/build-gmp-$GMPVERSION > /dev/null

	$SOURCEDIR/gmp-$GMPVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
	make -j$(nproc) > /dev/null
	make install > /dev/null

	popd > /dev/null
}

build-mpfr()
{
	echo "Building mpfr-$MPFRVERSION..."
	mkdir -p $BUILDDIR/build-mpfr-$MPFRVERSION
	pushd $BUILDDIR/build-mpfr-$MPFRVERSION > /dev/null

	$SOURCEDIR/mpfr-$MPFRVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
	make -j$(nproc) > /dev/null
	make install > /dev/null

	popd > /dev/null
}

build-mpc()
{
	echo "Building mpc-$MPCVERSION..."
	mkdir -p $BUILDDIR/build-mpc-$MPCVERSION
	pushd $BUILDDIR/build-mpc-$MPCVERSION > /dev/null

	$SOURCEDIR/mpc-$MPCVERSION/configure --prefix=$BUILDTOOLS --build=$HOST > /dev/null
	make -j$(nproc) &> /dev/null
	make install > /dev/null

	popd > /dev/null
}

build-binutils()
{
	echo "Building binutils-$BINUTILSVERSION..."
	mkdir -p $BUILDDIR/build-binutils-$BINUTILSVERSION
	pushd $BUILDDIR/build-binutils-$BINUTILSVERSION > /dev/null

	$SOURCEDIR/binutils-$BINUTILSVERSION/configure \
		CC_FOR_BUILD="/bin/gcc" \
		CFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		CXXFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		LDFLAGS_FOR_BUILD="-L$BUILDTOOLS/lib" \
		CFLAGS="-O2 -g -pipe -I$BUILDTOOLS/include" \
		CXXFLAGS="-O2 -g -pipe -I$BUILDTOOLS/include" \
		LDFLAGS="-L$BUILDTOOLS/lib" \
		--prefix=$PREFIX --with-sysroot=$SYSROOT \
		--build=$HOST --host=$HOST --target=$TARGET \
		--enable-shared --enable-ld=default --enable-gold=yes --enable-plugins \
		--disable-nls --disable-werror --disable-multilib &> /dev/null
	make -j$(nproc) &> /dev/null
	make install &> /dev/null

	mkdir -p $BUILDTOOLS/bin
	ln -s $PREFIX/bin/* $BUILDTOOLS/bin/
	mkdir -p $BUILDTOOLS/$TARGET
	ln -s $PREFIX/$TARGET/bin $BUILDTOOLS/$TARGET/bin

	popd > /dev/null
}

build-gcc-pass1()
{
	echo "Building initial gcc-$GCCVERSION..."
	mkdir -p $BUILDDIR/build-pass1-gcc-$GCCVERSION
	pushd $BUILDDIR/build-pass1-gcc-$GCCVERSION > /dev/null

	$SOURCEDIR/gcc-$GCCVERSION/configure \
		CC_FOR_BUILD="/bin/gcc" \
		CFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		CXXFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		LDFLAGS_FOR_BUILD="-L$BUILDTOOLS/lib" \
		CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		CXXFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		LDFLAGS="-L$BUILDTOOLS/lib" \
		CFLAGS_FOR_TARGET="" \
		CXXFLAGS_FOR_TARGET="" \
		LDFLAGS_FOR_TARGET="" \
		--prefix=$BUILDTOOLS --with-sysroot=$SYSROOT --with-local-prefix=$SYSROOT \
		--build=$HOST --host=$HOST --target=$TARGET \
		--with-newlib --with-arch=$GCC_ARCH --with-cpu=$GCC_CPU \
		--disable-libgomp --disable-libmudflap --disable-libmpx \
		--disable-libssp --disable-libatomic   \
		--disable-libquadmath --disable-libquadmath-support \
		--disable-multilib --disable-nls --disable-shared --disable-threads \
		--with-gmp=$BUILDTOOLS --with-mpfr=$BUILDTOOLS --with-mpc=$BUILDTOOLS \
		--disable-decimal-float --disable-lto --enable-__cxa_atexit \
		--enable-languages=c &> /dev/null

	make -j$(nproc) all-gcc &> /dev/null
	make -j$(nproc) install-gcc &> /dev/null

	mkdir -p $SYSROOT/lib
	mkdir -p $SYSROOT/usr/lib
	ln -sf lib $SYSROOT/lib64
	ln -sf lib $SYSROOT/usr/lib64

	popd > /dev/null
}

build-kernel-headers()
{
	echo "Building linux-$LINUXVERSION headers..."
	pushd $SOURCEDIR/linux-$LINUXVERSION #> /dev/null
	make mrproper #> /dev/null
	make ARCH=$LINUX_ARCH headers_check #> /dev/null
	make ARCH=$LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT/usr headers_install #> /dev/null

	popd #> /dev/null
}

build-glibc-headers()
{
	echo "Building glibc-$GLIBCVERSION headers.."
	mkdir -p $BUILDDIR/build-glibc-$GLIBCVERSION-headers
	pushd $BUILDDIR/build-glibc-$GLIBCVERSION-headers

	$SOURCEDIR/glibc-$GLIBCVERSION/configure \
		BUILD_CC="/bin/gcc" LD="$TARGET-ld" \
		CC="$TARGET-gcc -O2 -mlittle-endian -mcpu=$GCC_CPU" \
		AS="$TARGET-as" AR="$TARGET-ar" RANLIB="$TARGET-ranlib" \
		--prefix=/usr --with-headers=$SYSROOT/usr/include \
		--build=$HOST --host=$TARGET \
		--enable-kernel=$LINUXVERSION \
		--disable-werror \
		libc_cv_forced_unwind=yes \
		libc_cv_c_cleanup=yes


	make -j$(nproc) CXX="" BUILD_CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		 BUILD_CPPFLAGS="" BUILD_LDFLAGS="-L$BUILDTOOLS/lib" \
		 install-bootstrap-headers=yes install-headers \
		 cross_compiling=yes install_root=$SYSROOT

	cp $SOURCEDIR/glibc-$GLIBCVERSION/include/features.h $SYSROOT/usr/include/features.h
	cp bits/stdio_lim.h $SYSROOT/usr/include/stdio_lim.h

	make -j$(nproc) CXX="" BUILD_CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		 BUILD_CPPFLAGS="" BUILD_LDFLAGS="-L$BUILDTOOLS/lib" \
		 csu/subdir_lib

	cp csu/crt1.o csu/crti.o csu/crtn.o $SYSROOT/usr/lib

	$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null \
				-o $SYSROOT/usr/lib/libc.so

	touch $SYSROOT/usr/include/gnu/stubs.h

	popd
}

build-gcc-pass2()
{

	echo "Building gcc-$GCCVERSION pass2..."
	mkdir -p $BUILDDIR/build-pass2-gcc-$GCCVERSION
	pushd $BUILDDIR/build-pass2-gcc-$GCCVERSION > /dev/null

	$SOURCEDIR/gcc-$GCCVERSION/configure \
		CC_FOR_BUILD="/bin/gcc" \
		CFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		CXXFLAGS_FOR_BUILD="-O2 -g -I$BUILDTOOLS/include" \
		LDFLAGS_FOR_BUILD="-L$BUILDTOOLS/lib" \
		CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		CXXFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		LDFLAGS="-L$BUILDTOOLS/lib" \
		CFLAGS_FOR_TARGET="" \
		CXXFLAGS_FOR_TARGET="" \
		LDFLAGS_FOR_TARGET="" \
		--prefix=$BUILDTOOLS --with-sysroot=$SYSROOT --with-local-prefix=$SYSROOT \
		--build=$HOST --host=$HOST --target=$TARGET \
		--with-newlib --with-arch=$GCC_ARCH --with-cpu=$GCC_CPU \
		--disable-libgomp --disable-libmudflap --disable-libmpx \
		--disable-libssp --disable-libatomic   \
		--disable-libquadmath --disable-libquadmath-support \
		--disable-multilib --disable-nls --disable-shared --disable-threads \
		--with-gmp=$BUILDTOOLS --with-mpfr=$BUILDTOOLS --with-mpc=$BUILDTOOLS \
		--disable-decimal-float --disable-lto --enable-__cxa_atexit \
		--enable-languages=c &> /dev/null

	# make -j$(nproc) configure-gcc configure-libcpp configure-build-libiberty
	# make -j$(nproc) all-libcpp all-build-libiberty
	# make -j$(nproc) configure-libdecnumber
	# make -j$(nproc) libdecnumber libdecnumber.a
	# make -j$(nproc) configure-libbacktrace
	# make -j$(nproc) libbacktrace
	# make -j$(nproc) -C gcc libgcc.mvars
	make -j$(nproc) all-gcc all-target-libgcc
	make -j$(nproc) install-gcc install-target-libgcc

	ln -s libgcc.a $BUILDTOOLS/lib/gcc/$TARGET/$GCCVERSION/libgcc_sh.a

	popd > /dev/null
}

build-glibc-final()
{
	echo "Building glibc-$GLIBCVERSION final..."
	mkdir -p $BUILDDIR/build-glibc-$GLIBCVERSION-final
	pushd $BUILDDIR/build-glibc-$GLIBCVERSION-final > /dev/null

	$SOURCEDIR/glibc-$GLIBCVERSION/configure \
		BUILD_CC="/bin/gcc" LD="$TARGET-ld" \
		CC="$TARGET-gcc -O2 -mlittle-endian -mcpu=$GCC_CPU" \
		AS="$TARGET-as" AR="$TARGET-ar" RANLIB="$TARGET-ranlib" \
		--prefix=/usr --with-headers=$SYSROOT/usr/include \
		--build=$HOST --host=$TARGET \
		--enable-kernel=$LINUXVERSION \
		--disable-werror \
		libc_cv_forced_unwind=yes \
		libc_cv_c_cleanup=yes

	make -j$(nproc) CXX="" BUILD_CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		 BUILD_CPPFLAGS="" BUILD_LDFLAGS="-L$BUILDTOOLS/lib" \
		 install_root="$SYSROOT" all &> /dev/null

	make -j$(nproc) CXX="" BUILD_CFLAGS="-O2 -g -I$BUILDTOOLS/include" \
		 BUILD_CPPFLAGS="" BUILD_LDFLAGS="-L$BUILDTOOLS/lib" \
		 install_root="$SYSROOT" install &> /dev/null

	popd > /dev/null
}

build-gcc-final()
{
	echo "Building final gcc-$GCCVERSION..."
	mkdir -p $BUILDDIR/build-gcc-$GCCVERSION-final
	pushd $BUILDDIR/build-gcc-$GCCVERSION-final > /dev/null

	$SOURCEDIR/gcc-$GCCVERSION/configure \
		CC_FOR_BUILD="/bin/gcc" \
		CFLAGS="-O2 -g -pipe -I$BUILDTOOLS/include" \
		CFLAGS_FOR_BUILD="-O2 -g -pipe -I$BUILDTOOLS/include" \
		CXXFLAGS="-O2 -g -pipe -I$BUILDTOOLS/include" \
		CXXFLAGS_FOR_BUILD="-O2 -g -pipe -I$BUILDTOOLS/include" \
		LDFLAGS="-L$BUILDTOOLS/lib -lstdc++ -lm" \
		CFLAGS_FOR_TARGET="" \
		CXXFLAGS_FOR_TARGET="" \
		LDFLAGS_FOR_TARGET="" \
		--prefix=$PREFIX --with-sysroot=$SYSROOT --with-local-prefix=$SYSROOT \
		--build=$HOST --host=$HOST --target=$TARGET \
		--with-arch=$GCC_ARCH --with-cpu=$GCC_CPU \
		--disable-libgomp --disable-libmudflap --disable-libmpx \
		--disable-libssp --disable-libsanitizer \
		--disable-libquadmath --disable-libquadmath-support \
		--disable-multilib --disable-nls --enable-threads=posix \
		--with-gmp=$BUILDTOOLS --with-mpfr=$BUILDTOOLS --with-mpc=$BUILDTOOLS \
		--disable-multilib --disable-lto \
		--enable-plugin --enable-gold --enable-__cxa_atexit --enable-long-long\
		--enable-languages=c,c++ &> /dev/null

	make -j$(nproc) all &> /dev/null
	make -j$(nproc) install &> /dev/null

	popd > /dev/null
}

download-all()
{
	[[ ! -d "$DOWNLOADDIR" ]] && mkdir -p "$DOWNLOADDIR"

	echo "Source code download:"
	download https://ftp.gnu.org/gnu/gmp/gmp-$GMPVERSION.tar.xz
	download https://ftp.gnu.org/gnu/mpfr/mpfr-$MPFRVERSION.tar.xz
	download https://ftp.gnu.org/gnu/mpc/mpc-$MPCVERSION.tar.gz
	download https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILSVERSION.tar.xz
	download https://ftp.gnu.org/gnu/gcc/gcc-$GCCVERSION/gcc-$GCCVERSION.tar.xz
	download https://cdn.kernel.org/pub/linux/kernel/v${LINUXVERSION:0:1}.x/linux-$LINUXVERSION.tar.xz
	download https://ftp.gnu.org/gnu/glibc/glibc-$GLIBCVERSION.tar.xz
	download https://ftp.gnu.org/gnu/gdb/gdb-$GDBVERSION.tar.xz
}

extract-all()
{
	[[ ! -d "$SOURCEDIR" ]] && mkdir "$SOURCEDIR"

	echo "Extracting sources:"
	extract gmp-$GMPVERSION.tar.xz
	extract mpfr-$MPFRVERSION.tar.xz
	extract mpc-$MPCVERSION.tar.gz
	extract binutils-$BINUTILSVERSION.tar.xz
	extract gcc-$GCCVERSION.tar.xz
	extract linux-$LINUXVERSION.tar.xz
	extract glibc-$GLIBCVERSION.tar.xz
	extract gdb-$GDBVERSION.tar.xz
}

build-all()
{
	[[ ! -d "$BUILDDIR" ]] && mkdir "$BUILDDIR"

	echo "Building toolchain:"
	build-gmp
	build-mpfr
	build-mpc
	build-binutils
	build-gcc-pass1
	build-kernel-headers
	build-glibc-headers
	build-gcc-pass2
	build-glibc-final
	build-gcc-final
}

#############################################
#############################################
#############################################

pushd $SCRIPTDIR > /dev/null

download-all
extract-all
build-all

popd > /dev/null
