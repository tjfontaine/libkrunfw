#!/bin/sh

# This is a helper script for building the Linux kernel on macOS using
# a lightweight VM with krunvm.

KRUNVM=`which krunvm`
if [ -z "$KRUNVM" ]; then
	echo "Couldn't find krunvm binary"
	exit -1
fi

SCRIPTPATH=`realpath $0`
WORKDIR=`dirname $SCRIPTPATH`
if [ $? != 0 ]; then
	echo "Error creating lightweight VM"
	exit -1
fi

set -e

case $1 in
  prep)
    set +e
    exists=`krunvm list | grep libkrunfw-builder`
    if [ $? != 0 ]; then
      set -e
      echo "Creating build environment"
      krunvm create fedora --name libkrunfw-builder --cpus 2 --mem 2048 -v $WORKDIR:/work -w /work
    fi
    echo "Installing dependencies"
    krunvm start libkrunfw-builder /usr/bin/dnf -- install -qy \
      make gcc glibc-devel findutils xz patch flex bison diffutils bc perl \
      cpio
    ;;
  clean)
    krunvm delete libkrunfw-builder
    ;;
  *)
    krunvm start libkrunfw-builder /usr/bin/make -- -j2
    if [ ! -e "kernel.c" ]; then
      echo "There was a problem building the kernel bundle in the VM"
      exit -1
    fi
    ;;
esac
