import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("Resources/LegacyIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
guard let source = NSImage(contentsOf: root.appendingPathComponent("Design/tape-app-icon.png")) else {
    fatalError("Missing Tape icon")
}
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon-\(size)@\(scale)x.png"
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".utf8).write(to: root.appendingPathComponent("Resources/Assets.xcassets/Contents.json"))

// Icon Composer: separate original Tape mark and full-bleed black image layers.
let composer = root.appendingPathComponent("Resources/AppIcon.icon")
let layers = composer.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: layers, withIntermediateDirectories: true)
for (name, drawsMark) in [("mark.png", true), ("black.png", false)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    if drawsMark {
        NSColor.white.setFill()
        let scale: CGFloat = 5.6, start: CGFloat = 512 - 50 * 5.6
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: start + x * scale, y: 1024 - start - y * scale) }
        let mark = NSBezierPath()
        mark.move(to: point(8, 32))
        for pair in [(92,32),(100,41),(92,50),(100,59),(92,68),(8,68),(0,59),(8,50),(0,41)] {
            mark.line(to: point(CGFloat(pair.0), CGFloat(pair.1)))
        }
        mark.close()
        for x: CGFloat in [36, 57] {
            mark.appendRect(NSRect(x: start + x * scale, y: 1024 - start - 58 * scale, width: 7 * scale, height: 16 * scale))
        }
        mark.windingRule = .evenOdd
        mark.fill()
    } else {
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: layers.appendingPathComponent(name))
}
let iconJSON = """
{
  "fill": "none",
  "groups": [{
    "layers": [
      {"glass": false, "image-name": "mark.png", "name": "mark"},
      {"glass": false, "image-name": "black.png", "name": "black"}
    ],
    "lighting": "individual",
    "shadow": {"kind": "none", "opacity": 0},
    "specular": false,
    "translucency": {"enabled": false, "value": 0}
  }],
  "supported-platforms": {"squares": ["macOS"]}
}
"""
try Data(iconJSON.utf8).write(to: composer.appendingPathComponent("icon.json"))
