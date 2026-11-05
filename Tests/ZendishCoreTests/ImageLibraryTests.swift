import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ZendishCore

@Suite struct ImageLibraryTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeImage(to url: URL, width: Int = 400, height: Int = 200) throws {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let writer = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        #expect(CGImageDestinationFinalize(writer))
    }

    @Test func imagesAreCopiedAndSurviveTheOriginalBeingDeleted() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Photo.PNG")
        try writeImage(to: original)
        let library = try ImageLibrary(folder: folder.appendingPathComponent("Images"))

        let name = try library.add(original)
        try FileManager.default.removeItem(at: original)

        #expect(name.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: library.url(for: name).path))
    }

    @Test func filesThatAreNotImagesAreRefused() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try ImageLibrary(folder: folder.appendingPathComponent("Images"))
        let text = folder.appendingPathComponent("notes.txt")
        let fake = folder.appendingPathComponent("fake.png")
        try Data("hello".utf8).write(to: text)
        try Data("hello".utf8).write(to: fake)

        #expect(throws: ImageLibraryError.notAnImage("notes.txt")) { _ = try library.add(text) }
        #expect(throws: ImageLibraryError.unreadable("fake.png")) { _ = try library.add(fake) }
    }

    @Test func nameCannotEscapeTheLibraryFolder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try ImageLibrary(folder: folder)
        #expect(library.url(for: "../../secret.txt").deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func thumbnailsHaveTheRightSize() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("photo.png")
        try writeImage(to: original, width: 1000, height: 500)
        let library = try ImageLibrary(folder: folder.appendingPathComponent("Images"))
        let name = try library.add(original)

        let thumbnail = try #require(library.thumbnail(named: name, maxPixels: 100))
        #expect(max(thumbnail.width, thumbnail.height) == 100)
    }
}
