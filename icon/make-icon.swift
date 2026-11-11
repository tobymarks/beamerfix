// Erzeugt icon/AppIcon.icns: blauer macOS-Squircle mit weißem Monitor und Häkchen.
// Aufruf: swift icon/make-icon.swift   (wird von build.sh automatisch ausgeführt, falls .icns fehlt)

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS-Raster: 1024er Canvas, Icon-Körper 824 px, Radius ~185 px
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 10 / 1024)
    shadow.shadowBlurRadius = s * 20 / 1024
    shadow.set()
    NSColor.white.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.30, blue: 0.85, alpha: 1))!.draw(in: path, angle: -90)

    // Weißes Monitor-Symbol mit Häkchen (SF Symbol)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "checkmark.rectangle", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let r = NSRect(x: (s - sym.size.width) / 2, y: (s - sym.size.height) / 2,
                       width: sym.size.width, height: sym.size.height)
        sym.draw(in: r)
    }
    // Standfuß unter dem Bildschirm
    let foot = NSBezierPath(roundedRect: NSRect(x: s * 0.40, y: s * 0.215, width: s * 0.20, height: s * 0.035),
                            xRadius: s * 0.017, yRadius: s * 0.017)
    NSColor.white.setFill(); foot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(512).write(to: out.deletingPathExtension().appendingPathExtension("png"))
print("✓ \(out.path)")
