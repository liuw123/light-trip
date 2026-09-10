import SwiftData
import SwiftUI

struct ActivityEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let item: TimelineItem?
    private let trip: Trip?
    private let preferredDay: TripDay?
    @State private var title: String
    @State private var category: TimelineCategory
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var untimed: Bool
    @State private var origin: String
    @State private var destination: String
    @State private var location: String
    @State private var notes: String
    @State private var buffer: Int
    @State private var requiresConfirmation: Bool
    @State private var relatedBookingID: UUID?

    init(item: TimelineItem? = nil, trip: Trip? = nil, preferredDay: TripDay? = nil) {
        self.item = item; self.trip = trip ?? item?.day?.trip; self.preferredDay = preferredDay ?? item?.day
        let base = item?.startDate ?? preferredDay?.date ?? trip?.startDate ?? .now
        _title = State(initialValue: item?.title ?? "")
        _category = State(initialValue: item?.category ?? .activity)
        _date = State(initialValue: base)
        _start = State(initialValue: item?.startDate ?? base)
        _end = State(initialValue: item?.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: base)!)
        _untimed = State(initialValue: item?.isUntimed ?? false)
        _origin = State(initialValue: item?.origin ?? "")
        _destination = State(initialValue: item?.destination ?? "")
        _location = State(initialValue: item?.locationName ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _buffer = State(initialValue: item?.bufferMinutes ?? 0)
        _requiresConfirmation = State(initialValue: item?.requiresConfirmation ?? false)
        _relatedBookingID = State(initialValue: item?.bookings.first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) { ForEach(TimelineCategory.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Untimed", isOn: $untimed)
                    if !untimed {
                        DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Place") {
                    TextField("Origin", text: $origin)
                    TextField("Destination", text: $destination)
                    TextField("Location", text: $location)
                }
                Section("Operations") {
                    Stepper("Buffer: \(buffer) minutes", value: $buffer, in: 0...720, step: 5)
                    Toggle("Needs confirmation", isOn: $requiresConfirmation)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                if let trip, !trip.bookings.isEmpty {
                    Section("Related booking") {
                        Picker("Booking", selection: $relatedBookingID) {
                            Text("None").tag(UUID?.none)
                            ForEach(trip.bookings) { Text($0.provider).tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (!untimed && end < start)) }
            }
        }
    }

    private func save() {
        let calendar = (trip?.timeZoneIdentifier).map { ContractDate.calendar(timeZoneIdentifier: $0) } ?? .current
        let itemStart = untimed ? nil : calendar.date(bySettingHour: calendar.component(.hour, from: start), minute: calendar.component(.minute, from: start), second: 0, of: date)
        let itemEnd = untimed ? nil : calendar.date(bySettingHour: calendar.component(.hour, from: end), minute: calendar.component(.minute, from: end), second: 0, of: date)
        let value = item ?? TimelineItem(title: title)
        value.title = title; value.category = category; value.startDate = itemStart; value.endDate = itemEnd; value.isUntimed = untimed
        value.origin = origin.nilIfBlank; value.destination = destination.nilIfBlank; value.locationName = location.nilIfBlank
        value.notes = notes.nilIfBlank; value.bufferMinutes = buffer == 0 ? nil : buffer; value.requiresConfirmation = requiresConfirmation
        value.bookings = relatedBookingID.flatMap { id in trip?.bookings.first(where: { $0.id == id }) }.map { [$0] } ?? []
        if item == nil, let trip {
            let day = preferredDay ?? trip.days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) ?? {
                let day = TripDay(date: date, sequence: trip.days.count + 1, title: "Day \(trip.days.count + 1)")
                trip.days.append(day); modelContext.insert(day); return day
            }()
            value.sequence = day.items.count; day.items.append(value); modelContext.insert(value)
        }
        trip?.updatedAt = .now; try? modelContext.save(); dismiss()
    }
}

extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }
