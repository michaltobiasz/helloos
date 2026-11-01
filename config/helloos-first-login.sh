#!/usr/bin/env bash
# HelloOS: appearance settings applied once, at the user's first login.
# Runs inside the user's session (xfconf needs a running XFCE desktop).
# To apply them again: delete ~/.config/helloos/configured and log in again.

MARKER="$HOME/.config/helloos/configured"
[ -f "$MARKER" ] && exit 0
sleep 5   # give the XFCE desktop a moment to start

set_prop() {  # set_prop CHANNEL PROPERTY TYPE VALUE — creates it if missing
    xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null \
        || xfconf-query -c "$1" -p "$2" -s "$4" 2>/dev/null || true
}

# Bigger text and cursor
set_prop xsettings /Gtk/FontName string "Noto Sans 14"
set_prop xsettings /Gtk/MonospaceFontName string "Noto Sans Mono 14"
set_prop xsettings /Gtk/CursorThemeSize int 48
set_prop xsettings /Xft/DPI int 110
set_prop xfwm4 /general/title_font string "Noto Sans Bold 14"

# Desktop: big icons, open with a single click
set_prop xfce4-desktop /desktop-icons/icon-size uint 96
set_prop xfce4-desktop /desktop-icons/single-click bool true
set_prop xfce4-desktop /desktop-icons/file-icons/show-filesystem bool false
set_prop xfce4-desktop /desktop-icons/file-icons/show-removable bool true
set_prop xfce4-desktop /desktop-icons/file-icons/show-trash bool true
set_prop thunar /misc-single-click bool true
set_prop thunar /last-view string "ThunarIconView"
set_prop thunar /last-icon-view-zoom-level string "THUNAR_ZOOM_LEVEL_200_PERCENT"

# Taskbar at the bottom: taller, with big icons
for panel in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oE '^/panels/panel-[0-9]+' | sort -u); do
    set_prop xfce4-panel "$panel/size" uint 56
    set_prop xfce4-panel "$panel/icon-size" uint 40
done

# No password lock screen
set_prop xfce4-screensaver /lock/enabled bool false
set_prop xfce4-screensaver /saver/enabled bool false
set_prop xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate bool false
set_prop xfce4-session /shutdown/LockScreen bool false

# User folders in the system language (Documents / Dokumenty, Pictures / Obrazy…)
xdg-user-dirs-update 2>/dev/null || true

# Chrome without the welcome screen
mkdir -p "$HOME/.config/google-chrome" "$HOME/.config/chromium"
touch "$HOME/.config/google-chrome/First Run" "$HOME/.config/chromium/First Run"

# Big desktop shortcuts; Name[pl] makes them Polish on a Polish system
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
mkdir -p "$DESKTOP"
shortcut() {  # shortcut FILE NAME_EN NAME_PL ICON COMMAND
    local file="$DESKTOP/$1.desktop"
    printf '[Desktop Entry]\nType=Application\nName=%s\nName[pl]=%s\nIcon=%s\nExec=%s\nTerminal=false\n' \
        "$2" "$3" "$4" "$5" > "$file"
    chmod +x "$file"
    # XFCE asks "do you trust this launcher?" — mark it as trusted.
    gio set "$file" metadata::xfce-exe-checksum "$(sha256sum "$file" | cut -d' ' -f1)" 2>/dev/null || true
}
shortcut helloos-start "Start screen" "Ekran startowy" go-home /usr/local/bin/helloos-start
shortcut internet "Internet" "Internet" web-browser \
    "sh -c 'google-chrome-stable --force-device-scale-factor=1.25 || chromium --force-device-scale-factor=1.25'"
shortcut documents "My documents" "Moje dokumenty" folder-documents "thunar $(xdg-user-dir DOCUMENTS)"

mkdir -p "$(dirname "$MARKER")"
date > "$MARKER"
