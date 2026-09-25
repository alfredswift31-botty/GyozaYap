import SwiftUI

@main
struct GyozaYapApp: App {
    @StateObject private var store = MeetingStore()

    var body: some Scene {
        WindowGroup {
            Text("GyozaYap — \(store.meetings.count) meetings")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
