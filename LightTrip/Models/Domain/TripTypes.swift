import Foundation
import SwiftUI

enum TimelineCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case transport, activity, accommodation, meal, breakTime, reminder, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .transport: "Transport"
        case .activity: "Activity"
        case .accommodation: "Hotel"
        case .meal: "Meal"
        case .breakTime: "Break"
        case .reminder: "Important"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .transport: "arrow.triangle.swap"
        case .activity: "figure.walk"
        case .accommodation: "bed.double.fill"
        case .meal: "fork.knife"
        case .breakTime: "cup.and.saucer.fill"
        case .reminder: "exclamationmark.circle.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .transport: .blue
        case .activity: .green
        case .accommodation: .indigo
        case .meal, .breakTime: .secondary
        case .reminder: .orange
        case .other: .gray
        }
    }
}

enum BookingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case flight, train, hotel, attraction, groundTransport, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .flight: "Flights"
        case .train: "Trains"
        case .hotel: "Hotels"
        case .attraction: "Attractions"
        case .groundTransport: "Ground transport"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .train: "tram.fill"
        case .hotel: "building.2.fill"
        case .attraction: "ticket.fill"
        case .groundTransport: "car.fill"
        case .other: "bookmark.fill"
        }
    }
}

enum BookingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, needsConfirmation, confirmed, completed, cancelled
    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: "Planned"
        case .needsConfirmation: "Needs confirmation"
        case .confirmed: "Confirmed"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

enum SourceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case lightTripJSON, markdown, plainText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lightTripJSON: "Light Trip JSON"
        case .markdown: "Markdown"
        case .plainText: "Plain text"
        }
    }
}

enum ImportSeverity: String, Codable, Sendable { case warning, error }

struct ImportDiagnostic: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var severity: ImportSeverity
    var path: String
    var message: String
}

struct SourceFragment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var heading: String?
    var content: String
}

struct TripDraft: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var timeZoneIdentifier: String
    var travelerCount: Int
}

struct TripDayDraft: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var sequence: Int
    var title: String
    var summary: String?
    var importantNotes: [String]
    var items: [TimelineItemDraft]
}

struct TimelineItemDraft: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var category: TimelineCategory
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
    var sequence: Int
    var bookingIDs: [UUID]
    var sourceFingerprint: String?
}

struct BookingDraft: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var category: BookingCategory
    var provider: String
    var status: BookingStatus
    var reference: String?
    var startDate: Date?
    var endDate: Date?
    var officialURL: URL?
    var contactPhone: String?
    var notes: String?
    var details: BookingDetails
    var timelineItemIDs: [UUID]
    var sourceFingerprint: String?
}

struct ReminderDraft: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var timelineItemID: UUID?
    var offsetMinutes: Int
    var title: String
    var isEnabled: Bool
}

struct TripImportDraft: Identifiable, Sendable {
    var trip: TripDraft
    var days: [TripDayDraft]
    var bookings: [BookingDraft]
    var reminders: [ReminderDraft]
    var unrecognizedContent: [SourceFragment]
    var diagnostics: [ImportDiagnostic]
    var rawSource: String
    var sourceFormat: SourceFormat
    var contractVersion: Int?
    var parserVersion: Int?
    var sourceName: String?

    var id: UUID { trip.id }
    var itemCount: Int { days.reduce(0) { $0 + $1.items.count } }
    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

enum BookingDetails: Codable, Hashable, Sendable {
    case flight(FlightDetails)
    case train(TrainDetails)
    case hotel(HotelDetails)
    case attraction(AttractionDetails)
    case groundTransport(GroundTransportDetails)
    case other(OtherBookingDetails)

    private enum CodingKeys: String, CodingKey { case type, value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .flight(let value): try container.encode("flight", forKey: .type); try container.encode(value, forKey: .value)
        case .train(let value): try container.encode("train", forKey: .type); try container.encode(value, forKey: .value)
        case .hotel(let value): try container.encode("hotel", forKey: .type); try container.encode(value, forKey: .value)
        case .attraction(let value): try container.encode("attraction", forKey: .type); try container.encode(value, forKey: .value)
        case .groundTransport(let value): try container.encode("groundTransport", forKey: .type); try container.encode(value, forKey: .value)
        case .other(let value): try container.encode("other", forKey: .type); try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "flight": self = .flight(try container.decode(FlightDetails.self, forKey: .value))
        case "train": self = .train(try container.decode(TrainDetails.self, forKey: .value))
        case "hotel": self = .hotel(try container.decode(HotelDetails.self, forKey: .value))
        case "attraction": self = .attraction(try container.decode(AttractionDetails.self, forKey: .value))
        case "groundTransport": self = .groundTransport(try container.decode(GroundTransportDetails.self, forKey: .value))
        case "other": self = .other(try container.decode(OtherBookingDetails.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported booking detail type")
        }
    }

    var summaryRows: [(String, String)] {
        switch self {
        case .flight(let d): return [("Flight", d.flightNumber), ("Route", d.route), ("Terminal", d.terminal ?? "—"), ("Baggage", d.baggageNote ?? "—")]
        case .train(let d): return [("Train", d.trainNumber), ("Route", d.route), ("Seat", [d.seatClass, d.carriage, d.seat].compactMap{$0}.joined(separator: " · "))]
        case .hotel(let d): return [("Property", d.propertyName), ("Address", d.address ?? "—"), ("Room", d.roomInformation ?? "—")]
        case .attraction(let d): return [("Attraction", d.attractionName), ("Product", d.ticketType ?? "—"), ("Entrance", d.entrance ?? "—")]
        case .groundTransport(let d): return [("Route", d.route), ("Pickup", d.pickup ?? "—"), ("Vehicle", d.vehicleNumber ?? "—")]
        case .other(let d): return d.fields.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
    }

    var category: BookingCategory {
        switch self {
        case .flight: .flight
        case .train: .train
        case .hotel: .hotel
        case .attraction: .attraction
        case .groundTransport: .groundTransport
        case .other: .other
        }
    }
}

struct FlightDetails: Codable, Hashable, Sendable { var flightNumber: String; var originAirport: String; var destinationAirport: String; var departureTerminal: String?; var arrivalTerminal: String?; var baggageNote: String?; var route: String { "\(originAirport) → \(destinationAirport)" }; var terminal: String? { [departureTerminal, arrivalTerminal].compactMap{$0}.joined(separator: " → ").nilIfEmpty } }
struct TrainDetails: Codable, Hashable, Sendable { var trainNumber: String; var originStation: String; var destinationStation: String; var seatClass: String?; var carriage: String?; var seat: String?; var route: String { "\(originStation) → \(destinationStation)" } }
struct HotelDetails: Codable, Hashable, Sendable { var propertyName: String; var address: String?; var checkInNote: String?; var checkOutNote: String?; var roomInformation: String? }
struct AttractionDetails: Codable, Hashable, Sendable { var attractionName: String; var ticketType: String?; var entrance: String?; var meetingPoint: String?; var openingWindow: String? }
struct GroundTransportDetails: Codable, Hashable, Sendable { var origin: String?; var destination: String?; var pickup: String?; var dropOff: String?; var driver: String?; var vehicleNumber: String?; var meetingPoint: String?; var route: String { [origin, destination].compactMap{$0}.joined(separator: " → ") } }
struct OtherBookingDetails: Codable, Hashable, Sendable { var fields: [String: String] }

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
