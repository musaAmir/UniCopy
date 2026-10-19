import XCTest
@testable import UniCopyCore

final class CaptureHistoryTests: XCTestCase {
    func testNewestEntryComesFirstAndDuplicatesMoveUp() {
        var history = CaptureHistory()
        history.add("one")
        history.add("two")
        history.add("one")
        XCTAssertEqual(history.entries, ["one", "two"])
    }

    func testHistoryKeepsOnlyTheLimitAndIgnoresEmptyText() {
        var history = CaptureHistory(limit: 3)
        for text in ["one", "two", "", "three", "four"] { history.add(text) }
        XCTAssertEqual(history.entries, ["four", "three", "two"])
    }

    func testPromotingAnEntryMovesItToTheTop() {
        var history = CaptureHistory()
        history.add("one"); history.add("two"); history.add("three")
        history.promote("two")
        XCTAssertEqual(history.entries, ["two", "three", "one"])
        history.promote("missing")
        XCTAssertEqual(history.entries, ["two", "three", "one"])
    }

    func testClearRemovesEverything() {
        var history = CaptureHistory()
        history.add("one")
        history.clear()
        XCTAssertTrue(history.isEmpty)
    }

    func testPreviewCollapsesWhitespaceAndClipsLongText() {
        XCTAssertEqual(CaptureHistory.preview("one\n\ntwo   three"), "one two three")
        XCTAssertEqual(CaptureHistory.preview("abcdefghij", limit: 6), "abcde…")
        XCTAssertEqual(CaptureHistory.preview("  short  "), "short")
    }
}
