import AppKit
import UniCopyCore

func runWorkerSelfTest() -> Int32 {
    _ = NSApplication.shared
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1000,pixelsHigh:240,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor.white.setFill(); CGRect(x:0,y:0,width:1000,height:240).fill()
    let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:48),.foregroundColor:NSColor.black]
    ("Invoice 1042 Total 123.45" as NSString).draw(at:CGPoint(x:50,y:100),withAttributes:attrs)
    NSGraphicsContext.restoreGraphicsState()
    if let path = ProcessInfo.processInfo.environment["UNICOPY_TEST_IMAGE"] {
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
    }
    // Allow macOS to prepare its model on first use. The second fresh helper must
    // still return quickly; this detects transport stalls without mistaking a cold
    // model compilation for a deadlock.
    for phase in 0..<2 {
        let worker = OCRWorker()
        var received: OCRResult?
        let started = Date()
        let limit: TimeInterval = phase == 0 ? 55 : 5
        worker.recognize(image:bitmap.cgImage!,correctLanguage:false,automaticLanguage:false) { received = $0 }
        while received == nil && Date().timeIntervalSince(started) < limit {
            RunLoop.main.run(until:Date().addingTimeInterval(0.02))
        }
        let duration = Date().timeIntervalSince(started)
        worker.cancel()
        guard let result = received, result.error == nil, result.text.contains("Invoice 1042"), result.text.contains("123.45"), duration < limit else {
            print("FAIL: packaged OCR worker, phase \(phase), returned \(received?.error ?? received?.text ?? "no response")")
            return 1
        }
        print(String(format:"PASS: packaged helper phase %d recognised the fixture in %.2f seconds.",phase,duration))
    }
    return 0
}
