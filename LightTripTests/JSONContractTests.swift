import XCTest
@testable import LightTrip

final class JSONContractTests: XCTestCase {
    func testBundledJSONDecodes() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-trip.lighttrip", withExtension: "json", subdirectory: "SampleTrips") ?? Bundle.main.url(forResource: "sample-trip.lighttrip", withExtension: "json"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let draft = try TripImportService().parse(source, sourceName: url.lastPathComponent)
        XCTAssertEqual(draft.contractVersion, 1)
        XCTAssertEqual(draft.days.count, 5)
        XCTAssertEqual(draft.itemCount, 6)
        XCTAssertEqual(draft.bookings.count, 6)
        XCTAssertEqual(draft.sourceFormat, .lightTripJSON)
        XCTAssertEqual(draft.rawSource, source)
    }

    func testUnsupportedVersionIsFieldAddressable() throws {
        let source = minimalJSON.replacingOccurrences(of: #""schemaVersion": 1"#, with: #""schemaVersion": 2"#)
        XCTAssertThrowsError(try TripImportService().parse(source)) { error in
            XCTAssertTrue(error.localizedDescription.contains("schemaVersion"))
        }
    }

    func testUnknownAdditiveFieldIsAccepted() throws {
        let source = minimalJSON.replacingOccurrences(of: #""reminders": []"#, with: #""reminders": [], "futureField": true"#)
        let draft = try TripImportService().parse(source)
        XCTAssertEqual(draft.trip.title, "Test Trip")
        XCTAssertTrue(draft.rawSource.contains("futureField"))
    }

    func testEmbeddedContractIsAuthoritativeAndMarkdownIsPreserved() throws {
        let markdown = "# Notes\n\n```light-trip\n\(minimalJSON)\n```\n\nIgnore this prose."
        let draft = try TripImportService().parse(markdown)
        XCTAssertEqual(draft.sourceFormat, .markdown)
        XCTAssertEqual(draft.contractVersion, 1)
        XCTAssertEqual(draft.rawSource, markdown)
    }

    private let minimalJSON = #"""
    {
      "schemaVersion": 1,
      "trip": {
        "id": "7c7d5c44-67c1-4f18-913b-c7bf21cb403a",
        "title": "Test Trip",
        "destination": "Chengdu",
        "startDate": "2026-10-04",
        "endDate": "2026-10-04",
        "timeZone": "Asia/Shanghai",
        "travelerCount": 1
      },
      "days": [],
      "bookings": [],
      "reminders": []
    }
    """#
}
