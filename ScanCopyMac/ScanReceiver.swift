import AppKit
import Foundation
import MultipeerConnectivity

/// Data sent by the iPhone for each scan (must match the iPhone app).
struct ScanPayload: Codable {
    let value: String
    let type: String
}

enum AfterScanKey: String, CaseIterable, Identifiable {
    case returnKey, tab, nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnKey: return "Return (next row)"
        case .tab: return "Tab (next column)"
        case .nothing: return "Nothing"
        }
    }

    var keyCode: CGKeyCode? {
        switch self {
        case .returnKey: return 36
        case .tab: return 48
        case .nothing: return nil
        }
    }
}

@MainActor
final class ScanReceiver: NSObject, ObservableObject {
    static let serviceType = "scancopy"

    @Published private(set) var connectedPhones: [String] = []
    @Published private(set) var lastScan: String?
    @Published private(set) var scanCount = 0
    @Published private(set) var hasAccessibility = KeyTyper.isTrusted
    @Published private(set) var networkError: String?
    @Published private(set) var pairingCode: String

    @Published var typingEnabled: Bool {
        didSet { UserDefaults.standard.set(typingEnabled, forKey: "typingEnabled") }
    }
    @Published var afterScan: AfterScanKey {
        didSet { UserDefaults.standard.set(afterScan.rawValue, forKey: "afterScan") }
    }

    private let myPeer = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var accessibilityTimer: Timer?

    override init() {
        let defaults = UserDefaults.standard
        let savedCode = defaults.string(forKey: "pairingCode") ?? ""
        pairingCode = savedCode.count == 6 ? savedCode : Self.randomCode()
        typingEnabled = defaults.object(forKey: "typingEnabled") as? Bool ?? true
        afterScan = AfterScanKey(rawValue: defaults.string(forKey: "afterScan") ?? "") ?? .returnKey
        super.init()
        defaults.set(pairingCode, forKey: "pairingCode")
        startAdvertising()

        // Keep the Accessibility status fresh (the user grants it in System Settings).
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hasAccessibility = KeyTyper.isTrusted
            }
        }
    }

    /// Makes a new pairing code. Connected iPhones are disconnected and must enter the new code.
    func newPairingCode() {
        pairingCode = Self.randomCode()
        UserDefaults.standard.set(pairingCode, forKey: "pairingCode")
        startAdvertising()
    }

    func requestAccessibility() {
        KeyTyper.requestAccess()
        KeyTyper.openAccessibilitySettings()
    }

    // MARK: - Networking

    private func startAdvertising() {
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        session?.delegate = nil
        session?.disconnect()
        connectedPhones = []
        networkError = nil

        let session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.session = session
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    private func handleInvitation(from source: MCNearbyServiceAdvertiser, context: Data?,
                                  reply: @escaping (Bool, MCSession?) -> Void) {
        // Only iPhones that know the pairing code may connect (and type on this Mac).
        let code = context.flatMap { String(data: $0, encoding: .utf8) }
        if source === advertiser, code == pairingCode, let session {
            reply(true, session)
        } else {
            reply(false, nil)
        }
    }

    private func sessionChanged(_ source: MCSession) {
        guard source === session else { return }
        connectedPhones = source.connectedPeers.map(\.displayName)
    }

    private func received(_ data: Data, in source: MCSession) {
        guard source === session,
              let payload = try? JSONDecoder().decode(ScanPayload.self, from: data) else { return }
        let text = Self.sanitize(payload.value)
        guard !text.isEmpty else { return }

        lastScan = text
        scanCount += 1

        guard typingEnabled else { return }
        guard KeyTyper.isTrusted else {
            hasAccessibility = false
            NSSound.beep()
            return
        }
        KeyTyper.type(text)
        if let key = afterScan.keyCode {
            KeyTyper.press(key)
        }
    }

    // MARK: - Helpers

    /// Replaces line breaks / control characters with spaces and limits the length.
    static func sanitize(_ value: String) -> String {
        let cleaned = value.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(4000))
    }

    static func randomCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

extension ScanReceiver: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handleInvitation(from: advertiser, context: context, reply: invitationHandler)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.networkError = "Couldn't start listening. Allow Local Network for ScanCopyMac in System Settings ▸ Privacy & Security."
            }
        }
    }
}

extension ScanReceiver: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.sessionChanged(session) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.received(data, in: session) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
