import XCTest
@testable import ScrollStatsCore

final class HistoryArchiveTests: XCTestCase {
    private func event(id: UUID = UUID(), duration: Double = 10) throws -> ViewingEvent {
        try ViewingEvent(id: id, sessionID: UUID(), platform: "instagram", startedAt: Date(timeIntervalSince1970: 1000.125), duration: duration, source: "test")
    }
    func testRoundTripAndIdempotentImport() throws {
        let value = try event()
        let archive = try HistoryArchive.decode(HistoryArchive(events: [value, value]).encode())
        XCTAssertEqual(try archive.newEvents(existing: []), [value])
        XCTAssertTrue(try archive.newEvents(existing: [value]).isEmpty)
    }
    func testConflictingIDsRejectWholeImport() throws {
        let value = try event()
        let conflict = try event(id: value.id, duration: 15)
        XCTAssertThrowsError(try HistoryArchive(events: [value, conflict]).newEvents(existing: []))
        XCTAssertThrowsError(try HistoryArchive(events: [conflict]).newEvents(existing: [value]))
    }
    func testHighPrecisionTimestampsRoundTripWithoutFalseConflicts() throws {
        for index in 0..<100 {
            let value = try ViewingEvent(sessionID: UUID(), platform: "instagram",
                startedAt: Date(timeIntervalSinceReferenceDate: 815000000 + Double(index) / 333),
                duration: 1.25, source: "test")
            let archive = try HistoryArchive.decode(HistoryArchive(events: [value]).encode())
            XCTAssertTrue(try archive.newEvents(existing: [value]).isEmpty)
        }
    }
    func testUnsupportedVersionAndSizeLimit() {
        XCTAssertThrowsError(try HistoryArchive.decode(Data("{\"version\":2,\"events\":[]}".utf8)))
        XCTAssertThrowsError(try HistoryArchive.decode(Data(repeating: 0, count: HistoryArchive.maximumBytes + 1)))
    }
    func testFileRoundTripAndOversizedFileRejection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let value = try event()
        try HistoryArchive(events: [value]).encode().write(to: url, options: .atomic)
        XCTAssertEqual(try HistoryArchive.read(from: url).events, [value])
        try Data(repeating: 32, count: HistoryArchive.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try HistoryArchive.read(from: url)) { error in
            guard case HistoryArchive.ArchiveError.tooLarge = error else { return XCTFail("Expected size rejection, got \(error)") }
        }
    }
    func testCorruptAndMissingFilesFail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try HistoryArchive.read(from: url))
        try Data("{broken".utf8).write(to: url)
        XCTAssertThrowsError(try HistoryArchive.read(from: url))
    }
    func testExportRejectsConflictingRecords() throws {
        let value = try event()
        let conflicting = try event(id: value.id, duration: 12)
        XCTAssertThrowsError(try HistoryArchive(events: [value, conflicting]).encode())
    }
}
