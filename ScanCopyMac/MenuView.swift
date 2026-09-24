import ServiceManagement
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var receiver: ScanReceiver
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    private var isConnected: Bool { !receiver.connectedPhones.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScanCopy").font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isConnected ? "Connected: \(receiver.connectedPhones.joined(separator: ", "))"
                                         : "Waiting for iPhone…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let error = receiver.networkError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            Divider()

            // Pairing code
            VStack(alignment: .leading, spacing: 6) {
                Text("Pairing code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(receiver.pairingCode)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("New code") { receiver.newPairingCode() }
                }
                Text("On your iPhone: ScanCopy ▸ Settings ▸ Type into Mac, then enter this code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Typing options
            Toggle("Type scans into the active app", isOn: $receiver.typingEnabled)
            Picker("After each scan press", selection: $receiver.afterScan) {
                ForEach(AfterScanKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
            .pickerStyle(.menu)
            .disabled(!receiver.typingEnabled)

            if receiver.typingEnabled && !receiver.hasAccessibility {
                VStack(alignment: .leading, spacing: 8) {
                    Label("ScanCopy needs Accessibility permission to type on this Mac.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Grant Access…") { receiver.requestAccessibility() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let last = receiver.lastScan {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last scan").font(.caption).foregroundStyle(.secondary)
                    Text(last)
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Divider()

            Toggle("Open at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            HStack {
                Text("\(receiver.scanCount) scans this session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}
