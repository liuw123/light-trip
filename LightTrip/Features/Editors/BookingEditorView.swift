import SwiftData
import SwiftUI

struct BookingEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let booking: Booking?
    private let trip: Trip?
    @State private var category: BookingCategory
    @State private var provider: String
    @State private var status: BookingStatus
    @State private var reference: String
    @State private var service: String
    @State private var origin: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var hasStart: Bool
    @State private var notes: String
    @State private var linkedItemIDs: Set<UUID>

    init(booking: Booking? = nil, trip: Trip? = nil) {
        self.booking = booking; self.trip = trip ?? booking?.trip
        let rows = Dictionary(uniqueKeysWithValues: (booking?.details.summaryRows ?? []).map { ($0.0, $0.1) })
        _category = State(initialValue: booking?.category ?? .flight)
        _provider = State(initialValue: booking?.provider ?? "")
        _status = State(initialValue: booking?.status ?? .planned)
        _reference = State(initialValue: booking?.reference ?? "")
        _service = State(initialValue: rows["Flight"] ?? rows["Train"] ?? rows["Property"] ?? rows["Attraction"] ?? "")
        let route = rows["Route"]?.components(separatedBy: " → ") ?? []
        _origin = State(initialValue: route.first ?? "")
        _destination = State(initialValue: route.dropFirst().first ?? "")
        _startDate = State(initialValue: booking?.startDate ?? trip?.startDate ?? .now)
        _hasStart = State(initialValue: booking?.startDate != nil)
        _notes = State(initialValue: booking?.notes ?? "")
        _linkedItemIDs = State(initialValue: Set(booking?.timelineItems.map(\.id) ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $category) { ForEach(BookingCategory.allCases) { Text($0.label).tag($0) } }
                TextField("Provider", text: $provider)
                TextField(serviceLabel, text: $service)
                Picker("Status", selection: $status) { ForEach(BookingStatus.allCases) { Text($0.label).tag($0) } }
                TextField("Reservation reference", text: $reference).textInputAutocapitalization(.characters)
                Section("Route or location") { TextField("From", text: $origin); TextField("To / location", text: $destination) }
                Section("Timing") { Toggle("Has date and time", isOn: $hasStart); if hasStart { DatePicker("Starts", selection: $startDate) } }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8) }
                if let trip, !trip.days.flatMap(\.items).isEmpty {
                    Section("Related timeline items") {
                        ForEach(trip.sortedDays.flatMap(\.sortedItems)) { item in
                            Toggle(item.title, isOn: Binding(get: { linkedItemIDs.contains(item.id) }, set: { linked in
                                if linked { linkedItemIDs.insert(item.id) } else { linkedItemIDs.remove(item.id) }
                            }))
                        }
                    }
                }
            }
            .navigationTitle(booking == nil ? "New Booking" : "Edit Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(provider.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private var serviceLabel: String { switch category { case .flight: "Flight number"; case .train: "Train number"; case .hotel: "Property name"; case .attraction: "Attraction"; case .groundTransport: "Service"; case .other: "Name" } }
    private var details: BookingDetails {
        switch category {
        case .flight: .flight(.init(flightNumber: service, originAirport: origin, destinationAirport: destination, departureTerminal: nil, arrivalTerminal: nil, baggageNote: nil))
        case .train: .train(.init(trainNumber: service, originStation: origin, destinationStation: destination, seatClass: nil, carriage: nil, seat: nil))
        case .hotel: .hotel(.init(propertyName: service, address: destination.nilIfBlank, checkInNote: nil, checkOutNote: nil, roomInformation: nil))
        case .attraction: .attraction(.init(attractionName: service, ticketType: nil, entrance: destination.nilIfBlank, meetingPoint: nil, openingWindow: nil))
        case .groundTransport: .groundTransport(.init(origin: origin.nilIfBlank, destination: destination.nilIfBlank, pickup: nil, dropOff: nil, driver: nil, vehicleNumber: nil, meetingPoint: nil))
        case .other: .other(.init(fields: ["Name": service, "Location": destination]))
        }
    }
    private func save() {
        let value = booking ?? Booking(category: category, provider: provider)
        value.category = category; value.provider = provider; value.status = status; value.reference = reference.nilIfBlank
        value.startDate = hasStart ? startDate : nil; value.notes = notes.nilIfBlank; value.details = details
        value.timelineItems = trip?.days.flatMap(\.items).filter { linkedItemIDs.contains($0.id) } ?? []
        if booking == nil, let trip { trip.bookings.append(value); modelContext.insert(value) }
        trip?.updatedAt = .now; try? modelContext.save(); dismiss()
    }
}
