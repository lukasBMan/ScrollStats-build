import SwiftUI
import SwiftData
import ScrollStatsCore

@Model
final class StoredEvent {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var platform: String
    var startedAt: Date
    var endedAt: Date?
    var duration: Double
    var source: String
    init(_ event: ViewingEvent) {
        id = event.id
        sessionID = event.sessionID
        platform = event.platform
        startedAt = event.startedAt
        endedAt = event.endedAt
        duration = event.duration
        source = event.source
    }
    func event() throws -> ViewingEvent {
        try ViewingEvent(id: id, sessionID: sessionID, platform: platform, startedAt: startedAt, duration: duration, source: source, endedAt: endedAt)
    }
}

@main
struct ScrollStatsApp: App {
    private let storage: Result<ModelContainer, Error> = Result {
        try ModelContainer(for: StoredEvent.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
    }
    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                TabView {
                    DashboardView().tabItem { Label("Overview", systemImage: "chart.bar.xaxis") }
                    TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }.modelContainer(container).tint(.mint)
            case .failure:
                ContentUnavailableView("History unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Local storage could not open. Restart the app. Your history has not been reset."))
            }
        }
    }
}

struct DashboardView: View {
    @Query(sort: \StoredEvent.startedAt, order: .reverse) private var events: [StoredEvent]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Your scrolling, understood.").font(.largeTitle.bold())
                    Label("Automatic counting unavailable", systemImage: "info.circle").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECORDED VIDEOS").font(.caption.bold()).tracking(2)
                        Text(events.count, format: .number).font(.system(size: 64, weight: .bold, design: .rounded))
                        Text("Lifetime history from event records").font(.subheadline)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background(.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 28))
                    if events.isEmpty {
                        ContentUnavailableView("Your history starts here", systemImage: "play.rectangle", description: Text("No video events have been recorded. Screen Time does not provide individual Reel, TikTok or Short transitions. Counts will never be estimated from time spent."))
                    } else {
                        Text("Recent history").font(.title2.bold())
                        ForEach(events.prefix(50)) { event in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(event.platform.capitalized).font(.headline)
                                    Text(event.startedAt, style: .date)
                                    Text("Source: \(event.source)").font(.caption)
                                }
                                Spacer()
                                Text(event.duration, format: .number.precision(.fractionLength(0)))
                                Text("sec")
                            }
                        }
                    }
                }.padding(24)
            }.navigationTitle("ScrollStats").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SettingsView: View {
    @AppStorage("showPrivacyDetails") private var showPrivacyDetails = true
    var body: some View {
        NavigationStack {
            Form {
                HistoryTransferView()
                Section("Tracking on iPhone") {
                    Label("Not connected", systemImage: "pause.circle")
                    Text("Automatic video counting is not implemented. Screen Time measures app usage but does not supply the video transitions this app needs.")
                    Text("No monitoring permission is requested by this version.")
                }
                Section("Privacy") {
                    Toggle("Show privacy details", isOn: $showPrivacyDetails)
                    if showPrivacyDetails {
                        Text("History is stored locally. No analytics SDK, account, cloud sync, screen recording or backend is included. Standard device backups may include local app data.")
                    }
                }
            }.navigationTitle("Settings")
        }
    }
}
