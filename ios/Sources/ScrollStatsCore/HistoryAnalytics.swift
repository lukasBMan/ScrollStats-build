import Foundation

public struct DailyActivity: Identifiable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let count: Int
    public let duration: TimeInterval
}

public struct SessionSummary: Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let count: Int
    public let viewingDuration: TimeInterval
    public let platforms: [String]
}

public struct HistoryAnalytics {
    public let events: [ViewingEvent]

    public init(events: [ViewingEvent]) {
        var seen = Set<UUID>()
        self.events = events.filter { seen.insert($0.id).inserted }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public var lifetime: Statistics { Statistics(events: events) }
    public var platformCounts: [String: Int] {
        Dictionary(grouping: events, by: \.platform).mapValues(\.count)
    }
    public var sessions: [SessionSummary] {
        Dictionary(grouping: events, by: \.sessionID).map { id, values in
            SessionSummary(id: id, startedAt: values.map(\.startedAt).min()!,
                endedAt: values.map(\.endedAt).max()!,
                count: values.count, viewingDuration: values.reduce(0) { $0 + $1.duration },
                platforms: Set(values.map(\.platform)).sorted())
        }.sorted { $0.startedAt > $1.startedAt }
    }
    public var longestSession: SessionSummary? { sessions.max { $0.viewingDuration < $1.viewingDuration } }

    public func peakHour(calendar: Calendar) -> Int? {
        let counts = Dictionary(grouping: events) { calendar.component(.hour, from: $0.startedAt) }.mapValues(\.count)
        return counts.keys.sorted().max { counts[$0]! < counts[$1]! }
    }

    /// Includes zero-count days. Calendar arithmetic handles local DST boundaries.
    /// Viewing duration remains attributed to the event's start day.
    public func days(endingOn date: Date, count: Int, calendar: Calendar) -> [DailyActivity] {
        guard count > 0, count <= 3660 else { return [] }
        let end = calendar.startOfDay(for: date)
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startedAt) }
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let values = grouped[day] ?? []
            return DailyActivity(date: day, count: values.count, duration: values.reduce(0) { $0 + $1.duration })
        }
    }
}
