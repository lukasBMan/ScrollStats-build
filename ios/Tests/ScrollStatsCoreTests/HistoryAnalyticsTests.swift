import XCTest
@testable import ScrollStatsCore

final class HistoryAnalyticsTests: XCTestCase {
    private func event(_ date: Date, seconds: Double = 10, session: UUID = UUID(), platform: String = "instagram") throws -> ViewingEvent {
        try ViewingEvent(sessionID: session, platform: platform, startedAt: date, duration: seconds, source: "test")
    }

    func testDecodedInvalidEventsAreRejected() throws {
        let valid = try event(Date())
        let data = try JSONEncoder().encode(valid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["duration"] = -10
        XCTAssertThrowsError(try JSONDecoder().decode(ViewingEvent.self, from: JSONSerialization.data(withJSONObject: object)))
        object["duration"] = 10
        object["platform"] = "  "
        XCTAssertThrowsError(try JSONDecoder().decode(ViewingEvent.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testCodableRoundTrip() throws {
        let value = try event(Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try JSONDecoder().decode(ViewingEvent.self, from: JSONEncoder().encode(value)), value)
    }

    func testSessionsExcludeInterVideoGapsAndDuplicates() throws {
        let id = UUID()
        let first = try event(Date(timeIntervalSince1970: 100), session: id)
        let second = try event(Date(timeIntervalSince1970: 200), seconds: 20, session: id, platform: "youtube")
        let history = HistoryAnalytics(events: [second, first, first])
        XCTAssertEqual(history.lifetime.count, 2)
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.longestSession?.viewingDuration, 30)
        XCTAssertEqual(history.longestSession?.endedAt, Date(timeIntervalSince1970: 220))
        XCTAssertEqual(history.platformCounts, ["instagram": 1, "youtube": 1])
    }

    func testDailyBucketsAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(next.timeIntervalSince(start), 23 * 3600)
        let history = HistoryAnalytics(events: [try event(start), try event(next)])
        let days = history.days(endingOn: next, count: 3, calendar: calendar)
        XCTAssertEqual(days.map(\.count), [0, 1, 1])
        XCTAssertEqual(days.map(\.duration), [0, 10, 10])
        XCTAssertEqual(history.peakHour(calendar: calendar), 0)
    }

    func testEmptyHistory() {
        let history = HistoryAnalytics(events: [])
        XCTAssertNil(history.longestSession)
        XCTAssertNil(history.peakHour(calendar: .current))
        XCTAssertEqual(history.days(endingOn: Date(), count: 7, calendar: .current).count, 7)
        XCTAssertTrue(history.days(endingOn: Date(), count: -1, calendar: .current).isEmpty)
    }
    func testLegacyEventsDeriveEndDateAndInvalidEndDatesFail() throws {
        let original = try event(Date(timeIntervalSince1970: 1000))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "endedAt")
        let legacy = try JSONDecoder().decode(ViewingEvent.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.endedAt, Date(timeIntervalSince1970: 1010))
        XCTAssertThrowsError(try ViewingEvent(sessionID: UUID(), platform: "instagram", startedAt: original.startedAt,
            duration: 10, source: "test", endedAt: original.startedAt.addingTimeInterval(5)))
    }
}
