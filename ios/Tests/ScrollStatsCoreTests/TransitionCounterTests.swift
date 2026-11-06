import XCTest
@testable import ScrollStatsCore

final class TransitionCounterTests: XCTestCase {
    private let a = TransitionCounter.Screen.video(platform: "instagram", identity: "a")
    private let b = TransitionCounter.Screen.video(platform: "instagram", identity: "b")
    private func input(_ counter: inout TransitionCounter, _ screen: TransitionCounter.Screen,
                       _ time: Double, interaction: Bool = false, wall: Double? = nil) throws -> [ViewingEvent] {
        try counter.observe(screen, uptime: time, date: Date(timeIntervalSince1970: wall ?? (1000 + time)), userInteraction: interaction)
    }
    private func start(_ counter: inout TransitionCounter) throws -> ViewingEvent {
        XCTAssertTrue(try input(&counter, a, 0).isEmpty)
        return try XCTUnwrap(input(&counter, a, 0.5).last)
    }

    func testInitialVideoAndDuplicatesUseOneID() throws {
        var counter = TransitionCounter()
        let initial = try start(&counter)
        XCTAssertEqual(initial.startedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(initial.duration, 0.5)
        for time in [0.5, 1, 2, 3] {
            let update = try XCTUnwrap(input(&counter, a, time).last)
            XCTAssertEqual(update.id, initial.id)
            XCTAssertEqual(update.duration, time)
        }
    }
    func testConfirmedTransitionAndRevisitCountSeparately() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        _ = try input(&counter, b, 5)
        let updates = try input(&counter, b, 5.5)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].duration, 5)
        XCTAssertEqual(updates[1].duration, 0.5)
        XCTAssertNotEqual(updates[1].id, first.id)
        XCTAssertEqual(updates[1].sessionID, first.sessionID)
        _ = try input(&counter, a, 10)
        let revisit = try XCTUnwrap(input(&counter, a, 10.5).last)
        XCTAssertNotEqual(revisit.id, first.id)
    }
    func testTransientIdentityDoesNotCount() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        _ = try input(&counter, b, 1)
        let result = try input(&counter, a, 1.1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, first.id)
        XCTAssertEqual(result[0].duration, 1.1)
    }
    func testOverlayResumeExcludesHiddenTimeAndDoesNotRecount() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        XCTAssertEqual(try input(&counter, .overlay, 5).last?.duration, 5)
        XCTAssertTrue(try input(&counter, .overlay, 10).isEmpty)
        _ = try input(&counter, a, 20)
        let resumed = try XCTUnwrap(input(&counter, a, 20.5).last)
        XCTAssertEqual(resumed.id, first.id)
        XCTAssertEqual(resumed.duration, 5.5)
        XCTAssertEqual(resumed.endedAt, Date(timeIntervalSince1970: 1020.5))
        XCTAssertEqual(HistoryAnalytics(events: [resumed]).sessions.first?.endedAt, resumed.endedAt)
    }
    func testLongInterruptionCreatesNewSession() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        _ = try input(&counter, .outside, 5)
        _ = try input(&counter, a, 36)
        let resumed = try XCTUnwrap(input(&counter, a, 36.5).last)
        XCTAssertNotEqual(resumed.id, first.id)
        XCTAssertNotEqual(resumed.sessionID, first.sessionID)
    }
    func testUnknownScreenStopsDuration() throws {
        var counter = TransitionCounter()
        _ = try start(&counter)
        XCTAssertEqual(try input(&counter, .unknown, 2).last?.duration, 2)
        XCTAssertTrue(try input(&counter, .unknown, 20).isEmpty)
    }
    func testIdleHeartbeatsCannotCreatePhantomVideos() throws {
        var counter = TransitionCounter()
        _ = try start(&counter)
        XCTAssertEqual(try input(&counter, a, 100).last?.duration, 90.5)
        XCTAssertTrue(try input(&counter, a, 101).isEmpty)
        XCTAssertTrue(try input(&counter, a, 200).isEmpty)
        _ = try input(&counter, a, 201, interaction: true)
        XCTAssertEqual(try input(&counter, a, 201.5).count, 1)
    }
    func testClockChangesDoNotAffectDurationsAndStaleInputIsRejected() throws {
        var counter = TransitionCounter()
        _ = try start(&counter)
        XCTAssertEqual(try input(&counter, a, 2, wall: 0).last?.duration, 2)
        XCTAssertThrowsError(try input(&counter, a, 1))
        XCTAssertThrowsError(try input(&counter, a, .nan))
        XCTAssertEqual(try input(&counter, a, 3).last?.duration, 3)
    }
    func testPlatformSwitchCreatesNewSessionAndIdentityIsNotStored() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        let other = TransitionCounter.Screen.video(platform: "tiktok", identity: "private-content-token")
        _ = try input(&counter, other, 5)
        let update = try XCTUnwrap(input(&counter, other, 5.5).last)
        XCTAssertNotEqual(first.sessionID, update.sessionID)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(update), as: UTF8.self).contains("private-content-token"))
    }

    func testStopFlushesAndClearsSessionState() throws {
        var counter = TransitionCounter()
        let first = try start(&counter)
        XCTAssertEqual(try counter.stop(uptime: 2, date: Date()).last?.duration, 2)
        _ = try input(&counter, a, 3)
        let restarted = try XCTUnwrap(input(&counter, a, 3.5).last)
        XCTAssertNotEqual(first.id, restarted.id)
        XCTAssertNotEqual(first.sessionID, restarted.sessionID)
    }

    func testStaleCandidateCannotInventUnobservedViewingTime() throws {
        var counter = TransitionCounter()
        XCTAssertTrue(try input(&counter, a, 0).isEmpty)
        XCTAssertTrue(try input(&counter, a, 100).isEmpty)
        let initial = try XCTUnwrap(input(&counter, a, 100.5).last)
        XCTAssertEqual(initial.startedAt, Date(timeIntervalSince1970: 1100))
        XCTAssertEqual(initial.duration, 0.5)
    }

    func testDeterministicEventStormMaintainsSnapshotInvariants() throws {
        var counter = TransitionCounter()
        var seed: UInt64 = 42
        var time: Double = 0
        var saved = [UUID: ViewingEvent]()
        let screens: [TransitionCounter.Screen] = [a, a, a, b, .overlay, .unknown, .outside,
            .video(platform: "youtube", identity: "short")]
        for _ in 0..<3000 {
            seed = seed &* 6364136223846793005 &+ 1
            time += Double((seed >> 32) % 1000) / 100
            let screen = screens[Int(seed % UInt64(screens.count))]
            for update in try input(&counter, screen, time, interaction: seed % 7 == 0) {
                XCTAssertGreaterThanOrEqual(update.duration, 0)
                XCTAssertLessThanOrEqual(update.duration, update.endedAt.timeIntervalSince(update.startedAt) + 0.001)
                if let previous = saved[update.id] {
                    XCTAssertEqual(previous.startedAt, update.startedAt)
                    XCTAssertEqual(previous.sessionID, update.sessionID)
                    XCTAssertGreaterThanOrEqual(update.duration, previous.duration)
                    XCTAssertGreaterThanOrEqual(update.endedAt, previous.endedAt)
                }
                saved[update.id] = update
            }
        }
        XCTAssertFalse(saved.isEmpty)
    }
}
