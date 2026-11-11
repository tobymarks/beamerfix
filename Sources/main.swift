// BeamerFix – Menüleisten-App: externe Displays auf saubere Auflösung zwingen.
// Bauen: ./build.sh  (erzeugt build/BeamerFix.app)

import AppKit
import CoreGraphics
import ServiceManagement

// MARK: - Display-Logik

struct Mode {
    let raw: CGDisplayMode
    var width: Int { raw.width }
    var height: Int { raw.height }
    var pixelWidth: Int { raw.pixelWidth }
    var pixelHeight: Int { raw.pixelHeight }
    var hz: Double { raw.refreshRate }
    var hiDPI: Bool { pixelWidth > width }
    var label: String {
        let hzText = hz > 0 ? String(format: "%.0f Hz", hz) : "? Hz"
        return "\(pixelWidth) × \(pixelHeight) @ \(hzText)" + (hiDPI ? " (HiDPI)" : "")
    }
}

enum Displays {
    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    static func external() -> [CGDirectDisplayID] { online().filter { CGDisplayIsBuiltin($0) == 0 } }

    static func name(_ id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Externes Display \(id)"
    }

    static func modes(_ id: CGDirectDisplayID) -> [Mode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let list = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
        return list.map(Mode.init)
            .filter { $0.raw.isUsableForDesktopGUI() }
            .sorted { ($0.pixelWidth, $0.pixelHeight, $0.hz) > ($1.pixelWidth, $1.pixelHeight, $1.hz) }
    }

    static func current(_ id: CGDirectDisplayID) -> Mode? { CGDisplayCopyDisplayMode(id).map(Mode.init) }

    /// Exakte Pixel-Auflösung, ohne HiDPI bevorzugt, Bildrate am nächsten am Ziel.
    static func find(_ id: CGDirectDisplayID, w: Int, h: Int, hz: Double = 60) -> Mode? {
        modes(id).filter { $0.pixelWidth == w && $0.pixelHeight == h }
            .min { a, b in a.hiDPI != b.hiDPI ? !a.hiDPI : abs(a.hz - hz) < abs(b.hz - hz) }
    }

    @discardableResult
    static func apply(_ mode: Mode, to id: CGDirectDisplayID) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(cfg, id, mode.raw, nil)
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }
}

// MARK: - App
//
// Bedienung: EIN Klick aufs Menüleisten-Symbol.
//   1. Klick  → alle externen Displays auf 1920×1080 @ 60 Hz (ohne HiDPI), sonst 1280×720
//   2. Klick  → wieder wie vorher
//   Rechtsklick → Beamer 16:10 (1920×1200), Bei Anmeldung starten (an/aus), Beenden

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var originals: [CGDirectDisplayID: Mode] = [:]   // leer = nicht aktiv

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    private func updateIcon() {
        let active = !originals.isEmpty
        let icon = NSImage(systemSymbolName: active ? "checkmark.rectangle" : "display",
                           accessibilityDescription: "BeamerFix")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = active
            ? "BeamerFix aktiv – klicken zum Zurückstellen"
            : "BeamerFix – klicken, um das Bild am externen Display zu reparieren"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.autoenablesItems = false   // sonst überschreibt AppKit isEnabled
            let beamer = menu.addItem(withTitle: "Beamer 16:10 (1920 × 1200)", action: #selector(fixBeamer), keyEquivalent: "")
            beamer.target = self
            beamer.isEnabled = Displays.external().contains { Displays.find($0, w: 1920, h: 1200) != nil }
            menu.addItem(.separator())
            let login = menu.addItem(withTitle: "Bei Anmeldung starten", action: #selector(toggleLogin), keyEquivalent: "")
            login.target = self
            switch SMAppService.mainApp.status {
            case .enabled: login.state = .on
            case .requiresApproval: login.state = .mixed
            default: login.state = .off
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "BeamerFix beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        originals.isEmpty ? fix(Self.roomTargets) : undo()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    alert("Bitte in den Systemeinstellungen erlauben.",
                          "Allgemein → Anmeldeobjekte → BeamerFix aktivieren.")
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            alert("Autostart konnte nicht geändert werden.", error.localizedDescription)
        }
    }

    /// Konferenzraum-Ingest (Teams/Zoom Rooms, Capture-Karten): 1080p, Fallback 720p.
    static let roomTargets = [(1920, 1080), (1280, 720)]
    /// Beamer mit WUXGA-Panel (16:10) – passt zum MacBook-Seitenverhältnis.
    static let beamerTargets = [(1920, 1200)]

    @objc private func fixBeamer() { fix(Self.beamerTargets) }

    private func fix(_ targets: [(Int, Int)]) {
        let ext = Displays.external()
        guard !ext.isEmpty else { return alert("Kein externes Display gefunden.", "Ist das Kabel eingesteckt?") }

        var previous: [CGDirectDisplayID: Mode] = [:]   // Stand direkt vor diesem Versuch
        var applied: [String] = []
        for id in ext {
            guard let cur = Displays.current(id),
                  let target = targets.lazy.compactMap({ Displays.find(id, w: $0.0, h: $0.1) }).first
            else { continue }
            previous[id] = cur
            if Displays.apply(target, to: id) { applied.append("\(Displays.name(id)): \(target.label)") }
        }
        guard !applied.isEmpty else {
            let list = targets.map { "\($0.0) × \($0.1)" }.joined(separator: " / ")
            return alert("Keine passende Auflösung gefunden.", "Das Display bietet \(list) nicht an.")
        }

        if confirm(applied.joined(separator: "\n")) {
            // Ursprungszustand nur beim ersten Mal merken – „Rückgängig“ führt immer ganz zurück.
            for (id, mode) in previous where originals[id] == nil { originals[id] = mode }
        } else {
            previous.forEach { Displays.apply($0.value, to: $0.key) }
        }
        updateIcon()
    }

    private func undo() {
        // Nur Displays zurückstellen, die noch angeschlossen sind.
        let online = Set(Displays.online())
        for (id, mode) in originals where online.contains(id) { Displays.apply(mode, to: id) }
        originals = [:]
        updateIcon()
    }

    /// „Ist das Bild OK?“ – ohne Klick nach 15 s automatisch zurück.
    private func confirm(_ info: String) -> Bool {
        let a = NSAlert()
        a.messageText = "Ist das Bild jetzt in Ordnung?"
        a.informativeText = info
        let keep = a.addButton(withTitle: "")
        a.addButton(withTitle: "Zurück")
        var remaining = 15
        keep.title = "Ja, behalten (\(remaining))"
        let timer = Timer(timeInterval: 1, repeats: true) { t in
            remaining -= 1
            keep.title = "Ja, behalten (\(remaining))"
            if remaining <= 0 { t.invalidate(); NSApp.abortModal() }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal()
        timer.invalidate()
        return result == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
