#!/bin/sh

# build_on_krunvm_persistent.sh — like build_on_krunvm_fedora.sh, but
# keeps the `libkrunfw-builder` microVM around between invocations.
# The first run still pays the full provisioning cost (dnf install +
# `cargo install bindgen-cli` + `dnf builddep -y kernel`), but every
# subsequent run skips straight to `make -j8` against the kernel
# tree mounted at /work.
#
# The kernel tree's `.config` and per-source object files live on the
# host's `linux-6.12.76/` directory (-v $WORKDIR:/work mount in the
# VM), so make's incremental dependency tracking works across
# invocations even if you re-create the VM by hand.  What the
# persistent VM gets you is reuse of the *toolchain* (rustc/cargo/
# bindgen/clang/llvm/dwarves/etc.) and the kernel-builddep package
# set, both of which are bulky and slow to re-fetch.
#
# Idempotency is tracked via a sentinel file inside the mounted
# /work tree: `.libkrunfw-builder.provisioned` is touched once the
# dnf installs + bindgen install + kernel-builddep have all
# completed.  Delete it (or `krunvm delete libkrunfw-builder`) to
# force a re-provision.
#
# Tear down explicitly with: `krunvm delete libkrunfw-builder`.

set -e

KRUNVM=$(which krunvm)
if [ -z "$KRUNVM" ]; then
    echo "Couldn't find krunvm binary" >&2
    exit 1
fi

# realpath does not exist by default on macOS; install via brew
# coreutils if missing.
SCRIPTPATH=$(realpath "$0")
WORKDIR=$(dirname "$SCRIPTPATH")
VM_NAME="libkrunfw-builder"
SENTINEL="$WORKDIR/.libkrunfw-builder.provisioned"

vm_exists() {
    krunvm list 2>/dev/null | grep -qE "^$VM_NAME\$"
}

if vm_exists; then
    echo "[persistent] reusing existing microVM '$VM_NAME'"
else
    echo "[persistent] creating microVM '$VM_NAME' (cpus=8, mem=8192)"
    krunvm create fedora --name "$VM_NAME" --cpus 8 --mem 8192 \
        -v "$WORKDIR:/work" -w /work
    if [ $? -ne 0 ]; then
        echo "Error creating lightweight VM" >&2
        exit 1
    fi
    # New VM ⇒ force a re-provision regardless of any leftover sentinel.
    rm -f "$SENTINEL"
fi

if [ ! -f "$SENTINEL" ]; then
    echo "[persistent] provisioning toolchain (one-time, ~5-10 min)"

    krunvm start "$VM_NAME" /usr/bin/dnf -- install -y \
        'dnf-command(builddep)' python3-pyelftools rust cargo \
        rustfmt rust-src clang llvm dwarves
    if [ $? -ne 0 ]; then
        echo "Error installing dnf packages on VM" >&2
        exit 1
    fi

    # bindgen-cli is needed for the Rust bindings generator
    # (drivers/bifrost is in-tree Rust).  dnf doesn't ship it; install
    # via cargo into ~root/.cargo on the VM.
    krunvm start "$VM_NAME" /usr/bin/cargo -- install bindgen-cli
    if [ $? -ne 0 ]; then
        echo "Error installing bindgen-cli on VM" >&2
        exit 1
    fi

    krunvm start "$VM_NAME" /usr/bin/dnf -- builddep -y kernel
    if [ $? -ne 0 ]; then
        echo "Error installing kernel build deps" >&2
        exit 1
    fi

    touch "$SENTINEL"
    echo "[persistent] provisioned ($SENTINEL written)"
else
    echo "[persistent] toolchain already provisioned (sentinel: $SENTINEL)"
fi

echo "[persistent] running make -j8"
# bindgen is installed under /root/.cargo; PATH needs adjustment.
krunvm start "$VM_NAME" /usr/bin/sh -- -c 'export PATH=/root/.cargo/bin:$PATH; cd /work && make -j8'
if [ $? -ne 0 ]; then
    echo "Error running make in VM" >&2
    exit 1
fi

if [ ! -e "$WORKDIR/kernel.c" ]; then
    echo "kernel.c missing after build — make likely failed silently" >&2
    exit 1
fi

echo "[persistent] build OK; VM '$VM_NAME' kept alive for subsequent runs"
echo "[persistent]   tear down with: krunvm delete $VM_NAME"

exit 0
