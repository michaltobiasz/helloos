#!/usr/bin/env bash
# Senior OS: ustawienia wyglądu nakładane raz, przy pierwszym logowaniu seniora.
# Działa w sesji użytkownika (xfconf wymaga uruchomionego pulpitu XFCE).
# Żeby nałożyć je ponownie: usuń ~/.config/senior-os/skonfigurowano i zaloguj się.

ZNACZNIK="$HOME/.config/senior-os/skonfigurowano"
[ -f "$ZNACZNIK" ] && exit 0
sleep 5   # chwila, aż pulpit XFCE wystartuje

ustaw() {  # ustaw KANAŁ WŁAŚCIWOŚĆ TYP WARTOŚĆ — tworzy, jeśli nie istnieje
    xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null \
        || xfconf-query -c "$1" -p "$2" -s "$4" 2>/dev/null || true
}

# Większe litery i kursor
ustaw xsettings /Gtk/FontName string "Noto Sans 14"
ustaw xsettings /Gtk/MonospaceFontName string "Noto Sans Mono 14"
ustaw xsettings /Gtk/CursorThemeSize int 48
ustaw xsettings /Xft/DPI int 110
ustaw xfwm4 /general/title_font string "Noto Sans Bold 14"

# Pulpit: duże ikony, otwieranie jednym kliknięciem
ustaw xfce4-desktop /desktop-icons/icon-size uint 96
ustaw xfce4-desktop /desktop-icons/single-click bool true
ustaw xfce4-desktop /desktop-icons/file-icons/show-filesystem bool false
ustaw xfce4-desktop /desktop-icons/file-icons/show-removable bool true
ustaw xfce4-desktop /desktop-icons/file-icons/show-trash bool true
ustaw thunar /misc-single-click bool true
ustaw thunar /last-view string "ThunarIconView"
ustaw thunar /last-icon-view-zoom-level string "THUNAR_ZOOM_LEVEL_200_PERCENT"

# Pasek zadań na dole: wyższy, z dużymi ikonami
for panel in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oE '^/panels/panel-[0-9]+' | sort -u); do
    ustaw xfce4-panel "$panel/size" uint 56
    ustaw xfce4-panel "$panel/icon-size" uint 40
done

# Bez blokady ekranu hasłem i bez zbędnych powiadomień
ustaw xfce4-screensaver /lock/enabled bool false
ustaw xfce4-screensaver /saver/enabled bool false
ustaw xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate bool false
ustaw xfce4-session /shutdown/LockScreen bool false

# Polskie foldery: Dokumenty, Obrazy, Wideo, Pobrane
xdg-user-dirs-update 2>/dev/null || true

# Chrome bez ekranu powitalnego
mkdir -p "$HOME/.config/google-chrome" "$HOME/.config/chromium"
touch "$HOME/.config/google-chrome/First Run" "$HOME/.config/chromium/First Run"

# Duże skróty na pulpicie
PULPIT=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Pulpit")
mkdir -p "$PULPIT"
skrot() {  # skrot PLIK NAZWA IKONA POLECENIE
    local plik="$PULPIT/$1.desktop"
    printf '[Desktop Entry]\nType=Application\nName=%s\nIcon=%s\nExec=%s\nTerminal=false\n' \
        "$2" "$3" "$4" > "$plik"
    chmod +x "$plik"
    # XFCE pyta „czy ufasz temu skrótowi?” — oznaczamy jako zaufany.
    gio set "$plik" metadata::xfce-exe-checksum "$(sha256sum "$plik" | cut -d' ' -f1)" 2>/dev/null || true
}
skrot ekran-startowy "Ekran startowy" go-home /usr/local/bin/senior-ekran-startowy
skrot internet "Internet" web-browser \
    "sh -c 'google-chrome-stable --force-device-scale-factor=1.25 || chromium --force-device-scale-factor=1.25'"
skrot dokumenty "Moje dokumenty" folder-documents "thunar $(xdg-user-dir DOCUMENTS)"

mkdir -p "$(dirname "$ZNACZNIK")"
date > "$ZNACZNIK"
