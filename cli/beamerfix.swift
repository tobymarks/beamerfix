// beamerfix – erzwingt eine saubere Ausgabe-Auflösung (Standard: 1920x1080 @ 60 Hz, ohne HiDPI)
// auf externen Displays, z. B. an Konferenzraum-Systemen mit HDMI-/USB-C-Ingest.
//
// Bauen:   swiftc -O beamerfix.swift -o beamerfix
// Nutzung: ./beamerfix                 interaktiv: externes Display wählen, 1080p60 setzen
//          ./beamerfix list            alle Displays + verfügbare Modi anzeigen
//          ./beamerfix set 1920x1080@60 [--display N]   Modus direkt setzen
//          ./beamerfix mirror          internes Display auf das externe spiegeln
//          ./beamerfix unmirror        Spiegelung aufheben

import CoreGraphics
import Foundation

// MARK: - Helpers

struct Mode {
    let raw: CGDisplayMode
    var width: Int { raw.width }            // logische Punkte
    var height: Int { raw.height }
    var pixelWidth: Int { raw.pixelWidth }  // tatsächliche Pixel
    var pixelHeight: Int { raw.pixelHeight }
    var hz: Double { raw.refreshRate }
    var hiDPI: Bool { pixelWidth > width }
    var label: String {
        let hzText = hz > 0 ? String(format: "%.2f Hz", hz) : "? Hz"
        return "\(width)x\(height)  \(hzText)" + (hiDPI ? "  (HiDPI, \(pixelWidth)x\(pixelHeight) px)" : "")
    }
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func externalDisplays() -> [CGDirectDisplayID] {
    onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 }
}

func modes(for id: CGDirectDisplayID) -> [Mode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let list = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
    return list.map(Mode.init)
        .filter { $0.raw.isUsableForDesktopGUI() }
        .sorted { ($0.pixelWidth, $0.pixelHeight, $0.hz) > ($1.pixelWidth, $1.pixelHeight, $1.hz) }
}

func currentMode(_ id: CGDirectDisplayID) -> Mode? {
    CGDisplayCopyDisplayMode(id).map(Mode.init)
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let kind = CGDisplayIsBuiltin(id) != 0 ? "intern" : "extern"
    let mirror = CGDisplayIsInMirrorSet(id) != 0 ? ", gespiegelt" : ""
    let cur = currentMode(id)?.label ?? "?"
    return "Display \(id) [\(kind)\(mirror)] \(Int(b.width))x\(Int(b.height)) – aktuell: \(cur)"
}

/// Bester Treffer: exakte Pixel-Auflösung, kein HiDPI bevorzugt, Bildrate am nächsten am Ziel.
func findMode(_ id: CGDirectDisplayID, w: Int, h: Int, hz: Double) -> Mode? {
    modes(for: id)
        .filter { $0.pixelWidth == w && $0.pixelHeight == h }
        .min { a, b in
            if a.hiDPI != b.hiDPI { return !a.hiDPI }
            return abs(a.hz - hz) < abs(b.hz - hz)
        }
}

func apply(_ mode: Mode, to id: CGDirectDisplayID) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    CGConfigureDisplayWithDisplayMode(cfg, id, mode.raw, nil)
    // .forSession: gilt bis Abmelden/Abstecken – nichts wird dauerhaft verstellt.
    return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
}

/// Setzt den Modus und fragt nach – ohne "j" innerhalb von 15 s wird zurückgestellt.
func applyWithConfirm(_ mode: Mode, to id: CGDirectDisplayID) {
    guard let previous = currentMode(id) else { fail("Aktueller Modus nicht lesbar.") }
    print("→ Setze \(mode.label) …")
    guard apply(mode, to: id) else { fail("Modus konnte nicht gesetzt werden.") }

    print("Ist das Bild jetzt OK? [j/N] (automatisch zurück in 15 s) ", terminator: "")
    fflush(stdout)
    var answer: String?
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { answer = readLine(); sem.signal() }
    let timedOut = sem.wait(timeout: .now() + 15) == .timedOut

    if !timedOut, let a = answer?.lowercased(), a.hasPrefix("j") || a.hasPrefix("y") {
        print("✓ Behalten.")
    } else {
        print(timedOut ? "\n⏱  Keine Antwort – stelle zurück." : "↩︎ Stelle zurück.")
        _ = apply(previous, to: id)
    }
}

func parseMode(_ s: String) -> (Int, Int, Double)? {
    // "1920x1080" oder "1920x1080@60"
    let parts = s.lowercased().split(separator: "@")
    let wh = parts[0].split(separator: "x")
    guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]) else { return nil }
    let hz = parts.count > 1 ? Double(parts[1]) ?? 60 : 60
    return (w, h, hz)
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("✗ " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

func pickExternal(_ requested: CGDirectDisplayID?) -> CGDirectDisplayID {
    let ext = externalDisplays()
    if let r = requested {
        guard onlineDisplays().contains(r) else { fail("Display \(r) nicht gefunden.") }
        return r
    }
    guard !ext.isEmpty else { fail("Kein externes Display gefunden. Kabel eingesteckt?") }
    if ext.count == 1 { return ext[0] }
    print("Mehrere externe Displays:")
    for (i, id) in ext.enumerated() { print("  [\(i + 1)] \(describe(id))") }
    print("Welches? ", terminator: "")
    guard let line = readLine(), let n = Int(line), (1...ext.count).contains(n) else { fail("Abgebrochen.") }
    return ext[n - 1]
}

// MARK: - Commands

var args = Array(CommandLine.arguments.dropFirst())
var requestedDisplay: CGDirectDisplayID?
if let i = args.firstIndex(of: "--display"), i + 1 < args.count, let n = UInt32(args[i + 1]) {
    requestedDisplay = n
    args.removeSubrange(i...(i + 1))
}

switch args.first {
case "list":
    for id in onlineDisplays() {
        print(describe(id))
        for m in modes(for: id) { print("    " + m.label) }
        print()
    }

case "set":
    guard args.count > 1, let (w, h, hz) = parseMode(args[1]) else { fail("Format: set 1920x1080@60") }
    let id = pickExternal(requestedDisplay)
    guard let m = findMode(id, w: w, h: h, hz: hz) else {
        fail("Display \(id) bietet \(w)x\(h) nicht an. Verfügbare Modi: ./beamerfix list")
    }
    applyWithConfirm(m, to: id)

case "mirror":
    let ext = pickExternal(requestedDisplay)
    guard let internalID = onlineDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
        fail("Kein internes Display gefunden.")
    }
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    // Internes Display spiegelt das externe → Auflösung richtet sich nach dem Beamer/TV.
    CGConfigureDisplayMirrorOfDisplay(cfg, internalID, ext)
    print(CGCompleteDisplayConfiguration(cfg, .forSession) == .success ? "✓ Gespiegelt (Master: extern)." : "✗ Fehlgeschlagen.")

case "unmirror":
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    for id in onlineDisplays() { CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay) }
    print(CGCompleteDisplayConfiguration(cfg, .forSession) == .success ? "✓ Spiegelung aufgehoben." : "✗ Fehlgeschlagen.")

case nil:
    // Interaktiver Standard: externes Display → 1920x1080 @ 60 Hz, ohne HiDPI
    let id = pickExternal(requestedDisplay)
    print(describe(id))
    if let m = findMode(id, w: 1920, h: 1080, hz: 60) {
        applyWithConfirm(m, to: id)
    } else {
        print("1920x1080 wird nicht angeboten. Verfügbare Modi:")
        let all = modes(for: id)
        for (i, m) in all.enumerated() { print("  [\(i + 1)] \(m.label)") }
        print("Nummer wählen: ", terminator: "")
        guard let line = readLine(), let n = Int(line), (1...all.count).contains(n) else { fail("Abgebrochen.") }
        applyWithConfirm(all[n - 1], to: id)
    }

default:
    print("""
    beamerfix – saubere Auflösung für externe Displays erzwingen

      beamerfix                      externes Display auf 1920x1080 @ 60 Hz (ohne HiDPI)
      beamerfix list                 Displays und alle Modi anzeigen
      beamerfix set 1280x720@60      bestimmten Modus setzen
      beamerfix mirror | unmirror    internes Display auf extern spiegeln / aufheben
      --display <ID>                 bestimmtes Display (ID aus 'list')

    Änderungen gelten nur bis zum Abstecken/Abmelden.
    """)
}
