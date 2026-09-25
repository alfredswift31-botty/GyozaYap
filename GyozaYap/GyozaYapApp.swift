import SwiftUI

@main
struct GyozaYapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("GyozaYap", id: "main") {
            RootView()
                .frame(minWidth: 760, minHeight: 480)
                .environmentObject(model.store)
                .environmentObject(model.settings)
                .environmentObject(model.recorder)
                .environmentObject(model.notesService)
        }

        Settings {
            SettingsView()
                .environmentObject(model.settings)
                .environmentObject(model.notesService)
        }

        MenuBarExtra {
            MenuBarContent(recorder: model.recorder)
        } label: {
            MenuBarIcon(recorder: model.recorder)
        }
    }
}
