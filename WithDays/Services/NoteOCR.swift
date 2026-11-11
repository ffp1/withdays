import UIKit
import Vision

/// Reads the text in an image (Japanese and English), on the device.
/// Print is read well; handwriting, Japanese handwriting above all, less so.
enum NoteOCR {
    /// The lines found, top to bottom, joined with line breaks; empty when there's nothing to read.
    static func recognize(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
