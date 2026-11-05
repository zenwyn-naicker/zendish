import SwiftUI

public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: Self { self }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: "Match My Mac"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public struct SettingsView: View {
    @AppStorage("appearance") private var appearance = Appearance.system

    public init() {}

    public var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 90)
    }
}
