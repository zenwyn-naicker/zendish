import AppKit
import CoreText
import Foundation

public enum RecipePDFError: Error, CustomStringConvertible {
    case couldNotCreate

    public var description: String { "The PDF couldn't be created." }
}

/// Writes recipes to an A4 PDF for printing or reading in the kitchen. Each recipe starts on a
/// new page, and long recipes continue onto more pages.
public enum RecipePDF {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let margin: CGFloat = 54

    public static func write(_ recipes: [Recipe], to url: URL) throws {
        var box = page
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw RecipePDFError.couldNotCreate }
        for recipe in recipes {
            draw(text(for: recipe), in: context)
        }
        context.closePDF()
    }

    private static func draw(_ text: NSAttributedString, in context: CGContext) {
        let setter = CTFramesetterCreateWithAttributedString(text)
        let area = page.insetBy(dx: margin, dy: margin)
        var position = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: position, length: 0), CGPath(rect: area, transform: nil), nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let shown = CTFrameGetVisibleStringRange(frame).length
            if shown == 0 { break }
            position += shown
        } while position < text.length
    }

    static func text(for recipe: Recipe) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func add(_ string: String, font: NSFont, color: NSColor = .black, spacing: CGFloat = 4, before: CGFloat = 0, indent: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = spacing
            style.paragraphSpacingBefore = before
            style.lineSpacing = 2
            style.headIndent = indent
            result.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }

        add(recipe.title ?? "Untitled recipe", font: .systemFont(ofSize: 24, weight: .bold), spacing: 6)
        let details = [
            recipe.totalTime.map { "Total \($0)" }, recipe.prepTime.map { "Prep \($0)" },
            recipe.cookTime.map { "Cook \($0)" }, recipe.servingsText,
        ].compactMap { $0 }
        if !details.isEmpty {
            add(details.joined(separator: "  ·  "), font: .systemFont(ofSize: 11), color: .darkGray, spacing: 6)
        }
        if !recipe.ingredients.isEmpty {
            add("Ingredients", font: .systemFont(ofSize: 14, weight: .semibold), spacing: 6, before: 14)
            var section: String?
            for ingredient in recipe.ingredients {
                if let heading = ingredient.section, heading != section {
                    add(heading, font: .systemFont(ofSize: 11, weight: .medium), color: .darkGray, before: 6)
                }
                section = ingredient.section
                add(ingredient.text, font: .systemFont(ofSize: 12))
            }
        }
        if !recipe.steps.isEmpty {
            add("Method", font: .systemFont(ofSize: 14, weight: .semibold), spacing: 6, before: 14)
            for (index, step) in recipe.steps.enumerated() {
                add("\(index + 1).  \(step)", font: .systemFont(ofSize: 12), spacing: 7, indent: 18)
            }
        }
        return result
    }
}
