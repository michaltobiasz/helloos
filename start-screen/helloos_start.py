#!/usr/bin/env python3
"""HelloOS start screen: big buttons, a clock, nothing else.

For seniors and for children learning to use a computer. The set of buttons
depends on the profile chosen by install.sh (see PROFILES below). The language
follows the system language (Polish or English); set HELLOOS_LANG=pl|en to
force one.

Runs full screen after login. When a program (e.g. the browser) is closed,
the user lands back on this screen.
"""

import os
import shutil
import subprocess
import sys

from PyQt5.QtCore import QDate, QLocale, QSize, Qt, QTime, QTimer
from PyQt5.QtGui import QFont, QIcon
from PyQt5.QtNetwork import QLocalServer, QLocalSocket
from PyQt5.QtWidgets import (
    QApplication,
    QDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

SOCKET_NAME = "helloos-start-" + str(os.getuid())
LOCK_MS = 4000  # after a click the tile waits, so five windows don't open at once
CONFIG_DIR = os.path.expanduser("~/.config/helloos")

BACKGROUND = "#F5F1E8"
TEXT = "#1F1F1F"

# --- Language ---------------------------------------------------------------

TEXTS = {
    "pl": {
        "internet": "Internet", "documents": "Dokumenty", "notepad": "Notatnik",
        "paint": "Paint", "scratch": "Scratch", "videos": "Filmy",
        "pictures": "Zdjęcia", "help": "Pomoc zdalna", "shutdown": "Wyłącz komputer",
        "desktop": "Zwykły pulpit", "opening": "Otwieram…", "title": "Ekran startowy",
        "yes": "Tak", "no": "Nie", "turn_off": "Wyłącz",
        "confirm_shutdown": "Czy na pewno wyłączyć komputer?",
        "not_installed": "Program „{}” nie jest zainstalowany.\nPoproś kogoś o pomoc.",
        "failed": "Nie udało się otworzyć: {}.",
    },
    "en": {
        "internet": "Internet", "documents": "Documents", "notepad": "Notepad",
        "paint": "Paint", "scratch": "Scratch", "videos": "Videos",
        "pictures": "Pictures", "help": "Remote help", "shutdown": "Shut down",
        "desktop": "Desktop", "opening": "Opening…", "title": "Start screen",
        "yes": "Yes", "no": "No", "turn_off": "Shut down",
        "confirm_shutdown": "Do you really want to shut down the computer?",
        "not_installed": "“{}” is not installed.\nAsk someone for help.",
        "failed": "Could not open: {}.",
    },
}


def detect_language():
    forced = os.environ.get("HELLOOS_LANG", "")
    if forced in TEXTS:
        return forced
    return "pl" if QLocale.system().name().startswith("pl") else "en"


LANG = detect_language()
T = TEXTS[LANG]
LOCALE = QLocale(QLocale.Polish, QLocale.Poland) if LANG == "pl" else QLocale(QLocale.English)

# --- Actions ----------------------------------------------------------------


def xdg_folder(kind, fallback):
    """The user's folder (Documents, Pictures…) in the system language."""
    try:
        result = subprocess.run(
            ["xdg-user-dir", kind], capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if result and result != os.path.expanduser("~"):
            return result
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.expanduser(fallback)


def first_available(*commands):
    """The first command whose program is installed."""
    for command in commands:
        if shutil.which(command[0]):
            return command
    return None


def browser():
    return first_available(
        ["google-chrome-stable", "--force-device-scale-factor=1.25"],
        ["google-chrome", "--force-device-scale-factor=1.25"],
        ["chromium", "--force-device-scale-factor=1.25"],
        ["chromium-browser", "--force-device-scale-factor=1.25"],
        ["firefox"],
    )


def open_folder(kind, fallback):
    path = xdg_folder(kind, fallback)
    os.makedirs(path, exist_ok=True)
    return first_available(["thunar", path], ["nemo", path], ["xdg-open", path])


def remote_help():
    return first_available(["rustdesk"])


def notepad():
    return first_available(["xed"], ["mousepad"], ["gedit"])


def flatpak_installed(app_id):
    return bool(shutil.which("flatpak")) and subprocess.run(
        ["flatpak", "info", app_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def paint():
    if shutil.which("pinta"):
        return ["pinta"]
    if flatpak_installed("com.github.PintaProject.Pinta"):
        return ["flatpak", "run", "com.github.PintaProject.Pinta"]
    return first_available(["drawing"], ["tuxpaint"], ["kolourpaint"])


def scratch():
    # TurboWarp is Scratch that works offline; otherwise Scratch in the browser.
    if flatpak_installed("org.turbowarp.TurboWarp"):
        return ["flatpak", "run", "org.turbowarp.TurboWarp"]
    command = browser()
    return command + ["https://scratch.mit.edu/projects/editor/"] if command else None


# key: (theme icon, colour, action) — None as action means "shut down"
TILES = {
    "internet": ("web-browser", "#1565C0", browser),
    "documents": ("folder-documents", "#2E7D32", lambda: open_folder("DOCUMENTS", "~/Documents")),
    "notepad": ("accessories-text-editor", "#455A64", notepad),
    "paint": ("applications-graphics", "#C2185B", paint),
    "scratch": ("applications-development", "#EF6C00", scratch),
    "videos": ("folder-videos", "#6A1B9A", lambda: open_folder("VIDEOS", "~/Videos")),
    "pictures": ("folder-pictures", "#AD1457", lambda: open_folder("PICTURES", "~/Pictures")),
    "help": ("preferences-desktop-remote-desktop", "#00838F", remote_help),
    "shutdown": ("system-shutdown", "#B71C1C", None),
}

# The profile is chosen by install.sh (--profile) and stored in ~/.config/helloos/profile
PROFILES = {
    "senior": ["internet", "documents", "videos", "pictures", "help", "shutdown"],
    "child": ["internet", "documents", "notepad", "paint", "scratch", "shutdown"],
    "all": ["internet", "documents", "notepad", "paint", "scratch",
            "videos", "pictures", "help", "shutdown"],
}
PROFILE_ALIASES = {"dziecko": "child", "wszystko": "all"}


def load_profile():
    try:
        with open(os.path.join(CONFIG_DIR, "profile"), encoding="utf-8") as f:
            name = f.read().strip()
    except OSError:
        name = ""
    name = PROFILE_ALIASES.get(name, name)
    return PROFILES.get(name, PROFILES["all"])


ACTIVE = load_profile()
FEW = len(ACTIVE) <= 6

# --- Interface --------------------------------------------------------------


class BigQuestion(QDialog):
    """A dialog with a big question and two big buttons."""

    def __init__(self, parent, question, yes=None, no=None, ok_only=False):
        super().__init__(parent)
        self.setWindowTitle(" ")
        self.setModal(True)
        self.setStyleSheet(f"background:{BACKGROUND}; color:{TEXT};")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(48, 40, 48, 40)
        layout.setSpacing(32)

        label = QLabel(question)
        label.setWordWrap(True)
        label.setAlignment(Qt.AlignCenter)
        label.setFont(QFont("Sans", 26, QFont.Bold))
        layout.addWidget(label)

        buttons = QHBoxLayout()
        buttons.setSpacing(32)
        if ok_only:
            buttons.addWidget(self._button("OK", "#1565C0", self.accept))
        else:
            # "No" comes first and has focus, so Enter never shuts down by accident.
            buttons.addWidget(self._button(no or T["no"], "#546E7A", self.reject))
            buttons.addWidget(self._button(yes or T["yes"], "#B71C1C", self.accept))
        layout.addLayout(buttons)
        self.setMinimumWidth(640)

    @staticmethod
    def _button(text, colour, action):
        b = QPushButton(text)
        b.setFont(QFont("Sans", 24, QFont.Bold))
        b.setMinimumSize(220, 100)
        b.setCursor(Qt.PointingHandCursor)
        b.setStyleSheet(
            f"QPushButton{{background:{colour}; color:white; border-radius:16px;}}"
            "QPushButton:focus{border:5px solid #FFD600;}"
        )
        b.clicked.connect(action)
        return b


class Tile(QPushButton):
    def __init__(self, text, icon, colour):
        super().__init__(text)
        self.colour = colour
        self.setFont(QFont("Sans", 28 if FEW else 21, QFont.Bold))
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumSize(240, 120)
        themed = QIcon.fromTheme(icon)
        if not themed.isNull():
            self.setIcon(themed)
            self.setIconSize(QSize(72, 72))
        self.set_style()

    def set_style(self, waiting=False):
        bg = "#9E9E9E" if waiting else self.colour
        self.setStyleSheet(
            f"QPushButton{{background:{bg}; color:white; border:none;"
            " border-radius:24px; padding:8px; text-align:center;}"
            "QPushButton:hover{border:6px solid #FFD600;}"
            "QPushButton:focus{border:6px solid #FFD600;}"
        )


class StartScreen(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(T["title"])
        self.setStyleSheet(f"background:{BACKGROUND}; color:{TEXT};")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(56, 36, 56, 24)
        layout.setSpacing(20)

        self.clock = QLabel()
        self.clock.setAlignment(Qt.AlignCenter)
        self.clock.setFont(QFont("Sans", 64 if FEW else 48, QFont.Bold))
        self.date = QLabel()
        self.date.setAlignment(Qt.AlignCenter)
        self.date.setFont(QFont("Sans", 28))
        layout.addWidget(self.clock)
        layout.addWidget(self.date)

        grid = QGridLayout()
        grid.setSpacing(28)
        for i, key in enumerate(ACTIVE):
            icon, colour, action = TILES[key]
            tile = Tile(T[key], icon, colour)
            if action is None:
                tile.clicked.connect(self.shut_down)
            else:
                tile.clicked.connect(
                    lambda _=False, t=tile, a=action, n=T[key]: self.launch(t, a, n))
            grid.addWidget(tile, i // 3, i % 3)
        layout.addLayout(grid, 1)

        bottom = QHBoxLayout()
        bottom.addStretch(1)
        desktop = QPushButton(T["desktop"])
        desktop.setFont(QFont("Sans", 14))
        desktop.setCursor(Qt.PointingHandCursor)
        desktop.setStyleSheet(
            "QPushButton{background:transparent; color:#555; border:2px solid #BBB;"
            " border-radius:10px; padding:8px 16px;}"
        )
        desktop.clicked.connect(self.showMinimized)
        bottom.addWidget(desktop)
        layout.addLayout(bottom)

        self.update_clock()
        timer = QTimer(self)
        timer.timeout.connect(self.update_clock)
        timer.start(1000)

    def update_clock(self):
        self.clock.setText(QTime.currentTime().toString("HH:mm"))
        text = LOCALE.toString(QDate.currentDate(),
                               "dddd, d MMMM yyyy" if LANG == "pl" else "dddd, MMMM d, yyyy")
        self.date.setText(text[:1].upper() + text[1:])

    def launch(self, tile, action, name):
        command = action()
        if not command:
            BigQuestion(self, T["not_installed"].format(name), ok_only=True).exec_()
            return
        try:
            subprocess.Popen(command, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            BigQuestion(self, T["failed"].format(name), ok_only=True).exec_()
            return
        tile.setEnabled(False)
        tile.set_style(waiting=True)
        tile.setText(T["opening"])

        def restore():
            tile.setEnabled(True)
            tile.set_style()
            tile.setText(name)

        QTimer.singleShot(LOCK_MS, restore)

    def shut_down(self):
        if BigQuestion(self, T["confirm_shutdown"],
                       yes=T["turn_off"]).exec_() == QDialog.Accepted:
            subprocess.Popen(["systemctl", "poweroff"])

    def bring_to_front(self):
        self.showFullScreen()
        self.raise_()
        self.activateWindow()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("HelloOS")

    # Single instance: a second launch only brings the first one to the front.
    socket = QLocalSocket()
    socket.connectToServer(SOCKET_NAME)
    if socket.waitForConnected(300):
        socket.write(b"show")
        socket.waitForBytesWritten(300)
        return 0

    QLocalServer.removeServer(SOCKET_NAME)
    server = QLocalServer()
    server.listen(SOCKET_NAME)

    window = StartScreen()
    server.newConnection.connect(
        lambda: (server.nextPendingConnection(), window.bring_to_front()))

    if "--window" in sys.argv or "--okno" in sys.argv:  # for testing
        window.resize(1280, 800)
        window.show()
    else:
        window.showFullScreen()
    return app.exec_()


if __name__ == "__main__":
    sys.exit(main())
