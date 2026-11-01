#!/usr/bin/env bash
# shellcheck disable=SC1111
# Senior OS — zamienia świeżo zainstalowanego Linux Mint XFCE w system dla seniora.
#
# Użycie (na komputerze z Linux Mint XFCE, z internetem):
#   sudo ./install.sh                         # ustawia konto, z którego uruchomiono sudo
#   sudo ./install.sh --uzytkownik babcia     # tworzy osobne konto seniora (bez uprawnień admina)
#   sudo ./install.sh --uzytkownik babcia --autologowanie
#   sudo ./install.sh --iso                   # tryb budowania obrazu ISO (używa build-iso.sh)
#
# Skrypt można uruchamiać wiele razy — nic się nie zdubluje.

set -euo pipefail

KATALOG_ZRODLA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CEL=/opt/senior-os
UZYTKOWNIK=""
AUTOLOGOWANIE=0
TRYB_ISO=0
BEZ_RUSTDESK=0

komunikat() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ostrzezenie() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
blad() { printf '\033[1;31m[BŁĄD] %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --uzytkownik) UZYTKOWNIK="${2:-}"; shift 2 ;;
        --autologowanie) AUTOLOGOWANIE=1; shift ;;
        --iso) TRYB_ISO=1; shift ;;
        --bez-rustdesk) BEZ_RUSTDESK=1; shift ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        *) blad "Nieznana opcja: $1 (pomoc: --help)" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || blad "Uruchom przez sudo: sudo ./install.sh"
[ "$(uname -m)" = "x86_64" ] || blad "Potrzebny jest 64-bitowy procesor Intel/AMD (x86_64)."
command -v apt-get >/dev/null || blad "Ten skrypt działa na Linux Mint / Ubuntu / Debian."

if [ "$TRYB_ISO" -eq 0 ] && [ -z "$UZYTKOWNIK" ]; then
    UZYTKOWNIK="${SUDO_USER:-}"
    [ -n "$UZYTKOWNIK" ] && [ "$UZYTKOWNIK" != "root" ] \
        || blad "Podaj konto: sudo ./install.sh --uzytkownik NAZWA"
fi

export DEBIAN_FRONTEND=noninteractive

zainstaluj() {
    # Instaluje pakiety, pomijając te, których nie ma w repozytorium.
    local dostepne=() p
    for p in "$@"; do
        if apt-cache show "$p" >/dev/null 2>&1; then dostepne+=("$p")
        else ostrzezenie "Brak pakietu $p w repozytorium — pomijam."; fi
    done
    [ ${#dostepne[@]} -eq 0 ] || apt-get install -y --no-install-recommends "${dostepne[@]}"
}

# ---------------------------------------------------------------------------
komunikat "1/9 Aktualizacja listy programów"
apt-get update

komunikat "2/9 Instalacja programów (biuro, PDF, wideo, zdjęcia, język polski)"
zainstaluj \
    libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
    libreoffice-l10n-pl libreoffice-help-pl hunspell-pl hyphen-pl mythes-pl \
    xreader xviewer vlc thunar \
    python3-pyqt5 xdg-user-dirs fonts-noto-core \
    language-pack-pl language-pack-gnome-pl \
    wget ca-certificates gpg unattended-upgrades

komunikat "3/9 Pliki Senior OS do $CEL"
mkdir -p "$CEL"
cp -r "$KATALOG_ZRODLA/ekran-startowy" "$KATALOG_ZRODLA/konfiguracja" "$CEL/"
cp "$KATALOG_ZRODLA/install.sh" "$CEL/"
chmod 755 "$CEL/ekran-startowy/ekran_startowy.py" \
          "$CEL/konfiguracja/senior-pierwsze-logowanie.sh" \
          "$CEL/konfiguracja/zainstaluj-chrome.sh"
ln -sf "$CEL/ekran-startowy/ekran_startowy.py" /usr/local/bin/senior-ekran-startowy
install -m 644 "$CEL/konfiguracja/senior-ekran-startowy.desktop" /usr/share/applications/

komunikat "4/9 Przeglądarka Google Chrome"
if [ "$TRYB_ISO" -eq 1 ]; then
    # Licencja Google nie pozwala wbudować Chrome w rozpowszechniany obraz.
    # Zainstaluje się sam przy pierwszym uruchomieniu komputera z internetem.
    install -m 644 "$CEL/konfiguracja/senior-chrome.service" /etc/systemd/system/
    systemctl enable senior-chrome.service 2>/dev/null \
        || ln -sf /etc/systemd/system/senior-chrome.service \
                  /etc/systemd/system/multi-user.target.wants/senior-chrome.service
    zainstaluj chromium   # zapasowa przeglądarka, gdyby nie było internetu
else
    "$CEL/konfiguracja/zainstaluj-chrome.sh" || {
        ostrzezenie "Nie udało się zainstalować Chrome — instaluję Chromium."
        zainstaluj chromium
    }
fi
mkdir -p /etc/opt/chrome/policies/recommended /etc/chromium/policies/recommended
install -m 644 "$CEL/konfiguracja/chrome-polityki.json" /etc/opt/chrome/policies/recommended/senior-os.json
install -m 644 "$CEL/konfiguracja/chrome-polityki.json" /etc/chromium/policies/recommended/senior-os.json

komunikat "5/9 Pomoc zdalna (RustDesk)"
if [ "$BEZ_RUSTDESK" -eq 1 ] || command -v rustdesk >/dev/null; then
    echo "Pomijam (już jest albo wyłączono)."
else
    URL=$(wget -qO- https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
          | grep -o 'https://[^"]*x86_64\.deb' | grep -v sciter | head -1 || true)
    if [ -n "$URL" ] && wget -qO /tmp/rustdesk.deb "$URL"; then
        apt-get install -y /tmp/rustdesk.deb || ostrzezenie "RustDesk nie zainstalował się."
        rm -f /tmp/rustdesk.deb
    else
        ostrzezenie "Nie udało się pobrać RustDesk — przycisk pomocy pokaże komunikat."
    fi
fi

komunikat "6/9 Domyślne programy i LibreOffice w formatach Worda i Excela"
install -m 644 "$CEL/konfiguracja/mimeapps.list" /etc/xdg/mimeapps.list
for katalog in /usr/lib/libreoffice/share/registry /opt/libreoffice*/share/registry; do
    [ -d "$katalog" ] && install -m 644 "$CEL/konfiguracja/libreoffice-senior.xcd" "$katalog/senior-os.xcd"
done

komunikat "7/9 Automatyczne aktualizacje w tle"
if command -v mintupdate-automation >/dev/null; then
    mintupdate-automation upgrade enable || ostrzezenie "Nie udało się włączyć aktualizacji Mint."
fi
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

komunikat "8/9 Ustawienia dla nowych kont i konta seniora"
# /etc/skel: każde nowe konto (także tworzone przez instalator z ISO) dostaje ustawienia.
mkdir -p /etc/skel/.config/autostart /etc/skel/.linuxmint/mintwelcome
install -m 644 "$CEL/konfiguracja/senior-pierwsze-logowanie.desktop" /etc/skel/.config/autostart/
install -m 644 "$CEL/konfiguracja/senior-ekran-startowy.desktop" /etc/skel/.config/autostart/
touch /etc/skel/.linuxmint/mintwelcome/norun.flag

if [ -n "$UZYTKOWNIK" ]; then
    if ! id "$UZYTKOWNIK" >/dev/null 2>&1; then
        echo "Tworzę konto „${UZYTKOWNIK}” (bez uprawnień administratora)."
        useradd -m -s /bin/bash -G audio,video,plugdev,netdev,lpadmin,scanner "$UZYTKOWNIK" 2>/dev/null \
            || useradd -m -s /bin/bash "$UZYTKOWNIK"
        echo "Ustaw hasło dla konta $UZYTKOWNIK:"
        passwd "$UZYTKOWNIK"
    fi
    DOM=$(getent passwd "$UZYTKOWNIK" | cut -d: -f6)
    mkdir -p "$DOM/.config/autostart" "$DOM/.linuxmint/mintwelcome"
    cp "$CEL/konfiguracja/senior-pierwsze-logowanie.desktop" \
       "$CEL/konfiguracja/senior-ekran-startowy.desktop" "$DOM/.config/autostart/"
    touch "$DOM/.linuxmint/mintwelcome/norun.flag"
    rm -f "$DOM/.config/senior-os/skonfigurowano"   # ustawienia nałożą się przy następnym logowaniu
    chown -R "$UZYTKOWNIK:" "$DOM/.config" "$DOM/.linuxmint"

    if [ "$AUTOLOGOWANIE" -eq 1 ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        printf '[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$UZYTKOWNIK" \
            > /etc/lightdm/lightdm.conf.d/70-senior-os.conf
        groupadd -f autologin && usermod -aG autologin "$UZYTKOWNIK"
        echo "Komputer będzie logował konto $UZYTKOWNIK automatycznie."
    fi
fi

komunikat "9/9 Menu startowe (gdy na dysku jest też Windows)"
if [ "$TRYB_ISO" -eq 0 ] && command -v update-grub >/dev/null; then
    if [ -d /boot/efi/EFI/Microsoft ] || { command -v os-prober >/dev/null && os-prober 2>/dev/null | grep -qi windows; }; then
        install -m 644 "$CEL/konfiguracja/grub-senior.cfg" /etc/default/grub.d/99-senior-os.cfg
        update-grub
        echo "Wykryto Windows: Senior OS uruchomi się domyślnie po 3 sekundach."
    else
        echo "Nie wykryto Windowsa — menu startowe bez zmian."
    fi
fi

komunikat "Gotowe!"
echo "Wyloguj się i zaloguj ponownie (albo uruchom komputer ponownie)."
echo "Przy pierwszym logowaniu ustawienia wyglądu nałożą się same."
