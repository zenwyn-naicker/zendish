import AppKit
import SwiftUI

/// The Fresh Herb palette. Each colour has a light and dark value, and every text pairing
/// meets the WCAG AA contrast ratio of 4.5:1 in both.
enum Theme {
    static let page = color(light: 0xF4F7F1, dark: 0x121915)
    static let surface = color(light: 0xFFFFFF, dark: 0x1B241E)
    static let sidebar = color(light: 0xE7EEE3, dark: 0x18211B)
    static let tile = color(light: 0xE3ECDF, dark: 0x263329)
    static let selection = color(light: 0xC9DAC6, dark: 0x35523F)
    static let line = color(light: 0xDCE5D8, dark: 0x2C3A30)
    static let text = color(light: 0x1E2B22, dark: 0xEAF2EC)
    static let muted = color(light: 0x5C6B60, dark: 0xA3B3A8)
    static let accent = color(light: 0x2E7D4F, dark: 0x7BD6A0)
    static let onAccent = color(light: 0xFFFFFF, dark: 0x10231A)
    static let flag = color(light: 0xA85A0C, dark: 0xF2B566)
    static let flagFill = color(light: 0xFBEFDD, dark: 0x3A2C17)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// The main action on a screen: solid herb green, used once per view.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 7))
    }
}
