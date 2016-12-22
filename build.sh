#!/bin/bash

set -e

SCRIPTDIR="$(dirname "$0")"
export HERE="$(cd "$SCRIPTDIR" && pwd)"
PREFIX="$HERE/prefix"
PARALLEL="-j 8"

# Set this to false to disable C++ (speed up build a bit).
WITHCXX=false

in_list () {
  local needle=$1
  local haystackname=$2
  local -a haystack
  eval "haystack=( "\${$haystackname[@]}" )"
  for x in "${haystack[@]}"; do
    if [ "$x" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

declare -a BUILDLIST
BUILDLIST=()

while [ $# -gt 0 ]; do
  case "$1" in
    clean|binutils|mklinks|gcc1|newlib|gcc2|sim|test|debug)
      BUILDLIST=( "${BUILDLIST[@]}" $1 )
      ;;
    all)
      BUILDLIST=("clean" "binutils" "mklinks" "gcc1" "newlib" "gcc2" "sim" "test" "debug")
      ;;
    *)
      echo "Unknown option '$1'."
      exit 1
      ;;
  esac
  shift
done

if [ "${#BUILDLIST}" -eq 0 ]; then
  echo "build options: clean binutils mklinks gcc1 newlib gcc2 sim test debug all"
  exit 1
fi

if $WITHCXX; then
  LANGUAGES="c,c++"
  EXTRABUILD2OPTS="--with-newlib"
else
  LANGUAGES="c"
  EXTRABUILD2OPTS=
fi

BIN=$HERE/prefix/bin
if [[ ":$PATH:" != *":$BIN:"* ]]; then
    export PATH="$BIN:${PATH:+"$PATH:"}"
    echo Path set to $PATH
fi

cd "$HERE"
exec > >(tee build.log) 2>&1

if in_list clean BUILDLIST; then
  echo
  echo "************"
  echo "* Cleaning *"
  echo "************"
  echo
  rm -rf "$PREFIX"
  mkdir -p "$PREFIX/bin"
fi

if in_list binutils BUILDLIST; then
  echo
  echo "*********************"
  echo "* Building binutils *"
  echo "*********************"
  echo
  rm -rf build-binutils
  mkdir build-binutils
  pushd build-binutils
  ../binutils-gdb/configure --target=i386-unknown-elf --prefix="$PREFIX"
  make $PARALLEL
  make $PARALLEL install
  popd
fi

if in_list mklinks BUILDLIST; then
  echo
  echo "****************"
  echo "* Making links *"
  echo "****************"
  echo
  pushd "$PREFIX/bin"
  for prog in addr2line ar as c++filt elfedit gdb gprof ld ld.bfd nm objcopy objdump ranlib readelf size strings strip; do
    ln -s i386-unknown-elf-$prog ia16-unknown-elf-$prog
  done
  popd
fi

if in_list gcc1 BUILDLIST; then
  echo
  echo "************************"
  echo "* Building stage 1 GCC *"
  echo "************************"
  echo
  rm -rf build
  mkdir build
  pushd build
  ../gcc-ia16/configure --target=ia16-unknown-elf --prefix="$PREFIX" --without-headers --with-newlib --enable-languages=c --disable-libssp --with-as="$PREFIX/bin/ia16-unknown-elf-as"
#--enable-checking=all,valgrind
  make $PARALLEL
  make $PARALLEL install
  popd
fi

if in_list newlib BUILDLIST; then
  echo
  echo "*****************************"
  echo "* Building Newlib C library *"
  echo "*****************************"
  echo
  rm -rf build-newlib
  mkdir build-newlib
  pushd build-newlib
  ../newlib-ia16/configure --target=ia16-unknown-elf --prefix="$PREFIX"
  make $PARALLEL
  make $PARALLEL install
  popd
fi

if in_list gcc2 BUILDLIST; then
  echo
  echo "************************"
  echo "* Building stage 2 GCC *"
  echo "************************"
  echo
  rm -rf build2
  mkdir build2
  pushd build2
  ../gcc-ia16/configure --target=ia16-unknown-elf --prefix="$PREFIX" --disable-ssp --enable-languages=$LANGUAGES --with-as="$PREFIX/bin/ia16-unknown-elf-as" $EXTRABUILD2OPTS
  make $PARALLEL
  make $PARALLEL install
  popd
fi

if in_list sim BUILDLIST; then
  echo
  echo "**********************"
  echo "* Building simulator *"
  echo "**********************"
  echo
  rm 86sim/86sim
  gcc -Wall -O2 86sim/86sim.cpp -o 86sim/86sim
fi

if in_list test BUILDLIST; then
  echo
  echo "*****************"
  echo "* Running tests *"
  echo "*****************"
  echo
  export DEJAGNU="$HERE/site.exp"
  pushd build2
  make -k check RUNTESTFLAGS="--target_board=86sim"
  grep -E ^FAIL\|^WARNING\|^ERROR\|^XPASS\|^UNRESOLVED gcc/testsuite/gcc/gcc.log > ../fails.txt
  popd
fi

if in_list debug BUILDLIST; then
  echo
  echo "**********************"
  echo "* Building debug GCC *"
  echo "**********************"
  echo
  rm -rf build-debug
  mkdir build-debug
  pushd build-debug
  ../gcc-ia16/configure --target=ia16-unknown-elf --prefix="$PREFIX" --disable-ssp --enable-languages=$LANGUAGES --with-as="$PREFIX/bin/ia16-unknown-elf-as" $EXTRABUILD2OPTS
  make $PARALLEL 'CFLAGS=-g -O0' 'CXXFLAGS=-g -O0' 'BOOT_CFLAGS=-g -O0'
  popd
fi
