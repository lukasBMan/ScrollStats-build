import XCTest
@testable import ScrollStatsCore
final class StatisticsTests: XCTestCase {
    func testDuplicates() throws {
        let event = try ViewingEvent(sessionID: UUID(), platform: "instagram", startedAt: Date(), duration: 12, source: "test")
        let result = Statistics(events: [event, event])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.duration, 12)
        XCTAssertEqual(result.sessions, 1)
    }
    func testDateBoundary() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(86400)
        let events = try [start, end].map { try ViewingEvent(sessionID: UUID(), platform: "youtube", startedAt: $0, duration: 10, source: "test") }
        XCTAssertEqual(Statistics(events: events, interval: DateInterval(start: start, end: end)).count, 1)
    }
    func testEmptyAndInvalidDuration() {
        XCTAssertEqual(Statistics(events: []).averageDuration, 0)
        XCTAssertThrowsError(try ViewingEvent(sessionID: UUID(), platform: "tiktok", startedAt: Date(), duration: -1, source: "test"))
    }
}
