import AppKit
import Foundation
import Testing
@testable import ZendishCore

@Suite struct TextRecognizerTests {
    private func image(saying lines: [String], in folder: URL, named name: String) throws -> URL {
        let size = NSSize(width: 900, height: 120 * lines.count + 80)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
        ]
        for (index, line) in lines.enumerated() {
            let y = size.height - CGFloat(120 * (index + 1))
            (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = folder.appendingPathComponent(name)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func readsTextInImageOrder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try image(saying: ["Tomato soup", "2 cups stock"], in: folder, named: "one.png")
        let second = try image(saying: ["Simmer gently"], in: folder, named: "two.png")

        let text = try await TextRecognizer().text(from: [first, second])

        #expect(text.contains("Tomato soup"))
        #expect(text.contains("2 cups stock"))
        let soup = try #require(text.range(of: "Tomato soup"))
        let simmer = try #require(text.range(of: "Simmer gently"))
        #expect(soup.lowerBound < simmer.lowerBound)
    }

    @Test func aFileThatIsNotAnImageIsReported() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.png")
        try Data("not an image".utf8).write(to: file)

        await #expect(throws: TextRecognitionError.unreadableImage("notes.png")) {
            _ = try await TextRecognizer().text(from: [file])
        }
    }
}
