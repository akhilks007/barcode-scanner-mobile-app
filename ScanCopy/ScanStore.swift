import SwiftUI

struct ScanItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let value: String
    let type: String
    let date: Date
}

extension ScanItem {
    /// Returns a URL if the scanned value is a web link (so we can offer "Open").
    var webURL: URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

/// Keeps a history of scans, saved on the phone.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var items: [ScanItem] = []

    private let storageKey = "scanHistory"
    private let limit = 500

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ScanItem].self, from: data) {
            items = saved
        }
    }

    @discardableResult
    func add(value: String, type: String) -> ScanItem {
        let item = ScanItem(value: value, type: type, date: Date())
        items.insert(item, at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        save()
        return item
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
