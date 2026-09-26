import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper around the live camera barcode scanner.
struct ScannerView: UIViewControllerRepresentable {
    var isScanning: Bool
    var torchOn: Bool
    /// Size (in points) of the on-screen frame; only codes inside it are read.
    var scanAreaSize: CGSize
    var onScan: (_ value: String, _ type: String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.camera.onCodeScanned = onScan
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {
        vc.camera.onCodeScanned = onScan
        vc.camera.isScanningEnabled = isScanning
        vc.camera.setTorch(torchOn)
        vc.scanAreaSize = scanAreaSize
    }
}

/// Shows the camera preview full screen.
final class ScannerViewController: UIViewController {
    let camera = CameraController()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    /// Size of the on-screen frame. Codes whose centre is outside it are ignored.
    var scanAreaSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = camera.session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        camera.acceptCode = { [weak self] code in
            self?.isInsideFrame(code) ?? true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    /// True when the code's centre (as shown on screen) is inside the frame, plus a small margin.
    private func isInsideFrame(_ code: AVMetadataMachineReadableCodeObject) -> Bool {
        let bounds = view.bounds
        guard scanAreaSize.width > 0, bounds.width > 0,
              let onScreen = previewLayer.transformedMetadataObject(for: code) else { return true }
        let w = scanAreaSize.width + 40
        let h = scanAreaSize.height + 40
        let frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        return frame.contains(CGPoint(x: onScreen.bounds.midX, y: onScreen.bounds.midY))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        camera.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stop()
    }
}

/// Owns the AVCaptureSession and reads barcodes / QR codes from it.
final class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ScanCopy.camera")
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private let codeOutput = AVCaptureMetadataOutput()

    // Accessed on the main thread
    var onCodeScanned: ((String, String) -> Void)?
    /// Decides whether a detected code counts (used to ignore codes outside the on-screen frame).
    var acceptCode: ((AVMetadataMachineReadableCodeObject) -> Bool)?
    var isScanningEnabled = true
    private var torchRequested = false
    private var lastValue: String?
    private var lastScanTime = Date.distantPast
    /// The same code is ignored while it stays in view (prevents repeat copies).
    private let sameCodeCooldown: TimeInterval = 2.0

    private static let supportedTypes: [AVMetadataObject.ObjectType] = [
        .qr, .microQR, .ean13, .ean8, .upce, .code128, .code39, .code39Mod43, .code93,
        .itf14, .interleaved2of5, .codabar, .pdf417, .microPDF417, .aztec, .dataMatrix,
        .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
    ]

    func start() {
        sessionQueue.async {
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func setTorch(_ on: Bool) {
        guard on != torchRequested else { return }
        torchRequested = on
        sessionQueue.async {
            guard let device = self.device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                print("Torch error: \(error)")
            }
        }
    }

    // MARK: - Setup

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .high

        // Prefer multi-camera devices so newer iPhones can switch to macro for close-up codes.
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera
        ]
        guard let camera = preferred.lazy.compactMap({
                  AVCaptureDevice.default($0, for: .video, position: .back)
              }).first,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        device = camera

        let output = codeOutput
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = Self.supportedTypes.filter {
            output.availableMetadataObjectTypes.contains($0)
        }
        session.commitConfiguration()

        configureFocus(camera)
    }

    private func configureFocus(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            // On multi-camera devices zoom 1.0 is the ultra-wide lens; start on the normal "1x" wide lens.
            if let wideFactor = camera.virtualDeviceSwitchOverVideoZoomFactors.first {
                camera.videoZoomFactor = CGFloat(truncating: wideFactor)
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
        } catch {
            print("Focus config error: \(error)")
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate (called on main queue)

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard isScanningEnabled else { return }
        let codes = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .filter { !($0.stringValue ?? "").isEmpty }
            .filter { acceptCode?($0) ?? true }
        guard !codes.isEmpty else { return }
        let now = Date()

        // A new (different) code in the frame is copied immediately.
        if let code = codes.first(where: { $0.stringValue != lastValue }), let value = code.stringValue {
            report(value, code.type, at: now)
            return
        }

        // Only the previous code is in view: copy it again only if it left the frame for a moment.
        if now.timeIntervalSince(lastScanTime) >= sameCodeCooldown,
           let code = codes.first, let value = code.stringValue {
            report(value, code.type, at: now)
        } else {
            lastScanTime = now
        }
    }

    private func report(_ value: String, _ type: AVMetadataObject.ObjectType, at time: Date) {
        lastValue = value
        lastScanTime = time
        onCodeScanned?(value, Self.displayName(for: type))
    }

    static func displayName(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: return "QR Code"
        case .microQR: return "Micro QR"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code39Mod43: return "Code 39 Mod 43"
        case .code93: return "Code 93"
        case .itf14: return "ITF-14"
        case .interleaved2of5: return "Interleaved 2 of 5"
        case .codabar: return "Codabar"
        case .pdf417: return "PDF417"
        case .microPDF417: return "Micro PDF417"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited: return "GS1 DataBar"
        default: return type.rawValue
        }
    }
}
