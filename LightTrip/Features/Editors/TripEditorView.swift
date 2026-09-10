import SwiftData
import SwiftUI

struct TripEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let trip: Trip?
    @State private var title: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var timeZone: String
    @State private var travelers: Int

    init(trip: Trip? = nil) {
        self.trip = trip
        _title = State(initialValue: trip?.title ?? "")
        _destination = State(initialValue: trip?.destination ?? "")
        _startDate = State(initialValue: trip?.startDate ?? .now)
        _endDate = State(initialValue: trip?.endDate ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        _timeZone = State(initialValue: trip?.timeZoneIdentifier ?? TimeZone.current.identifier)
        _travelers = State(initialValue: trip?.travelerCount ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Trip title", text: $title)
                TextField("Destination", text: $destination)
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                TextField("IANA time zone", text: $timeZone)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper("Travelers: \(travelers)", value: $travelers, in: 1...99)
            }
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
            }
        }
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !destination.trimmingCharacters(in: .whitespaces).isEmpty && TimeZone(identifier: timeZone) != nil && endDate >= startDate }
    private func save() {
        if let trip {
            trip.title = title; trip.destination = destination; trip.startDate = startDate; trip.endDate = endDate
            trip.timeZoneIdentifier = timeZone; trip.travelerCount = travelers; trip.updatedAt = .now
        } else {
            let value = Trip(title: title, destination: destination, startDate: startDate, endDate: endDate,
                             timeZoneIdentifier: timeZone, travelerCount: travelers)
            modelContext.insert(value)
        }
        try? modelContext.save(); dismiss()
    }
}
