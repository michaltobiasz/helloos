#!/usr/bin/env bash
# Pobiera i instaluje Google Chrome z oficjalnej strony Google.
# Chrome dodaje własne źródło aktualizacji, więc dalej aktualizuje się sam.
set -euo pipefail

if command -v google-chrome-stable >/dev/null; then
    echo "Google Chrome jest już zainstalowany."
    exit 0
fi

PLIK=$(mktemp --suffix=.deb)
trap 'rm -f "$PLIK"' EXIT
wget -qO "$PLIK" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PLIK"

# Skrót „Internet” w menu zamiast nazwy „Google Chrome”.
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    mkdir -p /usr/local/share/applications
    sed -e 's/^Name=Google Chrome$/Name=Internet/' \
        -e 's|^Exec=/usr/bin/google-chrome-stable %U$|Exec=/usr/bin/google-chrome-stable --force-device-scale-factor=1.25 %U|' \
        /usr/share/applications/google-chrome.desktop > /usr/local/share/applications/google-chrome.desktop
fi
echo "Google Chrome zainstalowany."
