import SwiftUI
import SwiftData
import Charts
import ScrollStatsCore

struct TrendsView: View {
    @Query(sort: \StoredEvent.startedAt) private var records: [StoredEvent]
    @State private var range = 7
    @State private var selection: Date?
    private var history: HistoryAnalytics { HistoryAnalytics(events: records.compactMap { try? $0.event() }) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let summary = history
            let daily = summary.days(endingOn: timeline.date, count: range, calendar: .current)
            let selected = selection.flatMap { date in daily.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("See your patterns").font(.largeTitle.bold())
                        Text("From saved event records · automatic tracking unavailable")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Picker("History range", selection: $range) {
                            Text("Week").tag(7)
                            Text("Month").tag(30)
                            Text("Year").tag(365)
                        }.pickerStyle(.segmented).onChange(of: range) { _, _ in selection = nil }
                        VStack(alignment: .leading) {
                            Text(selected.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Today")
                                .font(.headline)
                            Text("\(selected?.count ?? daily.last?.count ?? 0) videos")
                                .font(.title.bold())
                            Chart(daily) { day in
                                BarMark(x: .value("Date", day.date, unit: .day), y: .value("Videos", day.count))
                                    .foregroundStyle(.mint)
                                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue("\(day.count) videos")
                            }.chartXSelection(value: $selection).frame(height: 200)
                            Text("Select a date to inspect its count.").font(.caption).foregroundStyle(.secondary)
                        }.padding().background(.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                        if records.isEmpty {
                            ContentUnavailableView("No history yet", systemImage: "chart.bar.xaxis", description: Text("Import a ScrollStats backup in Settings. No example data is included in these totals."))
                        }
                        VStack(spacing: 12) {
                            metric("Lifetime videos", "\(summary.lifetime.count)")
                            metric("Recorded viewing time", duration(summary.lifetime.duration))
                            metric("Average per video", duration(summary.lifetime.averageDuration))
                            metric("Longest session", duration(summary.longestSession?.viewingDuration ?? 0))
                            if let hour = summary.peakHour(calendar: .current) { metric("Peak hour (local)", String(format: "%02d:00", hour)) }
                            let comparison = summary.days(endingOn: timeline.date, count: 2, calendar: .current)
                            if comparison.count == 2 {
                                let delta = comparison[1].count - comparison[0].count
                                metric("Today vs yesterday", "\(delta >= 0 ? "+" : "")\(delta) videos")
                            }
                        }
                        if !summary.platformCounts.isEmpty {
                            Text("By platform").font(.title2.bold())
                            ForEach(summary.platformCounts.keys.sorted(), id: \.self) { platform in
                                metric(platform.capitalized, "\(summary.platformCounts[platform] ?? 0)")
                            }
                        }
                        Text("Recent sessions").font(.title2.bold())
                        ForEach(summary.sessions.prefix(30)) { session in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text("\(session.count) videos · \(duration(session.viewingDuration))")
                                Text(session.platforms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Viewing time comes from event durations, not measured attention. Durations are assigned to the day each video started. Imported records retain their declared source.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24)
                }.navigationTitle("Trends").navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).bold() }
    }
    private func duration(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.0f sec", seconds) : String(format: "%.1f min", seconds / 60)
    }
}
