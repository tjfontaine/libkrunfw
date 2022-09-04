#!/bin/sh

# This is a helper script for building the Linux kernel on macOS using
# a lightweight VM with krunvm.

BVCPU=${BUILDER_VCPUS:-2}
BMEM=${BUILDER_MEM:-2048}
BNAME=${BUILDER_NAME:-"libkrunfw-builder"}

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
    exists=`krunvm list | grep ${BNAME}`
    if [ $? != 0 ]; then
      set -e
      echo "Creating build environment"
      krunvm create fedora --name ${BNAME} --cpus ${BVCPU} --mem ${BMEM} -v $WORKDIR:/work -w /work
    fi
    echo "Installing dependencies"
    krunvm start ${BNAME} /usr/bin/dnf -- install -qy \
      make gcc glibc-devel findutils xz patch flex bison diffutils bc perl \
      cpio
    ;;
  config)
    krunvm start ${BNAME} /usr/bin/dnf -- install -qy ncurses-devel
    krunvm start ${BNAME} /usr/bin/make -- config
    ;;
  clean)
    krunvm delete ${BNAME}
    ;;
  *)
    krunvm start ${BNAME} /usr/bin/make -- -j${BVPU}
    if [ ! -e "kernel.c" ]; then
      echo "There was a problem building the kernel bundle in the VM"
      exit -1
    fi
    ;;
esac
