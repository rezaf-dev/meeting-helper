import AppKit
import Foundation

// Render the same simple vector geometry at every macOS icon size.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/MeetingHelper.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let blue = NSColor(srgbRed: 36 / 255, green: 89 / 255, blue: 212 / 255, alpha: 1)

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208).fill()
    let bubble = NSBezierPath()
    bubble.move(to: NSPoint(x: 344, y: 288))
    bubble.line(to: NSPoint(x: 680, y: 288))
    bubble.curve(to: NSPoint(x: 784, y: 392), controlPoint1: NSPoint(x: 737.44, y: 288), controlPoint2: NSPoint(x: 784, y: 334.56))
    bubble.line(to: NSPoint(x: 784, y: 600))
    bubble.curve(to: NSPoint(x: 680, y: 704), controlPoint1: NSPoint(x: 784, y: 657.44), controlPoint2: NSPoint(x: 737.44, y: 704))
    bubble.line(to: NSPoint(x: 456, y: 704))
    bubble.line(to: NSPoint(x: 304, y: 816))
    bubble.line(to: NSPoint(x: 304, y: 696))
    bubble.curve(to: NSPoint(x: 240, y: 600), controlPoint1: NSPoint(x: 265.13, y: 679.8), controlPoint2: NSPoint(x: 240, y: 641.9))
    bubble.line(to: NSPoint(x: 240, y: 392))
    bubble.curve(to: NSPoint(x: 344, y: 288), controlPoint1: NSPoint(x: 240, y: 334.56), controlPoint2: NSPoint(x: 286.56, y: 288))
    bubble.close()
    NSColor.white.setFill()
    bubble.fill()
    blue.setFill()
    for rect in [NSRect(x: 350, y: 424, width: 64, height: 144),
                 NSRect(x: 480, y: 376, width: 64, height: 240),
                 NSRect(x: 610, y: 424, width: 64, height: 144)] {
        NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for pointSize in [16, 32, 128, 256, 512] {
    try render(size: pointSize).write(to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    try render(size: pointSize * 2).write(to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/MeetingHelper.png"))
try render(size: 256).write(to: root.appendingPathComponent("Resources/Logo-preview.png"))
print("Rendered MeetingHelper logo and macOS icon sizes")
