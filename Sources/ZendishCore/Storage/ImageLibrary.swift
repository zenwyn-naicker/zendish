import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLibraryError: Error, Equatable, CustomStringConvertible {
    case notAnImage(String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .notAnImage(let name): "\(name) isn't an image Zendish can read."
        case .unreadable(let name): "\(name) couldn't be opened."
        }
    }
}

/// Keeps copies of the original images, so recipes survive if the originals are moved or deleted.
public struct ImageLibrary: Sendable {
    public let folder: URL

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func url(for name: String) -> URL {
        folder.appendingPathComponent((name as NSString).lastPathComponent)
    }

    /// Copies an image in and returns the name it's stored under.
    public func add(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard Self.isSupported(source) else { throw ImageLibraryError.notAnImage(source.lastPathComponent) }
        guard let reader = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(reader) > 0 else {
            throw ImageLibraryError.unreadable(source.lastPathComponent)
        }
        let name = "\(UUID().uuidString).\(source.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    public func remove(_ names: [String]) {
        for name in names { try? FileManager.default.removeItem(at: url(for: name)) }
    }

    /// A downscaled image, which is far quicker to show in a grid than the full file.
    public func thumbnail(named name: String, maxPixels: Int) -> CGImage? {
        Self.image(at: url(for: name), maxPixels: maxPixels)
    }

    public static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func image(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
