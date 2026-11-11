// Erzeugt dmg/background.tiff (600×400 pt, 1x + 2x) für das DMG-Fenster:
// heller Verlauf, Pfeil von der App (links) zum Programme-Ordner (rechts), Hinweistext.
// Aufruf: swift dmg/make-background.swift dmg/background.tiff

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg/background.tiff"
let W: CGFloat = 600, H: CGFloat = 400

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // → 2x-Version wird als Retina erkannt
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: NSColor(white: 0.99, alpha: 1), ending: NSColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Pfeil zwischen den Icons (Icons sitzen bei x=150 und x=450, y=180 von oben)
    let blue = NSColor(red: 0.10, green: 0.42, blue: 0.92, alpha: 1)
    let y = H - 180
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 245, y: y)); shaft.line(to: NSPoint(x: 345, y: y))
    shaft.lineWidth = 6; shaft.lineCapStyle = .round
    blue.setStroke(); shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 362, y: y))
    head.line(to: NSPoint(x: 338, y: y + 16))
    head.line(to: NSPoint(x: 338, y: y - 16))
    head.close()
    blue.setFill(); head.fill()

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: p,
        ]).draw(in: NSRect(x: 0, y: H - y - size * 1.4, width: W, height: size * 1.6))
    }
    text("BeamerFix installieren", size: 22, weight: .semibold, color: NSColor(white: 0.15, alpha: 1), y: 40)
    text("Ziehe BeamerFix auf den Programme-Ordner.", size: 14, weight: .regular,
         color: NSColor(white: 0.35, alpha: 1), y: 300)
    text("Dann BeamerFix starten – das Symbol erscheint oben in der Menüleiste.", size: 12, weight: .regular,
         color: NSColor(white: 0.5, alpha: 1), y: 324)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let img = NSImage(size: NSSize(width: W, height: H))
img.addRepresentation(render(scale: 1))
img.addRepresentation(render(scale: 2))
try! img.tiffRepresentation(using: .lzw, factor: 0)!.write(to: URL(fileURLWithPath: out))
// Vorschau-PNG für README/Review
// Vorschau: try! render(scale: 2).representation(using: .png, properties: [:])!
//     .write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + "-preview.png"))
print("✓ \(out)")
