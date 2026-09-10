import CryptoKit
import Foundation
import SwiftData

protocol TripImportParser: Sendable {
    func parse(_ source: String, sourceName: String?) throws -> TripImportDraft
}

enum ImportFormatOverride: String, CaseIterable, Identifiable {
    case automatic, json, markdown
    var id: String { rawValue }
}

enum ImportServiceError: LocalizedError {
    case empty
    case unsupported
    case embeddedBlockMissingEnd

    var errorDescription: String? {
        switch self {
        case .empty: "Paste or select a trip document first."
        case .unsupported: "The text is neither valid Light Trip JSON nor recognizable Markdown."
        case .embeddedBlockMissingEnd: "The embedded light-trip block is not closed."
        }
    }
}

struct TripImportService {
    private let jsonDecoder = LightTripContractDecoder()
    private let markdownParser = MarkdownTripParser()

    func parse(_ rawSource: String, sourceName: String? = nil,
               override: ImportFormatOverride = .automatic) throws -> TripImportDraft {
        let source = rawSource.removingBOM.normalizingLineEndings
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportServiceError.empty
        }

        if override != .markdown, let embedded = try embeddedContract(in: source) {
            return try jsonDecoder.decode(embedded, sourceName: sourceName,
                                          preservedSource: rawSource, sourceFormat: .markdown)
        }
        if override == .json || (override == .automatic && source.firstNonWhitespace == "{") {
            return try jsonDecoder.decode(source, sourceName: sourceName, preservedSource: rawSource)
        }
        if override == .markdown || MarkdownTripParser.looksLikeMarkdown(source) {
            return try markdownParser.parse(rawSource, sourceName: sourceName)
        }
        throw ImportServiceError.unsupported
    }

    private func embeddedContract(in source: String) throws -> String? {
        guard let opener = source.range(of: "```light-trip") else { return nil }
        let remainder = source[opener.upperBound...]
        guard let closer = remainder.range(of: "```") else { throw ImportServiceError.embeddedBlockMissingEnd }
        return String(remainder[..<closer.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct TripImportRepository {
    let modelContext: ModelContext

    func create(from draft: TripImportDraft) throws -> Trip {
        guard !draft.hasErrors else { throw ContractError.diagnostics(draft.diagnostics) }
        let trip = Trip(id: draft.trip.id, title: draft.trip.title, destination: draft.trip.destination,
                        startDate: draft.trip.startDate, endDate: draft.trip.endDate,
                        timeZoneIdentifier: draft.trip.timeZoneIdentifier,
                        travelerCount: draft.trip.travelerCount)
        modelContext.insert(trip)
        populate(trip, from: draft)
        try modelContext.save()
        return trip
    }

    func replace(_ trip: Trip, with draft: TripImportDraft) throws -> Trip {
        guard !draft.hasErrors else { throw ContractError.diagnostics(draft.diagnostics) }
        NotificationScheduler.shared.removeAll(for: trip)
        trip.days.forEach { modelContext.delete($0) }
        trip.bookings.forEach { modelContext.delete($0) }
        trip.reminders.forEach { modelContext.delete($0) }
        if let source = trip.sourceDocument { modelContext.delete(source) }
        trip.days.removeAll(); trip.bookings.removeAll(); trip.reminders.removeAll(); trip.sourceDocument = nil
        trip.title = draft.trip.title
        trip.destination = draft.trip.destination
        trip.startDate = draft.trip.startDate
        trip.endDate = draft.trip.endDate
        trip.timeZoneIdentifier = draft.trip.timeZoneIdentifier
        trip.travelerCount = draft.trip.travelerCount
        trip.updatedAt = .now
        populate(trip, from: draft)
        do {
            try modelContext.save()
            return trip
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func populate(_ trip: Trip, from draft: TripImportDraft) {

        var itemByID: [UUID: TimelineItem] = [:]
        for dayDraft in draft.days {
            let day = TripDay(id: dayDraft.id, date: dayDraft.date, sequence: dayDraft.sequence,
                              title: dayDraft.title, summary: dayDraft.summary,
                              importantNotes: dayDraft.importantNotes)
            trip.days.append(day)
            modelContext.insert(day)
            for itemDraft in dayDraft.items {
                let item = TimelineItem(id: itemDraft.id, title: itemDraft.title,
                    category: itemDraft.category, startDate: itemDraft.startDate,
                    endDate: itemDraft.endDate, isUntimed: itemDraft.isUntimed,
                    origin: itemDraft.origin, destination: itemDraft.destination,
                    locationName: itemDraft.locationName, meetingPoint: itemDraft.meetingPoint,
                    notes: itemDraft.notes, bufferMinutes: itemDraft.bufferMinutes,
                    latestSafeDeparture: itemDraft.latestSafeDeparture,
                    officialURL: itemDraft.officialURL, contactPhone: itemDraft.contactPhone,
                    requiresConfirmation: itemDraft.requiresConfirmation,
                    sourceFingerprint: itemDraft.sourceFingerprint, sequence: itemDraft.sequence)
                day.items.append(item)
                modelContext.insert(item)
                itemByID[item.id] = item
            }
        }

        var bookingByID: [UUID: Booking] = [:]
        for bookingDraft in draft.bookings {
            let booking = Booking(id: bookingDraft.id, category: bookingDraft.category,
                                  provider: bookingDraft.provider, status: bookingDraft.status,
                                  reference: bookingDraft.reference, startDate: bookingDraft.startDate,
                                  endDate: bookingDraft.endDate, officialURL: bookingDraft.officialURL,
                                  contactPhone: bookingDraft.contactPhone, notes: bookingDraft.notes,
                                  details: bookingDraft.details, sourceFingerprint: bookingDraft.sourceFingerprint)
            trip.bookings.append(booking)
            modelContext.insert(booking)
            bookingByID[booking.id] = booking
            for itemID in bookingDraft.timelineItemIDs {
                if let item = itemByID[itemID], !booking.timelineItems.contains(where: { $0.id == itemID }) {
                    booking.timelineItems.append(item)
                }
            }
        }
        for dayDraft in draft.days {
            for itemDraft in dayDraft.items {
                guard let item = itemByID[itemDraft.id] else { continue }
                for bookingID in itemDraft.bookingIDs {
                    if let booking = bookingByID[bookingID], !item.bookings.contains(where: { $0.id == bookingID }) {
                        item.bookings.append(booking)
                    }
                }
            }
        }
        for reminderDraft in draft.reminders {
            let reminder = ReminderRule(id: reminderDraft.id, offsetMinutes: reminderDraft.offsetMinutes,
                                        title: reminderDraft.title, isEnabled: reminderDraft.isEnabled)
            trip.reminders.append(reminder)
            if let itemID = reminderDraft.timelineItemID, let item = itemByID[itemID] {
                item.reminders.append(reminder)
            }
            modelContext.insert(reminder)
        }

        let sourceDocument = SourceDocument(
            rawContent: draft.rawSource, sourceFormat: draft.sourceFormat,
            contractVersion: draft.contractVersion, parserVersion: draft.parserVersion,
            sourceName: draft.sourceName, contentHash: Self.hash(draft.rawSource)
        )
        trip.sourceDocument = sourceDocument
        modelContext.insert(sourceDocument)
    }

    private static func hash(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var removingBOM: String { first == "\u{FEFF}" ? String(dropFirst()) : self }
    var normalizingLineEndings: String { replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
    var firstNonWhitespace: Character? { first { !$0.isWhitespace } }
}
