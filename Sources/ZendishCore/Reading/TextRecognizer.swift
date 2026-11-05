import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum TextRecognitionError: Error, Equatable, CustomStringConvertible {
    case unreadableImage(String)

    public var description: String {
        switch self {
        case .unreadableImage(let name): "\(name) couldn't be opened as an image."
        }
    }
}

/// Reads text from images with macOS text recognition, entirely on this Mac.
public struct TextRecognizer: Sendable {
    public init() {}

    /// Reads the images in order and returns their text, one line per line found.
    public func text(from images: [URL]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for image in images {
                try Task.checkCancellation()
                pages.append(try Self.readLines(from: image).joined(separator: "\n"))
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    /// Loads the recognition system early. The first read otherwise takes about 30 seconds.
    public func warmUp() async {
        await Task.detached(priority: .utility) {
            guard let context = CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let image = context.makeImage() else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }.value
    }

    private static func readLines(from url: URL) throws -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextRecognitionError.unreadableImage(url.lastPathComponent)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
