import AppKit
import Foundation

let sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Openly/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 24
    ) else { fatalError("Unable to create icon bitmap") }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 22/255, green: 39/255, blue: 122/255, alpha: 1).setFill()
    rect.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = CGFloat(size) * 0.58
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let text = "O" as NSString
    let textRect = NSRect(x: 0, y: CGFloat(size) * 0.19, width: CGFloat(size), height: fontSize * 1.25)
    text.draw(in: textRect, withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon")
    }
    try data.write(to: output.appendingPathComponent("icon-\(size).png"))
}

print("Generated \(sizes.count) Openly app icons")
