import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift <output.png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1200, height: 760)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create DMG background canvas\n", stderr)
    exit(1)
}

NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.current = nil }

NSColor(calibratedRed: 0.97, green: 0.965, blue: 0.94, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.14, alpha: 1),
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.37, blue: 0.33, alpha: 1),
]

NSString(string: "Install TokenDash").draw(at: NSPoint(x: 94, y: 650), withAttributes: titleAttributes)
NSString(string: "Drag the app to Applications to finish installation").draw(at: NSPoint(x: 96, y: 615), withAttributes: subtitleAttributes)

let accent = NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1)
accent.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 350, y: 350))
arrow.curve(to: NSPoint(x: 630, y: 350), controlPoint1: NSPoint(x: 430, y: 405), controlPoint2: NSPoint(x: 550, y: 405))
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 5
arrowHead.lineCapStyle = .round
arrowHead.move(to: NSPoint(x: 600, y: 375))
arrowHead.line(to: NSPoint(x: 640, y: 350))
arrowHead.line(to: NSPoint(x: 600, y: 325))
arrowHead.stroke()

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.43, green: 0.48, blue: 0.44, alpha: 1),
]
NSString(string: "You can close this window after copying TokenDash").draw(at: NSPoint(x: 96, y: 72), withAttributes: footerAttributes)

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode DMG background PNG\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: outputURL)
} catch {
    fputs("Unable to write DMG background: \(error)\n", stderr)
    exit(1)
}
