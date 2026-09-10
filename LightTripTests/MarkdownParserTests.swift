import XCTest
@testable import LightTrip

final class MarkdownParserTests: XCTestCase {
    func testCanonicalMarkdownFixture() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "canonical-trip", withExtension: "md", subdirectory: "Fixtures") ?? bundle.url(forResource: "canonical-trip", withExtension: "md"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let draft = try MarkdownTripParser().parse(source, sourceName: url.lastPathComponent)
        XCTAssertEqual(draft.days.count, 5)
        XCTAssertEqual(draft.itemCount, 6)
        XCTAssertEqual(draft.bookings.count, 6)
        XCTAssertEqual(draft.reminders.count, 2)
        XCTAssertEqual(draft.parserVersion, 1)
        XCTAssertTrue(draft.rawSource.contains("Cost"))
        XCTAssertFalse(String(describing: draft.trip).localizedCaseInsensitiveContains("cost"))
    }

    func testStableIDsAcrossRepeatedParsing() throws {
        let source = """
        # Weekend
        > Dates: 2026-10-04 to 2026-10-04
        > Destination: Chengdu
        > Time zone: Asia/Shanghai
        ## Day 1 — 2026-10-04 — Arrival
        | Time | Type | Plan |
        |---|---|---|
        | 09:00–10:00 | Activity | Breakfast |
        """
        let first = try MarkdownTripParser().parse(source, sourceName: nil)
        let second = try MarkdownTripParser().parse(source, sourceName: nil)
        XCTAssertEqual(first.trip.id, second.trip.id)
        XCTAssertEqual(first.days.first?.items.first?.id, second.days.first?.items.first?.id)
    }

    func testCommonChineseHeadingsAndColumns() throws {
        let source = """
        # 川西行程
        > 日期：2026年10月4日 至 10月5日
        > 目的地：成都、黄龙
        > 时区：Asia/Shanghai
        > 人数：2
        ## 10月4日｜抵达成都
        | 时间 | 具体安排 | 交通与取舍 | 费用 |
        |---|---|---|---|
        | 12:30–15:40 | 搭乘航班抵达成都 | 预留90分钟接驳 | 999 |
        ## 10月5日｜游览黄龙
        | 时间 | 具体安排 | 交通与取舍 |
        |---|---|---|
        | 11:20–15:30 | 游览黄龙景区 | 上行索道已预约 |
        """
        let draft = try MarkdownTripParser().parse(source, sourceName: nil)
        XCTAssertEqual(draft.days.count, 2)
        XCTAssertEqual(draft.itemCount, 2)
        XCTAssertEqual(draft.trip.destination, "成都、黄龙")
        XCTAssertEqual(draft.days[1].items[0].category, .activity)
        XCTAssertTrue(draft.rawSource.contains("费用"))
    }
}
