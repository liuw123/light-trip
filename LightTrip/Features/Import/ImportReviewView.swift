import SwiftData
import SwiftUI

struct ImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let draft: TripImportDraft
    let targetTrip: Trip?
    let completion: () -> Void
    @State private var excludedItems: Set<UUID> = []
    @State private var excludedBookings: Set<UUID> = []
    @State private var confirmingUpdate = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Trip", value: draft.trip.title)
                    LabeledContent("Dates", value: TripFormatters.range(draft.trip.startDate, draft.trip.endDate, timeZone: TimeZone(identifier: draft.trip.timeZoneIdentifier) ?? .current))
                    LabeledContent("Source", value: draft.sourceFormat.label)
                    LabeledContent("Days", value: "\(draft.days.count)")
                    LabeledContent("Timeline items", value: "\(draft.itemCount - excludedItems.count)")
                    LabeledContent("Bookings", value: "\(draft.bookings.count - excludedBookings.count)")
                }
                if let targetTrip {
                    Section("Update preview") {
                        LabeledContent("Add", value: "\(updateDiff.added) records")
                        LabeledContent("Modify", value: "\(updateDiff.modified) records")
                        LabeledContent("Preserve", value: "\(updateDiff.preserved) records")
                        LabeledContent("Remove", value: "\(updateDiff.removed) records")
                        Text("The current trip remains unchanged until you confirm the replacement.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !draft.diagnostics.isEmpty {
                    Section("Diagnostics") {
                        ForEach(draft.diagnostics) { diagnostic in
                            Label { VStack(alignment: .leading) { Text(diagnostic.path).font(.caption.monospaced()); Text(diagnostic.message) } }
                            icon: { Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").foregroundStyle(diagnostic.severity == .error ? .red : .orange) }
                        }
                    }
                }
                ForEach(draft.days) { day in
                    Section("Day \(day.sequence) · \(day.title)") {
                        ForEach(day.items) { item in
                            Toggle(isOn: Binding(get: { !excludedItems.contains(item.id) }, set: { include in if include { excludedItems.remove(item.id) } else { excludedItems.insert(item.id) } })) {
                                VStack(alignment: .leading) { Text(item.title); if let start = item.startDate { Text(TripFormatters.timeString(start, timeZone: TimeZone(identifier: draft.trip.timeZoneIdentifier) ?? .current)).font(.caption).foregroundStyle(.secondary) } }
                            }
                        }
                    }
                }
                if !draft.bookings.isEmpty {
                    Section("Bookings") {
                        ForEach(draft.bookings) { booking in
                            Toggle(isOn: Binding(get: { !excludedBookings.contains(booking.id) }, set: { include in if include { excludedBookings.remove(booking.id) } else { excludedBookings.insert(booking.id) } })) {
                                Label(booking.provider, systemImage: booking.category.symbol)
                            }
                        }
                    }
                }
                if !draft.unrecognizedContent.isEmpty {
                    Section("Preserved unrecognized content") {
                        ForEach(draft.unrecognizedContent) { fragment in DisclosureGroup(fragment.heading ?? "Section") { Text(fragment.content).textSelection(.enabled) } }
                    }
                }
            }
            .navigationTitle("Import Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(targetTrip == nil ? "Create Trip" : "Update Trip") {
                        if targetTrip == nil { commit() } else { confirmingUpdate = true }
                    }.disabled(draft.hasErrors)
                }
            }
            .confirmationDialog("Replace the structured trip data?", isPresented: $confirmingUpdate, titleVisibility: .visible) {
                Button("Replace Trip", role: .destructive) { commit() }
            } message: { Text("The original source and all existing timeline items, bookings, and reminders will be replaced by this reviewed import.") }
            .alert("Could not save trip", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") {} } message: { Text(saveError ?? "") }
        }
    }

    private func commit() {
        var reviewed = draft
        reviewed.days = reviewed.days.map { day in var copy = day; copy.items.removeAll { excludedItems.contains($0.id) }; return copy }
        reviewed.bookings.removeAll { excludedBookings.contains($0.id) }
        let validItems = Set(reviewed.days.flatMap(\.items).map(\.id))
        let validBookings = Set(reviewed.bookings.map(\.id))
        reviewed.days = reviewed.days.map { day in var copy = day; copy.items = copy.items.map { item in var item = item; item.bookingIDs = item.bookingIDs.filter(validBookings.contains); return item }; return copy }
        reviewed.bookings = reviewed.bookings.map { booking in var copy = booking; copy.timelineItemIDs = copy.timelineItemIDs.filter(validItems.contains); return copy }
        reviewed.reminders.removeAll { $0.timelineItemID.map { !validItems.contains($0) } ?? false }
        do {
            let repository = TripImportRepository(modelContext: modelContext)
            if let targetTrip { _ = try repository.replace(targetTrip, with: reviewed) }
            else { _ = try repository.create(from: reviewed) }
            completion()
        } catch { saveError = error.localizedDescription }
    }

    private var updateDiff: (added: Int, modified: Int, preserved: Int, removed: Int) {
        guard let targetTrip else { return (draft.itemCount + draft.bookings.count, 0, 0, 0) }
        let oldItems = Dictionary(uniqueKeysWithValues: targetTrip.days.flatMap(\.items).map { ($0.id, "\($0.title)|\($0.categoryRawValue)|\($0.startDate?.timeIntervalSince1970 ?? -1)|\($0.endDate?.timeIntervalSince1970 ?? -1)") })
        let newItems = Dictionary(uniqueKeysWithValues: draft.days.flatMap(\.items).map { ($0.id, "\($0.title)|\($0.category.rawValue)|\($0.startDate?.timeIntervalSince1970 ?? -1)|\($0.endDate?.timeIntervalSince1970 ?? -1)") })
        let oldBookings = Dictionary(uniqueKeysWithValues: targetTrip.bookings.map { ($0.id, "\($0.provider)|\($0.categoryRawValue)|\($0.statusRawValue)|\($0.reference ?? "")") })
        let newBookings = Dictionary(uniqueKeysWithValues: draft.bookings.map { ($0.id, "\($0.provider)|\($0.category.rawValue)|\($0.status.rawValue)|\($0.reference ?? "")") })
        let old = oldItems.merging(oldBookings) { left, _ in left }
        let new = newItems.merging(newBookings) { left, _ in left }
        let shared = Set(old.keys).intersection(new.keys)
        let modified = shared.filter { old[$0] != new[$0] }.count
        return (Set(new.keys).subtracting(old.keys).count, modified,
                shared.count - modified, Set(old.keys).subtracting(new.keys).count)
    }
}
