#!/usr/bin/env python3
"""Ekran startowy: duże przyciski, zegar, nic zbędnego.

Dla seniorów i dla dzieci uczących się obsługi komputera (profil wybiera
install.sh). Zestaw przycisków jest w słowniku PROFILE poniżej.

Uruchamia się po zalogowaniu na pełnym ekranie. Po zamknięciu programu
(np. przeglądarki) senior wraca do tego ekranu.
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
    QSizePolicy,
    QDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

NAZWA_GNIAZDA = "senior-os-ekran-startowy-" + str(os.getuid())
BLOKADA_MS = 4000  # po kliknięciu przycisk czeka, by nie otworzyć 5 okien naraz

TLO = "#F5F1E8"
TEKST = "#1F1F1F"


def folder_xdg(rodzaj, zapasowy):
    """Zwraca polski folder użytkownika (np. Dokumenty), także gdy nie istnieje."""
    try:
        wynik = subprocess.run(
            ["xdg-user-dir", rodzaj], capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if wynik and wynik != os.path.expanduser("~"):
            return wynik
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.expanduser(zapasowy)


def pierwszy_dostepny(*polecenia):
    """Pierwsze polecenie, którego program jest zainstalowany."""
    for polecenie in polecenia:
        if shutil.which(polecenie[0]):
            return polecenie
    return None


def internet():
    return pierwszy_dostepny(
        ["google-chrome-stable", "--force-device-scale-factor=1.25"],
        ["google-chrome", "--force-device-scale-factor=1.25"],
        ["chromium", "--force-device-scale-factor=1.25"],
        ["chromium-browser", "--force-device-scale-factor=1.25"],
        ["firefox"],
    )


def otworz_folder(rodzaj, zapasowy):
    sciezka = folder_xdg(rodzaj, zapasowy)
    os.makedirs(sciezka, exist_ok=True)
    return pierwszy_dostepny(["thunar", sciezka], ["nemo", sciezka], ["xdg-open", sciezka])


def pomoc():
    return pierwszy_dostepny(["rustdesk"])


def notatnik():
    return pierwszy_dostepny(["xed"], ["mousepad"], ["gedit"])


def paint():
    return pierwszy_dostepny(["pinta"], ["tuxpaint"], ["kolourpaint"])


def scratch():
    # TurboWarp to Scratch działający bez internetu; zapasowo Scratch w przeglądarce.
    if shutil.which("flatpak") and subprocess.run(
        ["flatpak", "info", "org.turbowarp.TurboWarp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0:
        return ["flatpak", "run", "org.turbowarp.TurboWarp"]
    przegladarka = internet()
    return przegladarka + ["https://scratch.mit.edu/projects/editor/"] if przegladarka else None


# nazwa: (napis, ikona z motywu systemu, kolor, akcja)
WSZYSTKIE = {
    "internet": ("Internet", "web-browser", "#1565C0", internet),
    "dokumenty": ("Dokumenty", "folder-documents", "#2E7D32",
                  lambda: otworz_folder("DOCUMENTS", "~/Dokumenty")),
    "notatnik": ("Notatnik", "accessories-text-editor", "#455A64", notatnik),
    "paint": ("Paint", "applications-graphics", "#C2185B", paint),
    "scratch": ("Scratch", "applications-development", "#EF6C00", scratch),
    "filmy": ("Filmy", "folder-videos", "#6A1B9A",
              lambda: otworz_folder("VIDEOS", "~/Wideo")),
    "zdjecia": ("Zdjęcia", "folder-pictures", "#AD1457",
                lambda: otworz_folder("PICTURES", "~/Obrazy")),
    "pomoc": ("Pomoc zdalna", "preferences-desktop-remote-desktop", "#00838F", pomoc),
    "wylacz": ("Wyłącz komputer", "system-shutdown", "#B71C1C", None),  # osobne pytanie
}

# Profil wybiera się w install.sh (--profil); zapisany jest w ~/.config/senior-os/profil
PROFILE = {
    "senior": ["internet", "dokumenty", "filmy", "zdjecia", "pomoc", "wylacz"],
    "dziecko": ["internet", "dokumenty", "notatnik", "paint", "scratch", "wylacz"],
    "wszystko": ["internet", "dokumenty", "notatnik", "paint", "scratch",
                 "filmy", "zdjecia", "pomoc", "wylacz"],
}


def wczytaj_profil():
    try:
        with open(os.path.expanduser("~/.config/senior-os/profil"), encoding="utf-8") as f:
            nazwa = f.read().strip()
    except OSError:
        nazwa = ""
    return PROFILE.get(nazwa, PROFILE["wszystko"])


KAFELKI = [WSZYSTKIE[n] for n in wczytaj_profil()]


class DuzePytanie(QDialog):
    """Okno z dużym pytaniem i dwoma dużymi przyciskami Tak / Nie."""

    def __init__(self, rodzic, pytanie, tak="Tak", nie="Nie", tylko_ok=False):
        super().__init__(rodzic)
        self.setWindowTitle(" ")
        self.setModal(True)
        self.setStyleSheet(f"background:{TLO}; color:{TEKST};")
        uklad = QVBoxLayout(self)
        uklad.setContentsMargins(48, 40, 48, 40)
        uklad.setSpacing(32)

        etykieta = QLabel(pytanie)
        etykieta.setWordWrap(True)
        etykieta.setAlignment(Qt.AlignCenter)
        etykieta.setFont(QFont("Sans", 26, QFont.Bold))
        uklad.addWidget(etykieta)

        przyciski = QHBoxLayout()
        przyciski.setSpacing(32)
        if tylko_ok:
            przyciski.addWidget(self._przycisk("OK", "#1565C0", self.accept))
        else:
            przyciski.addWidget(self._przycisk(nie, "#546E7A", self.reject))
            przyciski.addWidget(self._przycisk(tak, "#B71C1C", self.accept))
        uklad.addLayout(przyciski)
        self.setMinimumWidth(640)

    @staticmethod
    def _przycisk(napis, kolor, akcja):
        p = QPushButton(napis)
        p.setFont(QFont("Sans", 24, QFont.Bold))
        p.setMinimumSize(220, 100)
        p.setCursor(Qt.PointingHandCursor)
        p.setStyleSheet(
            f"QPushButton{{background:{kolor}; color:white; border-radius:16px;}}"
            "QPushButton:focus{border:5px solid #FFD600;}"
        )
        p.clicked.connect(akcja)
        return p


class Kafelek(QPushButton):
    def __init__(self, napis, ikona, kolor):
        super().__init__(napis)
        self.kolor = kolor
        self.setFont(QFont("Sans", 28 if len(KAFELKI) <= 6 else 21, QFont.Bold))
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumSize(240, 120)
        ik = QIcon.fromTheme(ikona)
        if not ik.isNull():
            self.setIcon(ik)
            self.setIconSize(QSize(72, 72))
        self.ustaw_styl()

    def ustaw_styl(self, czeka=False):
        tlo = "#9E9E9E" if czeka else self.kolor
        self.setStyleSheet(
            f"QPushButton{{background:{tlo}; color:white; border:none;"
            " border-radius:24px; padding:8px; text-align:center;}"
            "QPushButton:hover{border:6px solid #FFD600;}"
            "QPushButton:focus{border:6px solid #FFD600;}"
        )


class EkranStartowy(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Ekran startowy")
        self.setStyleSheet(f"background:{TLO}; color:{TEKST};")
        self.locale = QLocale(QLocale.Polish, QLocale.Poland)

        uklad = QVBoxLayout(self)
        uklad.setContentsMargins(56, 36, 56, 24)
        uklad.setSpacing(20)

        self.zegar = QLabel()
        self.zegar.setAlignment(Qt.AlignCenter)
        self.zegar.setFont(QFont("Sans", 64 if len(KAFELKI) <= 6 else 48, QFont.Bold))
        self.data = QLabel()
        self.data.setAlignment(Qt.AlignCenter)
        self.data.setFont(QFont("Sans", 28))
        uklad.addWidget(self.zegar)
        uklad.addWidget(self.data)

        siatka = QGridLayout()
        siatka.setSpacing(28)
        for i, (napis, ikona, kolor, akcja) in enumerate(KAFELKI):
            k = Kafelek(napis, ikona, kolor)
            if akcja is None:
                k.clicked.connect(self.wylacz)
            else:
                k.clicked.connect(lambda _=False, k=k, a=akcja, n=napis: self.uruchom(k, a, n))
            siatka.addWidget(k, i // 3, i % 3)
        uklad.addLayout(siatka, 1)

        dol = QHBoxLayout()
        dol.addStretch(1)
        pulpit = QPushButton("Zwykły pulpit")
        pulpit.setFont(QFont("Sans", 14))
        pulpit.setCursor(Qt.PointingHandCursor)
        pulpit.setStyleSheet(
            "QPushButton{background:transparent; color:#555; border:2px solid #BBB;"
            " border-radius:10px; padding:8px 16px;}"
        )
        pulpit.clicked.connect(self.showMinimized)
        dol.addWidget(pulpit)
        uklad.addLayout(dol)

        self.odswiez_zegar()
        t = QTimer(self)
        t.timeout.connect(self.odswiez_zegar)
        t.start(1000)

    def odswiez_zegar(self):
        self.zegar.setText(QTime.currentTime().toString("HH:mm"))
        tekst = self.locale.toString(QDate.currentDate(), "dddd, d MMMM yyyy")
        self.data.setText(tekst[:1].upper() + tekst[1:])

    def uruchom(self, kafelek, akcja, napis):
        polecenie = akcja()
        if not polecenie:
            DuzePytanie(self, f"Program „{napis}” nie jest zainstalowany.\n"
                              "Poproś rodzinę o pomoc.", tylko_ok=True).exec_()
            return
        try:
            subprocess.Popen(polecenie, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            DuzePytanie(self, f"Nie udało się otworzyć: {napis}.", tylko_ok=True).exec_()
            return
        kafelek.setEnabled(False)
        kafelek.ustaw_styl(czeka=True)
        kafelek.setText("Otwieram…")

        def przywroc():
            kafelek.setEnabled(True)
            kafelek.ustaw_styl()
            kafelek.setText(napis)

        QTimer.singleShot(BLOKADA_MS, przywroc)

    def wylacz(self):
        if DuzePytanie(self, "Czy na pewno wyłączyć komputer?",
                       tak="Wyłącz", nie="Nie").exec_() == QDialog.Accepted:
            subprocess.Popen(["systemctl", "poweroff"])

    def pokaz_na_wierzchu(self):
        self.showFullScreen()
        self.raise_()
        self.activateWindow()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Ekran startowy")

    # Tylko jedna kopia: druga tylko przywołuje pierwszą na wierzch.
    gniazdo = QLocalSocket()
    gniazdo.connectToServer(NAZWA_GNIAZDA)
    if gniazdo.waitForConnected(300):
        gniazdo.write(b"pokaz")
        gniazdo.waitForBytesWritten(300)
        return 0

    QLocalServer.removeServer(NAZWA_GNIAZDA)
    serwer = QLocalServer()
    serwer.listen(NAZWA_GNIAZDA)

    okno = EkranStartowy()
    serwer.newConnection.connect(lambda: (serwer.nextPendingConnection(), okno.pokaz_na_wierzchu()))

    if "--okno" in sys.argv:  # do testów
        okno.resize(1280, 800)
        okno.show()
    else:
        okno.showFullScreen()
    return app.exec_()


if __name__ == "__main__":
    sys.exit(main())
