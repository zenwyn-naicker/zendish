import SwiftUI
import ZendishUI

@main
struct ZendishApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        Window("Zendish", id: "main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .onOpenURL { url in model.receive([url]) }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Recipe…") { model.isChoosingFiles = true }
                    .keyboardShortcut("n")
            }
        }
    }
}
