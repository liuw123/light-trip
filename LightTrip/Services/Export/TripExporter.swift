import Foundation

struct TripExporter {
    func data(for trip: Trip) throws -> Data {
        let timeZone = trip.timeZone
        let dayContracts = trip.sortedDays.map { day in
            ContractDay(
                id: day.id,
                date: ContractDate.dayString(day.date, timeZone: timeZone),
                sequence: day.sequence,
                title: day.title,
                summary: day.summary,
                importantNotes: day.importantNotes,
                items: day.sortedItems.map { item in
                    ContractTimelineItem(
                        id: item.id,
                        title: item.title,
                        category: item.category,
                        startTime: ContractDate.timeString(item.startDate, timeZone: timeZone),
                        endTime: ContractDate.timeString(item.endDate, timeZone: timeZone),
                        isUntimed: item.isUntimed,
                        origin: item.origin,
                        destination: item.destination,
                        locationName: item.locationName,
                        meetingPoint: item.meetingPoint,
                        notes: item.notes,
                        bufferMinutes: item.bufferMinutes,
                        latestSafeDeparture: ContractDate.timeString(item.latestSafeDeparture, timeZone: timeZone),
                        officialURL: item.officialURL?.absoluteString,
                        contactPhone: item.contactPhone,
                        requiresConfirmation: item.requiresConfirmation,
                        sequence: item.sequence,
                        bookingIDs: item.bookings.map(\.id)
                    )
                }
            )
        }

        let bookingContracts = trip.bookings.map { booking in
            ContractBooking(
                id: booking.id,
                category: booking.category,
                provider: booking.provider,
                status: booking.status,
                reference: booking.reference,
                startDateTime: booking.startDate.map(Self.rfc3339),
                endDateTime: booking.endDate.map(Self.rfc3339),
                officialURL: booking.officialURL?.absoluteString,
                contactPhone: booking.contactPhone,
                notes: booking.notes,
                details: booking.details,
                timelineItemIDs: booking.timelineItems.map(\.id)
            )
        }
        let reminders = trip.reminders.map { reminder in
            ContractReminder(id: reminder.id, timelineItemID: reminder.timelineItem?.id,
                             offsetMinutes: reminder.offsetMinutes, title: reminder.title,
                             isEnabled: reminder.isEnabled)
        }
        let contract = LightTripContract(
            schemaVersion: LightTripContract.currentVersion,
            trip: ContractTrip(id: trip.id, title: trip.title, destination: trip.destination,
                               startDate: ContractDate.dayString(trip.startDate, timeZone: timeZone),
                               endDate: ContractDate.dayString(trip.endDate, timeZone: timeZone),
                               timeZone: trip.timeZoneIdentifier, travelerCount: trip.travelerCount),
            days: dayContracts, bookings: bookingContracts, reminders: reminders
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(contract)
    }

    private static func rfc3339(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
