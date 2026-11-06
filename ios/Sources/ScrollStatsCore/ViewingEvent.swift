import Foundation

public struct ViewingEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let platform: String
    public let startedAt: Date
    public let endedAt: Date
    public let duration: TimeInterval
    public let source: String

    public init(id: UUID = UUID(), sessionID: UUID, platform: String, startedAt: Date, duration: TimeInterval, source: String, endedAt: Date? = nil) throws {
        let end = endedAt ?? startedAt.addingTimeInterval(duration)
        guard duration.isFinite, duration >= 0,
              startedAt.timeIntervalSince1970.isFinite,
              end.timeIntervalSince1970.isFinite, end >= startedAt,
              duration <= end.timeIntervalSince(startedAt) + 0.001,
              !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.invalidEvent }
        self.id = id
        self.sessionID = sessionID
        self.platform = platform
        self.startedAt = startedAt
        self.endedAt = end
        self.duration = duration
        self.source = source
    }
    public enum ValidationError: Error { case invalidEvent }

    private enum CodingKeys: String, CodingKey { case id, sessionID, platform, startedAt, endedAt, duration, source }

    // Synthesized Decodable would bypass the validation in the public initializer.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      sessionID: values.decode(UUID.self, forKey: .sessionID),
                      platform: values.decode(String.self, forKey: .platform),
                      startedAt: values.decode(Date.self, forKey: .startedAt),
                      duration: values.decode(Double.self, forKey: .duration),
                      source: values.decode(String.self, forKey: .source),
                      endedAt: values.decodeIfPresent(Date.self, forKey: .endedAt))
    }
}

public struct Statistics {
    public let count: Int
    public let duration: TimeInterval
    public let sessions: Int
    public var averageDuration: TimeInterval { count == 0 ? 0 : duration / Double(count) }

    // Duration is attributed to event start date. Duplicate IDs never inflate counts.
    public init(events: [ViewingEvent], interval: DateInterval? = nil) {
        var ids = Set<UUID>()
        let unique = events.filter { event in
            let included = interval.map { event.startedAt >= $0.start && event.startedAt < $0.end } ?? true
            return included && event.duration.isFinite && event.duration >= 0 && ids.insert(event.id).inserted
        }
        count = unique.count
        duration = unique.reduce(0) { $0 + $1.duration }
        sessions = Set(unique.map(\.sessionID)).count
    }
}
