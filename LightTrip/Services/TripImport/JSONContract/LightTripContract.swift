import Foundation

struct LightTripContract: Codable, Sendable {
    static let currentVersion = 1
    var schemaVersion: Int
    var trip: ContractTrip
    var days: [ContractDay]
    var bookings: [ContractBooking]
    var reminders: [ContractReminder]
}

struct ContractTrip: Codable, Sendable {
    var id: UUID
    var title: String
    var destination: String
    var startDate: String
    var endDate: String
    var timeZone: String
    var travelerCount: Int?
}

struct ContractDay: Codable, Sendable {
    var id: UUID
    var date: String
    var sequence: Int
    var title: String
    var summary: String?
    var importantNotes: [String]?
    var items: [ContractTimelineItem]
}

struct ContractTimelineItem: Codable, Sendable {
    var id: UUID
    var title: String
    var category: TimelineCategory
    var startTime: String?
    var endTime: String?
    var isUntimed: Bool?
    var origin: String?
    var destination: String?
    var locationName: String?
    var meetingPoint: String?
    var notes: String?
    var bufferMinutes: Int?
    var latestSafeDeparture: String?
    var officialURL: String?
    var contactPhone: String?
    var requiresConfirmation: Bool?
    var sequence: Int
    var bookingIDs: [UUID]?
}

struct ContractBooking: Codable, Sendable {
    var id: UUID
    var category: BookingCategory
    var provider: String
    var status: BookingStatus
    var reference: String?
    var startDateTime: String?
    var endDateTime: String?
    var officialURL: String?
    var contactPhone: String?
    var notes: String?
    var details: BookingDetails
    var timelineItemIDs: [UUID]?
}

struct ContractReminder: Codable, Sendable {
    var id: UUID
    var timelineItemID: UUID?
    var offsetMinutes: Int
    var title: String
    var isEnabled: Bool
}

enum ContractError: LocalizedError {
    case diagnostics([ImportDiagnostic])
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .diagnostics(let diagnostics):
            diagnostics.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
        case .decode(let message): message
        }
    }
}

struct LightTripContractDecoder: Sendable {
    func decode(_ source: String, sourceName: String? = nil, preservedSource: String? = nil,
                sourceFormat: SourceFormat = .lightTripJSON) throws -> TripImportDraft {
        let data = Data(source.utf8)
        let contract: LightTripContract
        do {
            contract = try JSONDecoder().decode(LightTripContract.self, from: data)
        } catch {
            throw ContractError.decode(Self.describe(error))
        }

        var diagnostics = validate(contract)
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            throw ContractError.diagnostics(diagnostics)
        }

        let calendar = ContractDate.calendar(timeZoneIdentifier: contract.trip.timeZone)
        guard let startDate = ContractDate.day(contract.trip.startDate, calendar: calendar),
              let endDate = ContractDate.day(contract.trip.endDate, calendar: calendar) else {
            throw ContractError.diagnostics([
                .init(severity: .error, path: "trip", message: "Trip dates must use YYYY-MM-DD.")
            ])
        }

        let bookingIDs = Set(contract.bookings.map(\.id))
        let timelineIDs = Set(contract.days.flatMap(\.items).map(\.id))
        let bookingDrafts = contract.bookings.map { booking in
            BookingDraft(
                id: booking.id,
                category: booking.category,
                provider: booking.provider,
                status: booking.status,
                reference: booking.reference,
                startDate: ContractDate.dateTime(booking.startDateTime, calendar: calendar),
                endDate: ContractDate.dateTime(booking.endDateTime, calendar: calendar),
                officialURL: booking.officialURL.flatMap(URL.init(string:)),
                contactPhone: booking.contactPhone,
                notes: booking.notes,
                details: booking.details,
                timelineItemIDs: (booking.timelineItemIDs ?? []).filter { timelineIDs.contains($0) },
                sourceFingerprint: nil
            )
        }

        let dayDrafts = contract.days.map { day in
            let dayDate = ContractDate.day(day.date, calendar: calendar) ?? startDate
            let itemDrafts = day.items.map { item in
                TimelineItemDraft(
                    id: item.id,
                    title: item.title,
                    category: item.category,
                    startDate: ContractDate.localTime(item.startTime, on: dayDate, calendar: calendar),
                    endDate: ContractDate.localTime(item.endTime, on: dayDate, calendar: calendar),
                    isUntimed: item.isUntimed ?? item.startTime == nil,
                    origin: item.origin,
                    destination: item.destination,
                    locationName: item.locationName,
                    meetingPoint: item.meetingPoint,
                    notes: item.notes,
                    bufferMinutes: item.bufferMinutes,
                    latestSafeDeparture: ContractDate.localTime(item.latestSafeDeparture, on: dayDate, calendar: calendar),
                    officialURL: item.officialURL.flatMap(URL.init(string:)),
                    contactPhone: item.contactPhone,
                    requiresConfirmation: item.requiresConfirmation ?? false,
                    sequence: item.sequence,
                    bookingIDs: (item.bookingIDs ?? []).filter { bookingIDs.contains($0) },
                    sourceFingerprint: nil
                )
            }
            return TripDayDraft(
                id: day.id,
                date: dayDate,
                sequence: day.sequence,
                title: day.title,
                summary: day.summary,
                importantNotes: day.importantNotes ?? [],
                items: itemDrafts
            )
        }

        diagnostics.append(contentsOf: relationshipWarnings(contract))
        return TripImportDraft(
            trip: TripDraft(id: contract.trip.id, title: contract.trip.title,
                            destination: contract.trip.destination, startDate: startDate,
                            endDate: endDate, timeZoneIdentifier: contract.trip.timeZone,
                            travelerCount: contract.trip.travelerCount ?? 1),
            days: dayDrafts,
            bookings: bookingDrafts,
            reminders: contract.reminders.map {
                .init(id: $0.id, timelineItemID: $0.timelineItemID,
                      offsetMinutes: $0.offsetMinutes, title: $0.title, isEnabled: $0.isEnabled)
            },
            unrecognizedContent: [], diagnostics: diagnostics,
            rawSource: preservedSource ?? source, sourceFormat: sourceFormat,
            contractVersion: contract.schemaVersion, parserVersion: nil, sourceName: sourceName
        )
    }

    private func validate(_ contract: LightTripContract) -> [ImportDiagnostic] {
        var result: [ImportDiagnostic] = []
        func error(_ path: String, _ message: String) {
            result.append(.init(severity: .error, path: path, message: message))
        }
        if contract.schemaVersion != LightTripContract.currentVersion {
            error("schemaVersion", "Supported version is \(LightTripContract.currentVersion).")
        }
        if contract.trip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error("trip.title", "Title is required.") }
        if contract.trip.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error("trip.destination", "Destination is required.") }
        guard TimeZone(identifier: contract.trip.timeZone) != nil else {
            error("trip.timeZone", "Use a valid IANA timezone, for example Asia/Shanghai.")
            return result
        }
        let calendar = ContractDate.calendar(timeZoneIdentifier: contract.trip.timeZone)
        guard let tripStart = ContractDate.day(contract.trip.startDate, calendar: calendar),
              let tripEnd = ContractDate.day(contract.trip.endDate, calendar: calendar) else {
            error("trip.startDate", "Dates must use YYYY-MM-DD.")
            return result
        }
        if tripEnd < tripStart { error("trip.endDate", "End date cannot be before start date.") }
        if (contract.trip.travelerCount ?? 1) < 1 { error("trip.travelerCount", "Traveler count must be at least 1.") }

        var allIDs = Set<UUID>()
        func requireUnique(_ id: UUID, path: String) {
            if !allIDs.insert(id).inserted { error(path, "Entity identifiers must be unique.") }
        }
        requireUnique(contract.trip.id, path: "trip.id")
        for (dayIndex, day) in contract.days.enumerated() {
            let dayPath = "days[\(dayIndex)]"
            requireUnique(day.id, path: dayPath + ".id")
            guard let date = ContractDate.day(day.date, calendar: calendar) else {
                error(dayPath + ".date", "Date must use YYYY-MM-DD.")
                continue
            }
            if date < tripStart || date > tripEnd { error(dayPath + ".date", "Day must fall inside the trip range.") }
            for (itemIndex, item) in day.items.enumerated() {
                let itemPath = dayPath + ".items[\(itemIndex)]"
                requireUnique(item.id, path: itemPath + ".id")
                if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error(itemPath + ".title", "Title is required.") }
                if let time = item.startTime, ContractDate.localTime(time, on: date, calendar: calendar) == nil { error(itemPath + ".startTime", "Time must use HH:mm.") }
                if let time = item.endTime, ContractDate.localTime(time, on: date, calendar: calendar) == nil { error(itemPath + ".endTime", "Time must use HH:mm.") }
                if let start = ContractDate.localTime(item.startTime, on: date, calendar: calendar),
                   let end = ContractDate.localTime(item.endTime, on: date, calendar: calendar), end < start {
                    error(itemPath + ".endTime", "End time cannot be before start time.")
                }
                if let value = item.bufferMinutes, value < 0 { error(itemPath + ".bufferMinutes", "Buffer cannot be negative.") }
                if let value = item.officialURL, URL(string: value)?.scheme == nil { error(itemPath + ".officialURL", "URL must include a scheme.") }
            }
        }
        for (index, booking) in contract.bookings.enumerated() {
            let path = "bookings[\(index)]"
            requireUnique(booking.id, path: path + ".id")
            if booking.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error(path + ".provider", "Provider is required.") }
            if booking.details.category != booking.category { error(path + ".details.type", "Detail type must match booking category.") }
            if ContractDate.dateTimeInvalid(booking.startDateTime, calendar: calendar) { error(path + ".startDateTime", "Use RFC 3339 or YYYY-MM-DD.") }
            if ContractDate.dateTimeInvalid(booking.endDateTime, calendar: calendar) { error(path + ".endDateTime", "Use RFC 3339 or YYYY-MM-DD.") }
        }
        for (index, reminder) in contract.reminders.enumerated() {
            requireUnique(reminder.id, path: "reminders[\(index)].id")
            if reminder.offsetMinutes < 0 { error("reminders[\(index)].offsetMinutes", "Offset cannot be negative.") }
            if let itemID = reminder.timelineItemID,
               !contract.days.flatMap(\.items).contains(where: { $0.id == itemID }) {
                error("reminders[\(index)].timelineItemID", "Referenced timeline item does not exist.")
            }
        }
        return result
    }

    private func relationshipWarnings(_ contract: LightTripContract) -> [ImportDiagnostic] {
        let itemIDs = Set(contract.days.flatMap(\.items).map(\.id))
        let bookingIDs = Set(contract.bookings.map(\.id))
        var result: [ImportDiagnostic] = []
        for (dayIndex, day) in contract.days.enumerated() {
            for (itemIndex, item) in day.items.enumerated() where (item.bookingIDs ?? []).contains(where: { !bookingIDs.contains($0) }) {
                result.append(.init(severity: .warning, path: "days[\(dayIndex)].items[\(itemIndex)].bookingIDs", message: "Unknown booking link was ignored."))
            }
        }
        for (index, booking) in contract.bookings.enumerated() where (booking.timelineItemIDs ?? []).contains(where: { !itemIDs.contains($0) }) {
            result.append(.init(severity: .warning, path: "bookings[\(index)].timelineItemIDs", message: "Unknown timeline link was ignored."))
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, let context): return "\(path(context.codingPath, key)): required field is missing."
        case .typeMismatch(_, let context): return "\(path(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(_, let context): return "\(path(context.codingPath)): required value is null."
        case .dataCorrupted(let context): return "\(path(context.codingPath)): \(context.debugDescription)"
        @unknown default: return decoding.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey], _ extra: CodingKey? = nil) -> String {
        (codingPath + (extra.map { [$0] } ?? [])).map { key in
            if let index = key.intValue { return "[\(index)]" }
            return key.stringValue
        }.reduce("") { partial, component in
            component.hasPrefix("[") ? partial + component : partial + (partial.isEmpty ? "" : ".") + component
        }
    }
}

enum ContractDate {
    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    static func day(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, value.count == 10 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func localTime(_ value: String?, on date: Date, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    static func dateTime(_ value: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let result = formatter.date(from: value) { return result }
        return day(value, calendar: calendar)
    }

    static func dateTimeInvalid(_ value: String?, calendar: Calendar) -> Bool {
        value != nil && dateTime(value, calendar: calendar) == nil
    }

    static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timeString(_ date: Date?, timeZone: TimeZone) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
