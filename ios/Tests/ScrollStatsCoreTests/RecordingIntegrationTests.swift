import XCTest
@testable import ScrollStatsCore

final class RecordingIntegrationTests: XCTestCase {
    func testObservationsThroughDiskBackupToAnalytics() throws {
        var counter = TransitionCounter()
        var persisted = [UUID: ViewingEvent]()
        let a = TransitionCounter.Screen.video(platform: "instagram", identity: "private-a")
        let b = TransitionCounter.Screen.video(platform: "instagram", identity: "private-b")
        let observations: [(Double, TransitionCounter.Screen)] = [
            (0, a), (0.5, a), (5, a), (6, .overlay), (8, .unknown),
            (10, a), (10.5, a), (20, b), (20.5, b), (25, .outside)
        ]
        for (uptime, screen) in observations {
            let updates = try counter.observe(screen, uptime: uptime, date: Date(timeIntervalSince1970: 1000 + uptime))
            for update in updates { persisted[update.id] = update }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try HistoryArchive(events: Array(persisted.values)).encode()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-"))
        try data.write(to: url, options: .atomic)
        let restored = try HistoryArchive.read(from: url)
        XCTAssertTrue(try restored.newEvents(existing: Array(persisted.values)).isEmpty)
        let analytics = HistoryAnalytics(events: restored.events)
        XCTAssertEqual(analytics.lifetime.count, 2)
        XCTAssertEqual(analytics.lifetime.duration, 21)
        XCTAssertEqual(analytics.sessions.count, 1)
        XCTAssertEqual(analytics.sessions[0].endedAt, Date(timeIntervalSince1970: 1025))
        XCTAssertEqual(analytics.sessions[0].viewingDuration, 21)
    }

    func testSessionGapBoundary() throws {
        let screen = TransitionCounter.Screen.video(platform: "instagram", identity: "a")
        for gap in [29.999, 30, 30.001] {
            var counter = TransitionCounter()
            func observe(_ screen: TransitionCounter.Screen, _ uptime: Double) throws -> [ViewingEvent] {
                try counter.observe(screen, uptime: uptime, date: Date(timeIntervalSince1970: uptime))
            }
            _ = try observe(screen, 0)
            let first = try XCTUnwrap(observe(screen, 0.5).last)
            _ = try observe(.outside, 1)
            _ = try observe(screen, 1 + gap)
            let returned = try XCTUnwrap(observe(screen, 1.5 + gap).last)
            XCTAssertEqual(returned.id == first.id, gap <= 30)
            XCTAssertEqual(returned.sessionID == first.sessionID, gap <= 30)
        }
    }

    func testConfirmationWindowBoundaries() throws {
        let screen = TransitionCounter.Screen.video(platform: "instagram", identity: "a")
        for gap in [0.349, 0.35, 2, 2.001] {
            var counter = TransitionCounter()
            _ = try counter.observe(screen, uptime: 0, date: Date(timeIntervalSince1970: 0))
            let updates = try counter.observe(screen, uptime: gap, date: Date(timeIntervalSince1970: gap))
            XCTAssertEqual(updates.count, (0.35...2).contains(gap) ? 1 : 0)
        }
    }

    func testRejectedIdentityDoesNotPoisonValidState() throws {
        var counter = TransitionCounter()
        let screen = TransitionCounter.Screen.video(platform: "instagram", identity: "a")
        _ = try counter.observe(screen, uptime: 0, date: Date())
        let first = try XCTUnwrap(counter.observe(screen, uptime: 0.5, date: Date()).last)
        XCTAssertThrowsError(try counter.observe(.video(platform: "instagram", identity: " "), uptime: 10, date: Date()))
        let next = try XCTUnwrap(counter.observe(screen, uptime: 1, date: Date()).last)
        XCTAssertEqual(next.id, first.id)
        XCTAssertEqual(next.duration, 1)
    }
}
