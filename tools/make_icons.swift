// Draws the main-menu icons: the official Jellyfin mark (jellyfin-ux
// branding/SVG/icon-transparent.svg, CC BY-SA 4.0, unmodified) centred on the
// dark navy of the official app icon, as a 16:9 tile.
// Usage: swift make_icons.swift <svg> <outdir> [width height name...]
// Default: AppIcon.png and TopRowIcon.png at 188x108, the size the main menu
// caches (Kodi's is that size; a 376x216 icon was never shown).
import AppKit

let args = CommandLine.arguments
let svg = args[1], out = args[2]
let W = args.count > 4 ? Double(args[3])! : 188.0, H = args.count > 4 ? Double(args[4])! : 108.0
let names = args.count > 5 ? Array(args[5...]) : ["AppIcon.png", "TopRowIcon.png"]

guard let mark = NSImage(contentsOfFile: svg) else { fatalError("cannot read \(svg)") }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(red: 0.0, green: 0.043, blue: 0.145, alpha: 1).setFill()          // #000B25, the app icon's navy
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

// Same proportion as the square app icon: the mark spans about 56% of its height.
let side = H * 0.58
mark.draw(in: NSRect(x: (W - side) / 2, y: (H - side) / 2, width: side, height: side),
          from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
for name in names {
    try! png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
