import Foundation
import SwiftData

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var title: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var timeZoneIdentifier: String
    var travelerCount: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TripDay.trip)
    var days: [TripDay] = []
    @Relationship(deleteRule: .cascade, inverse: \Booking.trip)
    var bookings: [Booking] = []
    @Relationship(deleteRule: .cascade, inverse: \SourceDocument.trip)
    var sourceDocument: SourceDocument?
    @Relationship(deleteRule: .cascade, inverse: \ReminderRule.trip)
    var reminders: [ReminderRule] = []

    init(id: UUID = UUID(), title: String, destination: String, startDate: Date, endDate: Date,
         timeZoneIdentifier: String = TimeZone.current.identifier, travelerCount: Int = 1,
         createdAt: Date = .now, updatedAt: Date = .now, archivedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.travelerCount = travelerCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    var sortedDays: [TripDay] { days.sorted { $0.sequence < $1.sequence } }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

@Model
final class TripDay {
    @Attribute(.unique) var id: UUID
    var date: Date
    var sequence: Int
    var title: String
    var summary: String?
    var importantNotes: [String]
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \TimelineItem.day)
    var items: [TimelineItem] = []

    init(id: UUID = UUID(), date: Date, sequence: Int, title: String,
         summary: String? = nil, importantNotes: [String] = []) {
        self.id = id
        self.date = date
        self.sequence = sequence
        self.title = title
        self.summary = summary
        self.importantNotes = importantNotes
    }

    var sortedItems: [TimelineItem] {
        items.sorted {
            switch ($0.startDate, $1.startDate) {
            case let (lhs?, rhs?) where lhs != rhs: lhs < rhs
            default: $0.sequence < $1.sequence
            }
        }
    }
}

@Model
final class TimelineItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var categoryRawValue: String
    var startDate: Date?
    var endDate: Date?
    var isUntimed: Bool
    var origin: String?
    var destination: String?
    var locationName: String?
    var meetingPoint: String?
    var notes: String?
    var bufferMinutes: Int?
    var latestSafeDeparture: Date?
    var officialURL: URL?
    var contactPhone: String?
    var requiresConfirmation: Bool
    var isManuallyCompleted: Bool
    var sourceFingerprint: String?
    var sequence: Int
    var day: TripDay?
    var bookings: [Booking] = []

    @Relationship(deleteRule: .cascade, inverse: \ReminderRule.timelineItem)
    var reminders: [ReminderRule] = []

    init(id: UUID = UUID(), title: String, category: TimelineCategory = .other,
         startDate: Date? = nil, endDate: Date? = nil, isUntimed: Bool = false,
         origin: String? = nil, destination: String? = nil, locationName: String? = nil,
         meetingPoint: String? = nil, notes: String? = nil, bufferMinutes: Int? = nil,
         latestSafeDeparture: Date? = nil, officialURL: URL? = nil, contactPhone: String? = nil,
         requiresConfirmation: Bool = false, isManuallyCompleted: Bool = false,
         sourceFingerprint: String? = nil, sequence: Int = 0) {
        self.id = id
        self.title = title
        self.categoryRawValue = category.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.isUntimed = isUntimed
        self.origin = origin
        self.destination = destination
        self.locationName = locationName
        self.meetingPoint = meetingPoint
        self.notes = notes
        self.bufferMinutes = bufferMinutes
        self.latestSafeDeparture = latestSafeDeparture
        self.officialURL = officialURL
        self.contactPhone = contactPhone
        self.requiresConfirmation = requiresConfirmation
        self.isManuallyCompleted = isManuallyCompleted
        self.sourceFingerprint = sourceFingerprint
        self.sequence = sequence
    }

    var category: TimelineCategory {
        get { TimelineCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}

@Model
final class Booking {
    @Attribute(.unique) var id: UUID
    var categoryRawValue: String
    var provider: String
    var statusRawValue: String
    var reference: String?
    var startDate: Date?
    var endDate: Date?
    var officialURL: URL?
    var contactPhone: String?
    var notes: String?
    var detailsData: Data
    var sourceFingerprint: String?
    var trip: Trip?

    @Relationship(inverse: \TimelineItem.bookings)
    var timelineItems: [TimelineItem] = []

    init(id: UUID = UUID(), category: BookingCategory, provider: String,
         status: BookingStatus = .planned, reference: String? = nil,
         startDate: Date? = nil, endDate: Date? = nil, officialURL: URL? = nil,
         contactPhone: String? = nil, notes: String? = nil,
         details: BookingDetails = .other(.init(fields: [:])), sourceFingerprint: String? = nil) {
        self.id = id
        self.categoryRawValue = category.rawValue
        self.provider = provider
        self.statusRawValue = status.rawValue
        self.reference = reference
        self.startDate = startDate
        self.endDate = endDate
        self.officialURL = officialURL
        self.contactPhone = contactPhone
        self.notes = notes
        self.detailsData = (try? JSONEncoder().encode(details)) ?? Data()
        self.sourceFingerprint = sourceFingerprint
    }

    var category: BookingCategory {
        get { BookingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
    var status: BookingStatus {
        get { BookingStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }
    var details: BookingDetails {
        get { (try? JSONDecoder().decode(BookingDetails.self, from: detailsData)) ?? .other(.init(fields: [:])) }
        set { detailsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class SourceDocument {
    @Attribute(.unique) var id: UUID
    var rawContent: String
    var sourceFormatRawValue: String
    var importedAt: Date
    var contractVersion: Int?
    var parserVersion: Int?
    var sourceName: String?
    var contentHash: String
    var trip: Trip?

    init(id: UUID = UUID(), rawContent: String, sourceFormat: SourceFormat,
         importedAt: Date = .now, contractVersion: Int? = nil, parserVersion: Int? = nil,
         sourceName: String? = nil, contentHash: String) {
        self.id = id
        self.rawContent = rawContent
        self.sourceFormatRawValue = sourceFormat.rawValue
        self.importedAt = importedAt
        self.contractVersion = contractVersion
        self.parserVersion = parserVersion
        self.sourceName = sourceName
        self.contentHash = contentHash
    }

    var sourceFormat: SourceFormat { SourceFormat(rawValue: sourceFormatRawValue) ?? .plainText }
}

@Model
final class ReminderRule {
    @Attribute(.unique) var id: UUID
    var offsetMinutes: Int
    var title: String
    var isEnabled: Bool
    var isCompleted: Bool
    var notificationIdentifier: String?
    var timelineItem: TimelineItem?
    var trip: Trip?

    init(id: UUID = UUID(), offsetMinutes: Int, title: String, isEnabled: Bool = true,
         isCompleted: Bool = false, notificationIdentifier: String? = nil) {
        self.id = id
        self.offsetMinutes = offsetMinutes
        self.title = title
        self.isEnabled = isEnabled
        self.isCompleted = isCompleted
        self.notificationIdentifier = notificationIdentifier
    }
}
