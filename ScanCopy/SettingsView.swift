import SwiftUI

enum SettingsKey {
    static let beepEnabled = "beepEnabled"
    static let vibrateEnabled = "vibrateEnabled"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.beepEnabled) private var beepEnabled = true
    @AppStorage(SettingsKey.vibrateEnabled) private var vibrateEnabled = true

    var body: some View {
        NavigationStack {
            Form {
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
