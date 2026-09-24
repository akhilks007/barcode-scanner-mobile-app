import SwiftUI
import AVFoundation
import UIKit

enum ScanMode: String, CaseIterable, Identifiable {
    case qr, barcode

    var id: String { rawValue }
    var title: String { self == .qr ? "QR Code" : "Barcode" }
    var icon: String { self == .qr ? "qrcode" : "barcode" }
    /// Square frame for QR codes, wide frame for 1D barcodes.
    var frameSize: CGSize {
        self == .qr ? CGSize(width: 260, height: 260) : CGSize(width: 320, height: 150)
    }
    var cornerRadius: CGFloat { self == .qr ? 24 : 16 }
}

struct ContentView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("scanMode") private var scanMode: ScanMode = .qr
    @AppStorage(SettingsKey.beepEnabled) private var beepEnabled = true
    @AppStorage(SettingsKey.vibrateEnabled) private var vibrateEnabled = true

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn = false
    @State private var lastScan: ScanItem?
    @State private var copiedFlash = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraStatus {
            case .authorized:
                ScannerView(isScanning: !showHistory && !showSettings,
                            torchOn: torchOn,
                            scanAreaSize: scanMode.frameSize) { value, type in
                    handleScan(value: value, type: type)
                }
                .ignoresSafeArea()

                ViewfinderOverlay(mode: scanMode, highlight: copiedFlash)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    ModeSwitcher(mode: $scanMode)
                        .padding(.bottom, 12)
                    bottomPanel
                }
                .padding()

            case .notDetermined:
                ProgressView()
                    .task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    }

            default:
                PermissionView()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { torchOn = false }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            CircleButton(systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                         isActive: torchOn) {
                torchOn.toggle()
            }
            Spacer()
            CircleButton(systemImage: "clock.arrow.circlepath") {
                showHistory = true
            }
            CircleButton(systemImage: "gearshape.fill") {
                showSettings = true
            }
        }
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        if let scan = lastScan {
            ResultCard(item: scan,
                       flash: copiedFlash,
                       onCopy: { copyToClipboard(scan.value) })
                .id(scan.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text(scanMode == .qr ? "Place a QR code inside the square"
                                 : "Place the barcode inside the wide frame")
                .font(.subheadline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Actions

    private func handleScan(value: String, type: String) {
        copyToClipboard(value)
        if beepEnabled { BeepPlayer.shared.play() }
        if vibrateEnabled { Vibration.play() }
        withAnimation(.spring(duration: 0.3)) {
            lastScan = store.add(value: value, type: type)
        }
    }

    private func copyToClipboard(_ value: String) {
        // Universal Clipboard makes this available on your Mac (same Apple ID + Handoff on).
        UIPasteboard.general.string = value
        copiedFlash = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            copiedFlash = false
        }
    }
}

// MARK: - Subviews

struct ModeSwitcher: View {
    @Binding var mode: ScanMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScanMode.allCases) { m in
                Button {
                    withAnimation(.spring(duration: 0.3)) { mode = m }
                } label: {
                    Label(m.title, systemImage: m.icon)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(mode == m ? Color.black : Color.white)
                        .background {
                            if mode == m { Capsule().fill(Color.white) }
                        }
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ViewfinderOverlay: View {
    var mode: ScanMode
    var highlight: Bool

    var body: some View {
        let size = mode.frameSize
        ZStack {
            // Dim everything outside the frame
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .mask {
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: mode.cornerRadius)
                            .frame(width: size.width, height: size.height)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            RoundedRectangle(cornerRadius: mode.cornerRadius)
                .stroke(highlight ? Color.green : Color.white.opacity(0.9),
                        lineWidth: highlight ? 5 : 3)
                .frame(width: size.width, height: size.height)

            if mode == .barcode {
                Rectangle()
                    .fill(highlight ? Color.green : Color.red.opacity(0.85))
                    .frame(width: size.width - 32, height: 2)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.3), value: mode)
        .animation(.easeOut(duration: 0.2), value: highlight)
        .allowsHitTesting(false)
    }
}

struct CircleButton: View {
    let systemImage: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .foregroundStyle(isActive ? Color.black : Color.white)
                .background(isActive ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.ultraThinMaterial),
                            in: Circle())
        }
    }
}

struct ResultCard: View {
    let item: ScanItem
    let flash: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.type.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .scaleEffect(flash ? 1.12 : 1)
                    .animation(.spring(duration: 0.25), value: flash)
            }

            Text(item.value)
                .font(.body.monospaced())
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: onCopy) {
                    Label("Copy again", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let url = item.webURL {
                    Link(destination: url) {
                        Label("Open", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
            Text("Camera access needed")
                .font(.title3.bold())
            Text("ScanCopy uses the camera to read barcodes and QR codes. Please allow camera access in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(Color.white)
        .padding(32)
    }
}
