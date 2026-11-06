import Foundation

/// Consumes observations from a future authorized platform adapter. This type does
/// not inspect other apps. Identity tokens remain in memory and are never exported.
public struct TransitionCounter {
    public enum Screen: Equatable {
        case video(platform: String, identity: String)
        case overlay
        case outside
        case unknown
    }
    public enum InputError: Error { case invalidObservation }
    public static let confirmationDelay: TimeInterval = 0.35
    public static let confirmationWindow: TimeInterval = 2
    public static let sessionGap: TimeInterval = 30
    public static let inactivityLimit: TimeInterval = 90

    private struct Candidate {
        let screen: Screen
        let uptime: TimeInterval
        let date: Date
    }
    private struct Entry {
        let id: UUID
        let sessionID: UUID
        let screen: Screen
        let date: Date
        let firstUptime: TimeInterval
        var accumulated: TimeInterval = 0
        var segmentStart: TimeInterval?

        func snapshot(at uptime: TimeInterval) throws -> ViewingEvent {
            guard case .video(let platform, _) = screen else { throw InputError.invalidObservation }
            return try ViewingEvent(id: id, sessionID: sessionID, platform: platform, startedAt: date,
                duration: accumulated + (segmentStart.map { max(0, uptime - $0) } ?? 0), source: "observed-transition-v1",
                endedAt: date.addingTimeInterval(uptime - firstUptime))
        }
    }
    private var entry: Entry?
    private var candidate: Candidate?
    private var lastUptime: TimeInterval?
    private var lastActivity: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var idleScreen: Screen?

    public init() {}

    /// Flush and forget all identity/session state when consent is revoked or the
    /// adapter shuts down. The caller must persist returned records before disposal.
    public mutating func stop(uptime: TimeInterval, date: Date) throws -> [ViewingEvent] {
        let updates = try observe(.outside, uptime: uptime, date: date)
        self = Self()
        return updates
    }

    /// Returns records to upsert by ID, including the initial video once confirmed.
    /// Call from a single serial owner with monotonic uptime; wall clock is metadata.
    public mutating func observe(_ screen: Screen, uptime: TimeInterval, date: Date,
                                 userInteraction: Bool = false) throws -> [ViewingEvent] {
        guard uptime.isFinite, uptime >= 0, uptime >= (lastUptime ?? 0),
              date.timeIntervalSinceReferenceDate.isFinite else { throw InputError.invalidObservation }
        if case .video(let platform, let identity) = screen {
            guard !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputError.invalidObservation }
        }
        lastUptime = uptime
        var updates = [ViewingEvent]()

        if entry?.segmentStart != nil, uptime - lastActivity >= Self.inactivityLimit {
            updates += try pause(at: lastActivity + Self.inactivityLimit)
            idleScreen = entry?.screen
            entry = nil
            candidate = nil
        }
        guard case .video = screen else {
            candidate = nil
            updates += try pause(at: uptime)
            return updates
        }
        if screen == idleScreen && !userInteraction { return updates }
        idleScreen = nil

        if entry?.screen == screen, entry?.segmentStart != nil {
            candidate = nil
            if userInteraction { lastActivity = uptime }
            if let entry { updates.append(try entry.snapshot(at: uptime)) }
            return updates
        }
        if candidate?.screen != screen || candidate.map({ uptime - $0.uptime > Self.confirmationWindow }) == true {
            candidate = Candidate(screen: screen, uptime: uptime, date: date)
        }
        guard let pending = candidate else { return updates }
        guard uptime - pending.uptime >= Self.confirmationDelay else {
            if let entry, entry.segmentStart != nil { updates.append(try entry.snapshot(at: pending.uptime)) }
            return updates
        }

        let previous = entry
        let withinSession = pausedAt.map { pending.uptime - $0 <= Self.sessionGap } ?? true
        let samePlatform: Bool
        if case .video(let oldPlatform, _) = previous?.screen,
           case .video(let newPlatform, _) = screen { samePlatform = oldPlatform == newPlatform }
        else { samePlatform = false }
        updates += try pause(at: pending.uptime)
        if previous?.screen == screen && withinSession {
            entry?.segmentStart = pending.uptime
        } else {
            entry = Entry(id: UUID(), sessionID: withinSession && samePlatform ? previous!.sessionID : UUID(),
                          screen: screen, date: pending.date, firstUptime: pending.uptime, segmentStart: pending.uptime)
        }
        pausedAt = nil
        lastActivity = uptime
        candidate = nil
        if let entry { updates.append(try entry.snapshot(at: uptime)) }
        return updates
    }

    private mutating func pause(at uptime: TimeInterval) throws -> [ViewingEvent] {
        guard var current = entry, let start = current.segmentStart else { return [] }
        let snapshot = try current.snapshot(at: uptime)
        current.accumulated += max(0, uptime - start)
        current.segmentStart = nil
        entry = current
        pausedAt = uptime
        return [snapshot]
    }
}
