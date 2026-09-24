import SwiftUI

enum SettingsKey {
    static let beepEnabled = "beepEnabled"
    static let vibrateEnabled = "vibrateEnabled"
    static let macLinkEnabled = "macLinkEnabled"
    static let macPairingCode = "macPairingCode"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.beepEnabled) private var beepEnabled = true
    @AppStorage(SettingsKey.vibrateEnabled) private var vibrateEnabled = true
    @AppStorage(SettingsKey.macLinkEnabled) private var macLinkEnabled = false
    @AppStorage(SettingsKey.macPairingCode) private var macPairingCode = ""
    @EnvironmentObject private var macLink: MacLink

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $macLinkEnabled) {
                        Label("Type into Mac", systemImage: "laptopcomputer")
                    }
                    if macLinkEnabled {
                        HStack {
                            Text("Pairing code")
                            Spacer()
                            TextField("6 digits", text: $macPairingCode)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: 120)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Circle()
                                .fill(macLink.status.isConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(macLink.status.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Mac helper")
                } footer: {
                    Text("Open ScanCopy Mac on your Mac and enter the code shown in its menu-bar window. Each scan is then typed into whatever is selected on the Mac (for example a Numbers cell), and the cursor moves on to the next row.")
                }
                .onChange(of: macLinkEnabled) { _, on in
                    if on { macLink.start(pairingCode: macPairingCode) } else { macLink.stop() }
                }
                .onChange(of: macPairingCode) { _, code in
                    let digits = String(code.filter(\.isNumber).prefix(6))
                    if digits != code {
                        macPairingCode = digits
                        return
                    }
                    if macLinkEnabled { macLink.start(pairingCode: digits) }
                }

                Section {
                    Toggle(isOn: $beepEnabled) {
                        Label("Beep on scan", systemImage: "speaker.wave.2.fill")
                    }
                    if beepEnabled {
                        Button {
                            BeepPlayer.shared.play()
                        } label: {
                            Label("Test beep", systemImage: "play.circle")
                        }
                    }
                    Toggle(isOn: $vibrateEnabled) {
                        Label("Vibrate on scan", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    if vibrateEnabled {
                        Button {
                            Vibration.play()
                        } label: {
                            Label("Test vibration", systemImage: "play.circle")
                        }
                    }
                } header: {
                    Text("When a new code is scanned")
                } footer: {
                    Text("The beep follows your iPhone's ring/silent switch and volume. If you don't hear it, turn off silent mode. If you don't feel the vibration, check Settings ▸ Accessibility ▸ Touch ▸ Vibration is on.")
                }

                Section {
                    Text("Scanned codes are copied to your iPhone's clipboard. With the same Apple ID, Wi-Fi, Bluetooth and Handoff turned on, press ⌘V on your Mac to paste within about 2 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Pasting on your Mac")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
