<p align="center"><img src="icon/AppIcon.png" width="128" alt="BeamerFix-Icon"></p>

# BeamerFix

Ein Klick in der Menüleiste, und das Bild am Konferenzraum-Display stimmt.

Viele Konferenzraum-Systeme (z. B. Lenovo ThinkSmart mit Teams Rooms / Zoom Rooms) lesen das Bild vom
USB-C-/HDMI-Kabel über einen *Ingest* ein, der intern auf 1080p arbeitet. Windows-Laptops schicken dort
von sich aus 1920 × 1080 @ 60 Hz, Macs dagegen oft 4K, 16:10, skalierte HiDPI-Modi oder krumme
Bildraten – das Ergebnis ist ein verzerrtes, unscharfes Bild. Über die Systemeinstellungen lässt sich
das häufig nicht beheben, weil macOS den passenden Modus versteckt.

BeamerFix erzwingt genau diesen Modus.

## Bedienung

| Aktion | Wirkung |
|---|---|
| **Klick** auf das Menüleisten-Symbol | Alle externen Displays → 1920 × 1080 @ 60 Hz ohne HiDPI (Fallback: 1280 × 720) |
| Rückfrage „Ist das Bild jetzt in Ordnung?“ | Bestätigen, sonst wird nach 15 s automatisch zurückgestellt |
| **Nochmal klicken** (Symbol zeigt ✓) | Alles wie vorher |
| **Rechtsklick → Beamer 16:10 (1920 × 1200)** | Für Beamer mit WUXGA-Panel, direkt per HDMI angeschlossen – passt zum 16:10 des MacBooks, keine Balken |
| **Rechtsklick** | „Bei Anmeldung starten“ an/aus · Beenden |

Änderungen gelten nur bis zum Abstecken bzw. Abmelden – BeamerFix verstellt nichts dauerhaft.

**Welche Auflösung wann?** Konferenzraum-Systeme (Teams Rooms, Zoom Rooms, Capture-Karten) arbeiten
intern mit 1080p – dafür ist der normale Klick da. 1920 × 1200 nur bei einem Beamer ohne Raumsystem
dazwischen. 4K ist bewusst nicht dabei: Am Ingest ist es gerade das Problem, an einem direkt
angeschlossenen 4K-TV macht macOS es selbst richtig.

## Installation

**Einfach:** Unter [Releases](https://github.com/tobymarks/beamerfix/releases/latest) `BeamerFix.zip`
laden, entpacken, nach *Programme* ziehen. Signiert und von Apple notarisiert – keine Warnung beim Start.

**Aus dem Quellcode:**

```sh
git clone https://github.com/tobymarks/beamerfix.git
cd beamerfix
./build.sh install      # baut und kopiert nach /Applications
```

Voraussetzungen: macOS 13 oder neuer, Xcode Command Line Tools (`xcode-select --install`).
Das Ergebnis ist ein Universal-Binary (Apple Silicon + Intel).

Ein lokaler Build ist nur ad-hoc signiert und läuft ohne Warnung nur auf dem Mac, auf dem er gebaut
wurde. Für eine weitergebbare Version:

```sh
# einmalig: API-Key aus App Store Connect als notarytool-Profil hinterlegen
xcrun notarytool store-credentials beamerfix-notary --key AuthKey_XXX.p8 --key-id XXX --issuer <Issuer-UUID>

./build.sh release        # Developer ID signieren, notarisieren, stapeln → build/BeamerFix.zip
```

## Kommandozeilen-Tool

`./build.sh` baut zusätzlich `build/beamerfix` für Diagnose und Sonderfälle:

```sh
beamerfix                   # externes Display auf 1080p60 (mit Rückfrage)
beamerfix list              # alle Displays und alle Modi, auch versteckte
beamerfix set 1280x720@60   # bestimmten Modus setzen
beamerfix mirror|unmirror   # MacBook-Bildschirm auf extern spiegeln / aufheben
```

## Grenzen

BeamerFix wählt nur unter den Modi, die der Mac anbietet. Es überschreibt nicht die EDID des
Displays und ändert weder Farbformat noch HDR-Signalisierung. Bietet der Ingest gar kein sauberes
1080p an, hilft nur ein HDMI-EDID-Emulator auf der Raumseite.

## Aufbau

```
Sources/main.swift      Menüleisten-App (AppKit, CoreGraphics, ServiceManagement)
cli/beamerfix.swift     Kommandozeilen-Tool
icon/make-icon.swift    erzeugt icon/AppIcon.icns
build.sh                Build + Installation
```
