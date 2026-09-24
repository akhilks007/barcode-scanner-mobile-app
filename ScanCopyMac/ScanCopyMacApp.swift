import SwiftUI

/// Menu-bar app that receives scans from CodeDropScan on iPhone and types them into the active app.
@main
struct ScanCopyMacApp: App {
    @StateObject private var receiver = ScanReceiver()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(receiver)
        } label: {
            Image(systemName: receiver.connectedPhones.isEmpty ? "barcode.viewfinder" : "barcode")
        }
        .menuBarExtraStyle(.window)
    }
}
