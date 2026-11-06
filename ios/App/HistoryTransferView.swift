import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ScrollStatsCore

struct HistoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct HistoryTransferView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [StoredEvent]
    @State private var importing = false
    @State private var exporting = false
    @State private var document = HistoryDocument(data: Data())
    @State private var pending: [ViewingEvent] = []
    @State private var confirming = false
    @State private var message: String?
    @State private var working = false

    var body: some View {
        Section("Local history backups") {
            Button("Import ScrollStats backup") { importing = true }
            Button("Export history") {
                Task { @MainActor in
                    working = true
                    defer { working = false }
                    do {
                        let values = try records.map { try $0.event() }
                        let data = try await Task.detached(priority: .userInitiated) {
                            try HistoryArchive(events: values).encode()
                        }.value
                        document = HistoryDocument(data: data)
                        exporting = true
                    } catch { message = "History could not be exported. No records were changed." }
                }
            }.disabled(records.isEmpty)
            if working { ProgressView("Processing history…") }
            Text("Imports preserve their declared source. A backup is not independently verified tracking data. Instagram, TikTok and YouTube exports are not supported yet.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(working)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            Task { @MainActor in
                working = true
                defer { working = false }
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let existing = try records.map { try $0.event() }
                    pending = try await Task.detached(priority: .userInitiated) {
                        try HistoryArchive.read(from: url).newEvents(existing: existing)
                    }.value
                    if pending.isEmpty { message = "This backup contains no new events." }
                    else { confirming = true }
                } catch { message = "Import failed. Choose a valid ScrollStats backup under 10 MB with no conflicting event IDs. Your history is unchanged." }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "ScrollStats-history") { result in
            if case .failure = result { message = "The backup could not be saved." }
        }
        .confirmationDialog("Import \(pending.count) events?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Import events") { savePending() }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: { Text("These records will appear in your statistics with their declared source.") }
        .alert("History", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func savePending() {
        // Separate context gives the import a single explicit save/rollback boundary.
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        do {
            let existing = try writer.fetch(FetchDescriptor<StoredEvent>()).map { try $0.event() }
            let additions = try HistoryArchive(events: pending).newEvents(existing: existing)
            for event in additions { writer.insert(StoredEvent(event)) }
            try writer.save()
            message = "Imported \(additions.count) events."
        } catch {
            writer.rollback()
            message = "The import could not be saved. Your history is unchanged."
        }
        pending = []
    }
}
