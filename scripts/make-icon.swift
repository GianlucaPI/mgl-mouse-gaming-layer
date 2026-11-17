// Generates Resources/AppIcon.icns: run `swift scripts/make-icon.swift` from the repo root.
// Draws the SF Symbol "computermouse.fill" on a rounded gradient square (macOS icon grid).
import AppKit

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MGL.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body, ~185/1024 corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: path, angle: -90)
    NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.10, alpha: 1).setStroke()   // accent ring
    path.lineWidth = max(1, s * 14 / 1024)
    path.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2,
                               width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = URL(fileURLWithPath: "Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
precondition(task.terminationStatus == 0, "iconutil failed")
print("Wrote \(out.path)")
