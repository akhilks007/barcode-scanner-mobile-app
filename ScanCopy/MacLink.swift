import Foundation
import MultipeerConnectivity
import UIKit

/// Data sent to the Mac helper for each scan.
struct ScanPayload: Codable {
    let value: String
    let type: String
}

enum MacLinkStatus: Equatable {
    case off
    case needsCode
    case searching
    case connecting(String)
    case rejected(String)
    case noPermission
    case connected(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var text: String {
        switch self {
        case .off: return "Off"
        case .needsCode: return "Enter the 6-digit code from your Mac"
        case .searching: return "Looking for your Mac…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .rejected(let name): return "\(name) didn't accept. Check the pairing code"
        case .noPermission: return "Allow Local Network for ScanCopy in iPhone Settings"
        case .connected(let name): return "Connected to \(name)"
        }
    }
}

/// Finds the ScanCopy Mac helper on the local network (Wi-Fi / Bluetooth) and sends it each scan.
@MainActor
final class MacLink: NSObject, ObservableObject {
    static let serviceType = "scancopy"

    @Published private(set) var status: MacLinkStatus = .off

    private let myPeer = PeerIdentity.load(key: "macLinkPeerID", displayName: UIDevice.current.name)
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var pairingCode = ""
    private var isEnabled = false
    private var watchdog: Timer?

    override init() {
        super.init()
        // While enabled but not connected, keep retrying so the link comes back on its own
        // (Mac restarted, woke from sleep, Wi-Fi changed…).
        watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryIfNeeded() }
        }
    }

    func start(pairingCode: String) {
        teardown()
        isEnabled = true
        self.pairingCode = pairingCode
        guard pairingCode.count == 6 else {
            status = .needsCode
            return
        }
        let session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: Self.serviceType)
        browser.delegate = self
        self.session = session
        self.browser = browser
        status = .searching
        browser.startBrowsingForPeers()
    }

    func stop() {
        isEnabled = false
        teardown()
        status = .off
    }

    /// Call when the app comes back to the foreground (iOS drops the link in the background).
    func resume() {
        guard isEnabled, !status.isConnected else { return }
        start(pairingCode: pairingCode)
    }

    @discardableResult
    func send(value: String, type: String) -> Bool {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(ScanPayload(value: value, type: type)) else { return false }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            return true
        } catch {
            print("MacLink send error: \(error)")
            return false
        }
    }

    // MARK: - Internals

    private func retryIfNeeded() {
        guard isEnabled, pairingCode.count == 6 else { return }
        switch status {
        case .connected, .connecting, .off, .needsCode:
            return
        case .searching, .rejected, .noPermission:
            let previous = status
            start(pairingCode: pairingCode)
            if case .rejected = previous { status = previous }
        }
    }

    private func teardown() {
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.delegate = nil
        session?.disconnect()
        session = nil
    }

    private func peerFound(_ peer: MCPeerID, by source: MCNearbyServiceBrowser) {
        guard source === browser, let session, !session.connectedPeers.contains(peer) else { return }
        status = .connecting(peer.displayName)
        source.invitePeer(peer, to: session, withContext: Data(pairingCode.utf8), timeout: 15)
    }

    private func stateChanged(_ state: MCSessionState, peer: MCPeerID, in source: MCSession) {
        guard source === session else { return }
        switch state {
        case .connected:
            status = .connected(peer.displayName)
        case .connecting:
            status = .connecting(peer.displayName)
        case .notConnected:
            guard source.connectedPeers.isEmpty else { return }
            if case .connecting(let name) = status {
                status = .rejected(name)
            } else if status.isConnected {
                status = .searching
            }
            scheduleRetry(for: source)
        @unknown default:
            break
        }
    }

    /// Restart discovery shortly after a disconnect so the Mac can be found again.
    private func scheduleRetry(for source: MCSession) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard self.isEnabled, self.session === source, !self.status.isConnected else { return }
            let previous = self.status
            self.start(pairingCode: self.pairingCode)
            if case .rejected = previous { self.status = previous }
        }
    }
}

extension MacLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.peerFound(peerID, by: browser) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if browser === self.browser { self.status = .noPermission }
            }
        }
    }
}

extension MacLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.stateChanged(state, peer: peerID, in: session) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

/// Reuses the same peer identity across launches (recommended by Apple for reliable reconnection).
enum PeerIdentity {
    static func load(key: String, displayName: String) -> MCPeerID {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let peer = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           peer.displayName == displayName {
            return peer
        }
        let peer = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        }
        return peer
    }
}
