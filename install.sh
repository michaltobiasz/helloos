#!/usr/bin/env bash
# shellcheck disable=SC1111
# HelloOS — turns a fresh Linux Mint XFCE install into a simple system for learning
# to use a computer: for seniors and for primary school children.
#
# Usage (on a computer with Linux Mint XFCE and internet access):
#   sudo ./install.sh                                  # sets up the account that ran sudo
#   sudo ./install.sh --user grandma --profile senior  # creates a separate account (no admin rights)
#   sudo ./install.sh --user ola --profile child --autologin
#   sudo ./install.sh --iso                            # image build mode (used by build-iso.sh)
#
# Profiles: senior | child | all (default). Other options: --no-rustdesk
# Messages are in Polish on a Polish system, otherwise in English.
# Safe to run many times — nothing gets duplicated.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=/opt/helloos
TARGET_USER=""
AUTOLOGIN=0
ISO_MODE=0
NO_RUSTDESK=0
PROFILE=""

case "${LANG:-}" in pl*) PL=1 ;; *) PL=0 ;; esac
t() { if [ "$PL" -eq 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }  # t POLISH ENGLISH

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m[%s] %s\033[0m\n' "$(t BŁĄD ERROR)" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --user|--uzytkownik) TARGET_USER="${2:-}"; shift 2 ;;
        --profile|--profil) PROFILE="${2:-}"; shift 2 ;;
        --autologin|--autologowanie) AUTOLOGIN=1; shift ;;
        --iso) ISO_MODE=1; shift ;;
        --no-rustdesk|--bez-rustdesk) NO_RUSTDESK=1; shift ;;
        -h|--help) sed -n '3,15p' "$0"; exit 0 ;;
        *) die "$(t "Nieznana opcja: $1 (pomoc: --help)" "Unknown option: $1 (see --help)")" ;;
    esac
done

case "$PROFILE" in
    "") ;;
    senior) ;;
    child|dziecko) PROFILE=child ;;
    all|wszystko) PROFILE=all ;;
    *) die "$(t "Profil: senior, child albo all." "Profile must be senior, child or all.")" ;;
esac

[ "$(id -u)" -eq 0 ] || die "$(t "Uruchom przez sudo: sudo ./install.sh" "Run with sudo: sudo ./install.sh")"
[ "$(uname -m)" = "x86_64" ] || die "$(t "Potrzebny jest 64-bitowy procesor Intel/AMD (x86_64)." "A 64-bit Intel/AMD processor (x86_64) is required.")"
command -v apt-get >/dev/null || die "$(t "Ten skrypt działa na Linux Mint / Ubuntu / Debian." "This script works on Linux Mint / Ubuntu / Debian.")"

if [ "$ISO_MODE" -eq 0 ] && [ -z "$TARGET_USER" ]; then
    TARGET_USER="${SUDO_USER:-}"
    [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ] \
        || die "$(t "Podaj konto: sudo ./install.sh --user NAZWA" "Choose an account: sudo ./install.sh --user NAME")"
fi

export DEBIAN_FRONTEND=noninteractive

install_pkgs() {
    # Installs packages, skipping any that are not in the repository.
    local available=() p
    for p in "$@"; do
        # Skip packages with no installation candidate (e.g. removed from this release).
        if apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^(]'; then available+=("$p")
        else warn "$(t "Brak pakietu $p w repozytorium — pomijam." "Package $p not in the repository — skipping.")"; fi
    done
    [ ${#available[@]} -eq 0 ] || apt-get install -y --no-install-recommends "${available[@]}"
}

# ---------------------------------------------------------------------------
step "1/10 $(t "Aktualizacja listy programów" "Updating package lists")"
apt-get update

step "2/10 $(t "Programy: biuro, Notatnik, Paint, PDF, wideo, zdjęcia, języki" "Apps: office, Notepad, Paint, PDF, video, pictures, languages")"
install_pkgs \
    libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
    libreoffice-l10n-pl libreoffice-help-pl libreoffice-help-en-us \
    hunspell-pl hunspell-en-us hyphen-pl mythes-pl \
    xreader xviewer vlc thunar xed pinta drawing tuxpaint flatpak \
    python3-pyqt5 xdg-user-dirs fonts-noto-core \
    language-pack-pl language-pack-gnome-pl language-pack-en \
    wget ca-certificates gpg unattended-upgrades

step "3/10 $(t "Pliki HelloOS do" "HelloOS files to") $DEST"
mkdir -p "$DEST"
cp -r "$SRC/start-screen" "$SRC/config" "$DEST/"
cp "$SRC/install.sh" "$DEST/"
chmod 755 "$DEST/start-screen/helloos_start.py" \
          "$DEST/config/helloos-first-login.sh" \
          "$DEST/config/install-chrome.sh"
ln -sf "$DEST/start-screen/helloos_start.py" /usr/local/bin/helloos-start
install -m 644 "$DEST/config/helloos-start.desktop" /usr/share/applications/

step "4/10 Google Chrome"
if [ "$ISO_MODE" -eq 1 ]; then
    # Google's licence does not allow Chrome inside a redistributed image.
    # It installs itself on the first boot with internet access.
    install -m 644 "$DEST/config/helloos-chrome.service" /etc/systemd/system/
    systemctl enable helloos-chrome.service 2>/dev/null \
        || ln -sf /etc/systemd/system/helloos-chrome.service \
                  /etc/systemd/system/multi-user.target.wants/helloos-chrome.service
    install_pkgs chromium   # fallback browser for offline / live USB use
else
    "$DEST/config/install-chrome.sh" || {
        warn "$(t "Nie udało się zainstalować Chrome — instaluję Chromium." "Could not install Chrome — installing Chromium.")"
        install_pkgs chromium
    }
fi
mkdir -p /etc/opt/chrome/policies/recommended /etc/chromium/policies/recommended
install -m 644 "$DEST/config/chrome-policies.json" /etc/opt/chrome/policies/recommended/helloos.json
install -m 644 "$DEST/config/chrome-policies.json" /etc/chromium/policies/recommended/helloos.json

step "5/10 $(t "Pomoc zdalna (RustDesk)" "Remote help (RustDesk)")"
if [ "$NO_RUSTDESK" -eq 1 ] || command -v rustdesk >/dev/null; then
    t "Pomijam (już jest albo wyłączono)." "Skipping (already installed or disabled)."; echo
else
    URL=$(wget -qO- https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
          | grep -o 'https://[^"]*x86_64\.deb' | grep -v sciter | head -1 || true)
    if [ -n "$URL" ] && wget -qO /tmp/rustdesk.deb "$URL"; then
        apt-get install -y /tmp/rustdesk.deb || warn "$(t "RustDesk nie zainstalował się." "RustDesk failed to install.")"
        rm -f /tmp/rustdesk.deb
    else
        warn "$(t "Nie udało się pobrać RustDesk." "Could not download RustDesk.")"
    fi
fi

step "6/10 $(t "Scratch (TurboWarp) i Paint (Pinta) z Flathuba" "Scratch (TurboWarp) and Paint (Pinta) from Flathub")"
flatpak_app() {  # flatpak_app ID NAME
    if flatpak info "$1" >/dev/null 2>&1; then
        t "$2 jest już zainstalowany." "$2 is already installed."; echo
    elif ! { flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
             && flatpak install -y --noninteractive flathub "$1"; }; then
        warn "$(t "Nie udało się zainstalować: $2." "Could not install: $2.")"
    fi
}
flatpak_app org.turbowarp.TurboWarp "Scratch (TurboWarp)"
# Pinta is no longer packaged in Ubuntu 24.04 / Mint 22 — use Flathub when apt has none.
command -v pinta >/dev/null || flatpak_app com.github.PintaProject.Pinta "Paint (Pinta)"

step "7/10 $(t "Domyślne programy; LibreOffice w formatach Worda i Excela" "Default apps; LibreOffice saving in Word and Excel formats")"
install -m 644 "$DEST/config/mimeapps.list" /etc/xdg/mimeapps.list
for dir in /usr/lib/libreoffice/share/registry /opt/libreoffice*/share/registry; do
    [ -d "$dir" ] && install -m 644 "$DEST/config/libreoffice-helloos.xcd" "$dir/helloos.xcd"
done

step "8/10 $(t "Automatyczne aktualizacje w tle" "Automatic background updates")"
if command -v mintupdate-automation >/dev/null; then
    mintupdate-automation upgrade enable || warn "$(t "Nie udało się włączyć aktualizacji Mint." "Could not enable Mint updates.")"
fi
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

step "9/10 $(t "Ustawienia dla nowych kont i wybranego konta" "Settings for new accounts and the chosen account")"
# /etc/skel: every new account (including one created by the ISO installer) gets the settings.
mkdir -p /etc/skel/.config/autostart /etc/skel/.linuxmint/mintwelcome
install -m 644 "$DEST/config/helloos-first-login.desktop" /etc/skel/.config/autostart/
install -m 644 "$DEST/config/helloos-start.desktop" /etc/skel/.config/autostart/
touch /etc/skel/.linuxmint/mintwelcome/norun.flag

if [ -n "$TARGET_USER" ]; then
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        t "Tworzę konto „${TARGET_USER}” (bez uprawnień administratora)." \
          "Creating account \"${TARGET_USER}\" (without admin rights)."; echo
        useradd -m -s /bin/bash -G audio,video,plugdev,netdev,lpadmin,scanner "$TARGET_USER" 2>/dev/null \
            || useradd -m -s /bin/bash "$TARGET_USER"
        t "Ustaw hasło dla konta $TARGET_USER:" "Set a password for $TARGET_USER:"; echo
        passwd "$TARGET_USER"
    fi
    HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    mkdir -p "$HOME_DIR/.config/autostart" "$HOME_DIR/.config/helloos" "$HOME_DIR/.linuxmint/mintwelcome"
    cp "$DEST/config/helloos-first-login.desktop" \
       "$DEST/config/helloos-start.desktop" "$HOME_DIR/.config/autostart/"
    touch "$HOME_DIR/.linuxmint/mintwelcome/norun.flag"
    echo "${PROFILE:-all}" > "$HOME_DIR/.config/helloos/profile"
    rm -f "$HOME_DIR/.config/helloos/configured"   # settings re-apply at next login
    chown -R "$TARGET_USER:" "$HOME_DIR/.config" "$HOME_DIR/.linuxmint"

    if [ "$AUTOLOGIN" -eq 1 ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        printf '[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n' "$TARGET_USER" \
            > /etc/lightdm/lightdm.conf.d/70-helloos.conf
        groupadd -f autologin && usermod -aG autologin "$TARGET_USER"
        t "Komputer będzie logował konto $TARGET_USER automatycznie." \
          "The computer will log in $TARGET_USER automatically."; echo
    fi
fi

step "10/10 $(t "Menu startowe (gdy na dysku jest też Windows)" "Boot menu (when Windows is also on the disk)")"
if [ "$ISO_MODE" -eq 0 ] && command -v update-grub >/dev/null; then
    if [ -d /boot/efi/EFI/Microsoft ] || { command -v os-prober >/dev/null && os-prober 2>/dev/null | grep -qi windows; }; then
        install -m 644 "$DEST/config/grub-helloos.cfg" /etc/default/grub.d/99-helloos.cfg
        update-grub
        t "Wykryto Windows: HelloOS uruchomi się domyślnie po 3 sekundach." \
          "Windows found: HelloOS will start by default after 3 seconds."; echo
    else
        t "Nie wykryto Windowsa — menu startowe bez zmian." "Windows not found — boot menu unchanged."; echo
    fi
fi

step "$(t "Gotowe!" "Done!")"
t "Wyloguj się i zaloguj ponownie (albo uruchom komputer ponownie)." \
  "Log out and back in (or restart the computer)."; echo
t "Przy pierwszym logowaniu ustawienia wyglądu nałożą się same." \
  "The appearance settings apply automatically at the first login."; echo
