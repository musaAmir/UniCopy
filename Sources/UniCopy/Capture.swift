import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import UniCopyCore

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ScreenCapture {
    static func image(for selection: CaptureSelection) async throws -> CGImage {
        // Give the compositor a frame to remove selection overlays before taking the still.
        try await Task.sleep(nanoseconds: 80_000_000)
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError(message: "That display was disconnected. Please select an area again.")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CaptureGeometry.sourceRect(selection: selection.rect, screenHeight: selection.screenFrame.height)
        let size = CaptureGeometry.pixelSize(points: selection.rect.size, scale: selection.scale)
        config.width = Int(size.width); config.height = Int(size.height)
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        return image
    }
}

final class OCRWorker {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled: String?
    private var timeout: Timer?

    func cancel(reason: String = "Capture cancelled.") {
        lock.lock(); cancelled = reason; let process = process; lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }
    func recognize(image: CGImage, correctLanguage: Bool, automaticLanguage: Bool, completion: @escaping (OCRResult) -> Void) {
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.cancel(reason: "Recognition took too long. Try a smaller area.") }
        timeout = timer; RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.global(qos: .userInitiated).async {
            let result: OCRResult = autoreleasepool {
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/UniCopyOCR")
                guard FileManager.default.isExecutableFile(atPath:helper.path) else {
                    return OCRResult(error: "The OCR helper is missing. Rebuild or reinstall UniCopy.")
                }
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return OCRResult(error:"Couldn’t prepare the selected image.") }
                CGImageDestinationAddImage(destination,image,nil)
                guard CGImageDestinationFinalize(destination) else { return OCRResult(error:"Couldn’t prepare the selected image.") }
                let task = Process(); task.executableURL = helper
                task.arguments = (correctLanguage ? ["--correct-language"] : []) + (automaticLanguage ? ["--auto-language"] : [])
                let input = Pipe(); let output = Pipe()
                task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
                // A timed-out child may close stdin while the parent is writing.
                _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                self.lock.lock(); self.process = task; let cancelled = self.cancelled; self.lock.unlock()
                if let cancelled { return OCRResult(error:cancelled) }
                do {
                    try task.run()
                    self.lock.lock(); let cancelled = self.cancelled; self.lock.unlock()
                    if cancelled != nil && task.isRunning { task.terminate() }
                    try input.fileHandleForWriting.write(contentsOf: data as Data)
                    try input.fileHandleForWriting.close()
                    let response = output.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    self.lock.lock(); let reason = self.cancelled; self.lock.unlock()
                    if let reason { return OCRResult(error:reason) }
                    guard task.terminationStatus == 0, response.count < 4_000_000,
                          let decoded = try? JSONDecoder().decode(OCRResult.self,from:response) else {
                        return OCRResult(error:"Recognition couldn’t finish. Try a smaller area.")
                    }
                    return decoded
                } catch {
                    try? input.fileHandleForWriting.close()
                    if task.isRunning { task.terminate(); task.waitUntilExit() }
                    return OCRResult(error:error.localizedDescription)
                }
            }
            self.lock.lock(); self.process = nil; self.lock.unlock()
            DispatchQueue.main.async { self.timeout?.invalidate(); self.timeout = nil; completion(result) }
        }
    }
}
