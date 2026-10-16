import AppKit
let name = CommandLine.arguments[1]
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let directory = destination.deletingPathExtension().appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: Double(pixels)*0.08, y: Double(pixels)*0.08, width: Double(pixels)*0.84, height: Double(pixels)*0.84)
        NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.21, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: Double(pixels)*0.19, yRadius: Double(pixels)*0.19).fill()
        let symbol = NSImage(systemSymbolName: name == "Hush" ? "circle.lefthalf.filled" : "text.viewfinder", accessibilityDescription: nil)!
        let symbolRect = NSRect(x: Double(pixels)*0.26, y: Double(pixels)*0.26, width: Double(pixels)*0.48, height: Double(pixels)*0.48)
        let color = NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.84, alpha: 1)
        let tinted = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) ?? symbol
        tinted.draw(in: symbolRect)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 1 ? "" : "@2x"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", directory.path, "-o", destination.path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("Icon generation failed") }
try FileManager.default.removeItem(at: directory)
