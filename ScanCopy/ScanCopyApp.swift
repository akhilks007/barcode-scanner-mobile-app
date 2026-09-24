import SwiftUI

@main
struct ScanCopyApp: App {
    @StateObject private var store = ScanStore()
    @StateObject private var macLink = MacLink()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(macLink)
        }
    }
}
