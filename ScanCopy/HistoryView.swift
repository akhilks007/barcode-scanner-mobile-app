import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @State private var copiedID: ScanItem.ID?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView("No scans yet",
                                           systemImage: "barcode.viewfinder",
                                           description: Text("Codes you scan will appear here."))
                } else {
                    List {
                        Section {
                            ForEach(store.items) { item in
                                Button {
                                    copy(item)
                                } label: {
                                    HistoryRow(item: item, justCopied: copiedID == item.id)
                                }
                                .foregroundStyle(.primary)
                                .contextMenu {
                                    Button { copy(item) } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    ShareLink(item: item.value)
                                    if let url = item.webURL {
                                        Link(destination: url) {
                                            Label("Open Link", systemImage: "safari")
                                        }
                                    }
                                }
                            }
                            .onDelete { store.delete(at: $0) }
                        } footer: {
                            Text("Tap a scan to copy it again. Swipe left to delete.")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                        .disabled(store.items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear all scans?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { store.clear() }
            }
        }
    }

    private func copy(_ item: ScanItem) {
        UIPasteboard.general.string = item.value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == item.id { copiedID = nil }
        }
    }
}

struct HistoryRow: View {
    let item: ScanItem
    let justCopied: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.value)
                    .font(.body.monospaced())
                    .lineLimit(2)
                Text("\(item.type) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundStyle(justCopied ? Color.green : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}
