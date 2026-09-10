import SwiftData
import XCTest
@testable import LightTrip

@MainActor
final class PersistenceTests: XCTestCase {
    func testImportIsPersistedWithRelationshipsAndSource() throws {
        let schema = Schema([Trip.self, TripDay.self, TimelineItem.self, Booking.self, SourceDocument.self, ReminderRule.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let draft = try LightTripContractDecoder().decode(minimalJSON)
        let trip = try TripImportRepository(modelContext: container.mainContext).create(from: draft)
        XCTAssertEqual(trip.days.count, 1)
        XCTAssertEqual(trip.days.first?.items.count, 1)
        XCTAssertEqual(trip.bookings.count, 1)
        XCTAssertEqual(trip.days.first?.items.first?.bookings.first?.id, trip.bookings.first?.id)
        XCTAssertEqual(trip.sourceDocument?.rawContent, minimalJSON)
    }

    func testNextItemUsesTimelineDates() throws {
        let trip = Trip(title: "Test", destination: "Test", startDate: .now, endDate: .now)
        let day = TripDay(date: .now, sequence: 1, title: "Today")
        let later = TimelineItem(title: "Later", startDate: Date(timeIntervalSince1970: 200), endDate: Date(timeIntervalSince1970: 300))
        let earlier = TimelineItem(title: "Earlier", startDate: Date(timeIntervalSince1970: 100), endDate: Date(timeIntervalSince1970: 150))
        day.items = [later, earlier]; trip.days = [day]
        XCTAssertEqual(NextItemService().nextItem(in: trip, now: Date(timeIntervalSince1970: 175))?.title, "Later")
    }

    private let minimalJSON = #"""
    {
      "schemaVersion": 1,
      "trip": {"id":"7c7d5c44-67c1-4f18-913b-c7bf21cb403a","title":"Test","destination":"Chengdu","startDate":"2026-10-04","endDate":"2026-10-04","timeZone":"Asia/Shanghai"},
      "days": [{"id":"10000000-0000-4000-8000-000000000001","date":"2026-10-04","sequence":1,"title":"Arrival","items":[{"id":"20000000-0000-4000-8000-000000000001","title":"Train","category":"transport","startTime":"09:00","endTime":"10:00","sequence":1,"bookingIDs":["30000000-0000-4000-8000-000000000001"]}]}],
      "bookings": [{"id":"30000000-0000-4000-8000-000000000001","category":"train","provider":"China Railway","status":"confirmed","details":{"type":"train","value":{"trainNumber":"C0001","originStation":"A","destinationStation":"B"}},"timelineItemIDs":["20000000-0000-4000-8000-000000000001"]}],
      "reminders": []
    }
    """#
}
