import Foundation
import ImageIO
import UniCopyCore

// One image per process. Exit to release the recognition engine's allocations.
let result: OCRResult = autoreleasepool {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= 80_000_000,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width <= 4096, image.height <= 4096 else {
        return OCRResult(error: "This capture is too large or could not be read.")
    }
    do { return OCRResult(text: try OCRService.recognize(image,
        correctLanguage: CommandLine.arguments.contains("--correct-language"),
        automaticLanguage: CommandLine.arguments.contains("--auto-language"))) }
    catch { return OCRResult(error: error.localizedDescription) }
}
FileHandle.standardOutput.write(try JSONEncoder().encode(result))
