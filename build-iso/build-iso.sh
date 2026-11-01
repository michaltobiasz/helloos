#!/usr/bin/env bash
# HelloOS — builds a custom ISO image from the original Linux Mint XFCE ISO.
#
# Usage (on a Linux Mint or Ubuntu computer with ~15 GB free space):
#   sudo ./build-iso/build-iso.sh linuxmint-xfce-64bit.iso [helloos.iso]
#
# What it does: unpacks the system from the ISO, runs install.sh --iso inside it,
# packs it back and writes a new ISO that keeps the original boot setup
# (works on both UEFI and older BIOS computers).
#
# Experimental — test the ISO in VirtualBox before writing it to a USB stick.

set -euo pipefail

ISO_IN="${1:-}"
ISO_OUT="${2:-helloos.iso}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
[ -f "$ISO_IN" ] || { echo "Give a Linux Mint XFCE ISO file: sudo $0 mint.iso"; exit 1; }

for prog in xorriso unsquashfs mksquashfs; do
    command -v "$prog" >/dev/null || apt-get install -y xorriso squashfs-tools
done

WORK=$(mktemp -d /var/tmp/helloos-iso.XXXX)
ROOT="$WORK/root"
cleanup() {
    for m in dev/pts dev proc sys run; do umount -lf "$ROOT/$m" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Unpacking the system from the ISO"
xorriso -osirrox on -indev "$ISO_IN" \
    -extract /casper/filesystem.squashfs "$WORK/filesystem.squashfs" \
    -extract /md5sum.txt "$WORK/md5sum.txt"
unsquashfs -d "$ROOT" "$WORK/filesystem.squashfs"
rm -f "$WORK/filesystem.squashfs"

echo "==> Installing HelloOS inside the image"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$ROOT/$m"; done
RESOLV_LINK=$(readlink "$ROOT/etc/resolv.conf" || true)
cp --remove-destination /etc/resolv.conf "$ROOT/etc/resolv.conf"
mkdir -p "$ROOT/tmp/helloos"
cp -r "$REPO/install.sh" "$REPO/start-screen" "$REPO/config" "$ROOT/tmp/helloos/"
chroot "$ROOT" /bin/bash /tmp/helloos/install.sh --iso
chroot "$ROOT" apt-get clean
rm -rf "$ROOT/tmp/helloos" "$ROOT/var/lib/apt/lists/"*
for m in dev/pts dev proc sys run; do umount -lf "$ROOT/$m"; done
[ -n "$RESOLV_LINK" ] && ln -sf "$RESOLV_LINK" "$ROOT/etc/resolv.conf"

echo "==> Packing the system (this takes a while)"
mksquashfs "$ROOT" "$WORK/filesystem.squashfs" -comp xz -noappend
du -sx --block-size=1 "$ROOT" | cut -f1 > "$WORK/filesystem.size"

# Update checksums so the "check disc for defects" option does not report errors.
for f in filesystem.squashfs filesystem.size; do
    sum=$(md5sum "$WORK/$f" | cut -d' ' -f1)
    sed -i "s|^[0-9a-f]*  \./casper/$f\$|$sum  ./casper/$f|" "$WORK/md5sum.txt"
done

echo "==> Writing $ISO_OUT"
rm -f "$ISO_OUT"
xorriso -indev "$ISO_IN" -outdev "$ISO_OUT" \
    -map "$WORK/filesystem.squashfs" /casper/filesystem.squashfs \
    -map "$WORK/filesystem.size" /casper/filesystem.size \
    -map "$WORK/md5sum.txt" /md5sum.txt \
    -boot_image any replay

echo "Done: $ISO_OUT"
echo "Chrome installs itself on the first boot with internet access."
