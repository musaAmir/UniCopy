import Foundation
import Vision
import CoreGraphics

public enum CaptureGeometry {
    public static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect? {
        let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y)).intersection(bounds)
        return !rect.isNull && rect.width >= 5 && rect.height >= 5 ? rect : nil
    }
    public static func sourceRect(selection: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: selection.minX, y: screenHeight - selection.maxY, width: selection.width, height: selection.height)
    }
    public static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        let ratio = min(scale, 4096 / max(1, points.width, points.height))
        return CGSize(width: max(1, (points.width * ratio).rounded()), height: max(1, (points.height * ratio).rounded()))
    }
}

public struct OCRResult: Codable {
    public let text: String
    public let error: String?
    public init(text: String = "", error: String? = nil) { self.text = text; self.error = error }
}

public enum OCRService {
    public static func recognize(_ image: CGImage, correctLanguage: Bool = false, automaticLanguage: Bool = false) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = automaticLanguage
        if !automaticLanguage {
            let supported = try request.supportedRecognitionLanguages()
            var languages: [String] = []
            for preferred in Locale.preferredLanguages + ["en-US"] {
                if let match = supported.first(where: { $0 == preferred }) ?? supported.first(where: { $0.split(separator:"-").first == preferred.split(separator:"-").first }), !languages.contains(match) {
                    languages.append(match)
                }
            }
            if !languages.isEmpty { request.recognitionLanguages = Array(languages.prefix(2)) }
        }
        request.usesLanguageCorrection = correctLanguage
        try VNImageRequestHandler(cgImage: image).perform([request])
        // Vision's observation order preserves its detected reading order; avoid a naive Y sort
        // which can interleave neighbouring columns and lines with slightly different baselines.
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return String(text.prefix(200_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
