import AppKit

// Source artwork for the Finder installer window; no image service or user data.
let size = NSSize(width: 800, height: 500)
let image = NSImage(size: size)
image.lockFocus()
let bounds = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.99, alpha: 1).setFill()
bounds.fill()
for (rect, color) in [
    (NSRect(x: -250, y: 50, width: 900, height: 750), NSColor.systemBlue),
    (NSRect(x: 300, y: -300, width: 850, height: 800), NSColor.systemPurple)
] {
    NSGradient(starting: color.withAlphaComponent(0.12), ending: color.withAlphaComponent(0))?
        .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
}
func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, opacity: CGFloat) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 30, y: y, width: 740, height: size * 1.7), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.2, alpha: opacity), .paragraphStyle: paragraph
    ])
}
text("Panopticon", y: 396, size: 40, weight: .semibold, opacity: 1)
text("Your desktop. Your rhythm.", y: 366, size: 15, weight: .regular, opacity: 0.65)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 356, y: 252)); arrow.line(to: NSPoint(x: 444, y: 252))
arrow.move(to: NSPoint(x: 430, y: 266)); arrow.line(to: NSPoint(x: 444, y: 252)); arrow.line(to: NSPoint(x: 430, y: 238))
NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.5, alpha: 0.5).setStroke(); arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.stroke()
text("Drag Panopticon into Applications", y: 108, size: 17, weight: .medium, opacity: 0.9)
text("Then open it from Applications to make it yours.", y: 81, size: 12, weight: .regular, opacity: 0.55)
text("macOS 13+  ·  Apple Silicon & Intel  ·  Free and local", y: 30, size: 11, weight: .regular, opacity: 0.4)
image.unlockFocus()
guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
    let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render installer artwork") }
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "resources/dmg/background.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output, options: .atomic)
print("Rendered \(output.path)")
