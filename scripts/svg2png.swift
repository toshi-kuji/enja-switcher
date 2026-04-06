import Cocoa

guard CommandLine.arguments.count >= 4 else {
    print("Usage: svg2png <input.svg> <output.png> <size>")
    exit(1)
}

let svgPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let size = Int(CommandLine.arguments[3])!

guard let svgData = FileManager.default.contents(atPath: svgPath),
      let svgImage = NSImage(data: svgData) else {
    print("Error: Cannot load SVG from \(svgPath)")
    exit(1)
}

// Render to bitmap with transparency
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context

// Clear to transparent
NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// Draw SVG
svgImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Error: Cannot create PNG data")
    exit(1)
}

try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Generated: \(outputPath) (\(size)x\(size))")
