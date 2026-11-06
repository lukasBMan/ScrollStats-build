import Foundation

/// ScrollStats interchange format, not a parser for third-party watch-history exports.
public struct HistoryArchive: Codable, Sendable {
    public let version: Int
    public let dateEncoding: String
    public let events: [ViewingEvent]
    public static let maximumBytes = 10 * 1024 * 1024
    public enum ArchiveError: Error { case unsupportedVersion, tooLarge, conflictingID }

    public init(events: [ViewingEvent]) {
        version = 1
        dateEncoding = "secondsSince2001"
        self.events = events
    }

    /// Bounded reads also enforce the limit if the file grows after selection.
    public static func read(from url: URL) throws -> HistoryArchive {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw ArchiveError.tooLarge }
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> HistoryArchive {
        guard data.count <= maximumBytes else { throw ArchiveError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.version == 1, archive.dateEncoding == "secondsSince2001" else { throw ArchiveError.unsupportedVersion }
        _ = try archive.newEvents(existing: [])
        return archive
    }

    public func encode() throws -> Data {
        guard version == 1, dateEncoding == "secondsSince2001" else { throw ArchiveError.unsupportedVersion }
        _ = try newEvents(existing: [])
        let encoder = JSONEncoder()
        // Preserve Date's exact reference interval; epoch conversions introduce rounding.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ArchiveError.tooLarge }
        return data
    }

    public func newEvents(existing: [ViewingEvent]) throws -> [ViewingEvent] {
        var known = [UUID: ViewingEvent]()
        for event in existing { known[event.id] = event }
        var additions = [ViewingEvent]()
        for event in events {
            if let previous = known[event.id] {
                guard previous == event else { throw ArchiveError.conflictingID }
            } else {
                additions.append(event)
                known[event.id] = event
            }
        }
        return additions
    }
}
