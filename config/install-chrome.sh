#!/usr/bin/env bash
# Downloads and installs Google Chrome from Google's official site.
# Chrome adds its own update source, so it keeps updating itself.
set -euo pipefail

if command -v google-chrome-stable >/dev/null; then
    echo "Google Chrome is already installed."
    exit 0
fi

DEB=$(mktemp --suffix=.deb)
trap 'rm -f "$DEB"' EXIT
wget -qO "$DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEB"

# Menu entry called "Internet" instead of "Google Chrome", with bigger page zoom.
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    mkdir -p /usr/local/share/applications
    sed -e 's/^Name=Google Chrome$/Name=Internet/' \
        -e '/^Name\[[^]]*\]=Google Chrome$/d' \
        -e 's|^Exec=/usr/bin/google-chrome-stable %U$|Exec=/usr/bin/google-chrome-stable --force-device-scale-factor=1.25 %U|' \
        /usr/share/applications/google-chrome.desktop > /usr/local/share/applications/google-chrome.desktop
fi
echo "Google Chrome installed."
