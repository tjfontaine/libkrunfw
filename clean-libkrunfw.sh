#!/usr/bin/env bash
#
# clean-libkrunfw.sh - selective clean of libkrunfw kernel build artifacts.
#
# Why this exists:
#   On macOS the default filesystem (APFS) is case-insensitive. The Linux
#   kernel source tree contains BOTH `Documentation/Kbuild` (a build-system
#   file used by Kbuild itself) AND `Documentation/kbuild/` (a directory of
#   documentation). On a case-sensitive FS these are distinct; on a
#   case-insensitive FS they collide, and `make clean` (which walks the
#   tree and touches Kbuild files) blows up.
#
#   This script sidesteps `make clean` entirely and just removes the
#   build artifacts we actually care about, leaving `.config` in place
#   so we don't have to reconfigure the kernel.
#

set -e
set -u

# Operate from the script's own directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect the kernel source dir (first match for linux-*).
KERNEL_DIR=""
for d in linux-*/; do
    if [ -d "$d" ]; then
        KERNEL_DIR="${d%/}"
        break
    fi
done

if [ -z "$KERNEL_DIR" ]; then
    echo "error: no linux-* kernel source directory found under $SCRIPT_DIR" >&2
    exit 1
fi

echo "cleaning kernel source: $KERNEL_DIR"
cd "$KERNEL_DIR"

echo "deleting .o files..."
find . -type f -name '*.o' -delete

echo "deleting .ko files..."
find . -type f -name '*.ko' -delete

echo "deleting .*.cmd files..."
find . -type f -name '.*.cmd' -delete

echo "deleting top-level build artifacts..."
rm -f \
    vmlinux \
    vmlinux.o \
    vmlinux.unstripped \
    vmlinux.symvers \
    vmlinux.btf \
    System.map \
    Module.symvers

echo "done. (.config preserved)"
