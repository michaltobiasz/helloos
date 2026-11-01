#!/usr/bin/env bash
# Senior OS — buduje własny obraz ISO z oryginalnego ISO Linux Mint XFCE.
#
# Użycie (na komputerze z Linux Mint lub Ubuntu, ok. 15 GB wolnego miejsca):
#   sudo ./build-iso/build-iso.sh linuxmint-xfce-64bit.iso [senior-os.iso]
#
# Co robi: rozpakowuje system z ISO, uruchamia w nim install.sh --iso,
# pakuje z powrotem i zapisuje nowe ISO z zachowaniem oryginalnego rozruchu
# (działa i na UEFI, i na starszym BIOS).
#
# Wersja eksperymentalna — przetestuj ISO w VirtualBox przed nagraniem na pendrive.

set -euo pipefail

ISO_WE="${1:-}"
ISO_WY="${2:-senior-os.iso}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Uruchom przez sudo."; exit 1; }
[ -f "$ISO_WE" ] || { echo "Podaj plik ISO Linux Mint XFCE: sudo $0 mint.iso"; exit 1; }

for prog in xorriso unsquashfs mksquashfs; do
    command -v "$prog" >/dev/null || apt-get install -y xorriso squashfs-tools
done

PRACA=$(mktemp -d /var/tmp/senior-iso.XXXX)
ROOT="$PRACA/root"
sprzatanie() {
    for m in dev/pts dev proc sys run; do umount -lf "$ROOT/$m" 2>/dev/null || true; done
    rm -rf "$PRACA"
}
trap sprzatanie EXIT

echo "==> Rozpakowuję system z ISO"
xorriso -osirrox on -indev "$ISO_WE" \
    -extract /casper/filesystem.squashfs "$PRACA/filesystem.squashfs" \
    -extract /md5sum.txt "$PRACA/md5sum.txt"
unsquashfs -d "$ROOT" "$PRACA/filesystem.squashfs"
rm -f "$PRACA/filesystem.squashfs"

echo "==> Instaluję Senior OS wewnątrz obrazu"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$ROOT/$m"; done
RESOLV_LINK=$(readlink "$ROOT/etc/resolv.conf" || true)
cp --remove-destination /etc/resolv.conf "$ROOT/etc/resolv.conf"
mkdir -p "$ROOT/tmp/senior-os"
cp -r "$REPO/install.sh" "$REPO/ekran-startowy" "$REPO/konfiguracja" "$ROOT/tmp/senior-os/"
chroot "$ROOT" /bin/bash /tmp/senior-os/install.sh --iso
chroot "$ROOT" apt-get clean
rm -rf "$ROOT/tmp/senior-os" "$ROOT/var/lib/apt/lists/"*
for m in dev/pts dev proc sys run; do umount -lf "$ROOT/$m"; done
[ -n "$RESOLV_LINK" ] && ln -sf "$RESOLV_LINK" "$ROOT/etc/resolv.conf"

echo "==> Pakuję system (to potrwa kilkanaście minut)"
mksquashfs "$ROOT" "$PRACA/filesystem.squashfs" -comp xz -noappend
du -sx --block-size=1 "$ROOT" | cut -f1 > "$PRACA/filesystem.size"

# Sumy kontrolne, żeby opcja „sprawdź płytę” nie zgłaszała błędu.
for plik in filesystem.squashfs filesystem.size; do
    suma=$(md5sum "$PRACA/$plik" | cut -d' ' -f1)
    sed -i "s|^[0-9a-f]*  \./casper/$plik\$|$suma  ./casper/$plik|" "$PRACA/md5sum.txt"
done

echo "==> Zapisuję $ISO_WY"
rm -f "$ISO_WY"
xorriso -indev "$ISO_WE" -outdev "$ISO_WY" \
    -map "$PRACA/filesystem.squashfs" /casper/filesystem.squashfs \
    -map "$PRACA/filesystem.size" /casper/filesystem.size \
    -map "$PRACA/md5sum.txt" /md5sum.txt \
    -boot_image any replay

echo "Gotowe: $ISO_WY"
echo "Chrome zainstaluje się sam po pierwszym uruchomieniu z internetem."
