import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TripSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var showingEditor = false
    @State private var confirmDelete = false
    @State private var exportDocument: TripTextDocument?
    @State private var showingExporter = false
    @State private var reminderError: String?
    @State private var showingReimport = false

    var body: some View {
        Form {
            Section("Trip") {
                LabeledContent("Title", value: trip.title)
                LabeledContent("Destination", value: trip.destination)
                LabeledContent("Dates", value: TripFormatters.range(trip.startDate, trip.endDate, timeZone: trip.timeZone))
                LabeledContent("Time zone", value: trip.timeZoneIdentifier)
                LabeledContent("Travelers", value: "\(trip.travelerCount)")
                Button("Edit trip", systemImage: "pencil") { showingEditor = true }
            }
            Section("Reminders") {
                if trip.reminders.filter({ $0.timelineItem != nil }).isEmpty { Text("No scheduled reminder rules").foregroundStyle(.secondary) }
                ForEach(trip.reminders.filter { $0.timelineItem != nil }) { reminder in
                    Toggle(reminder.title, isOn: Binding(get: { reminder.isEnabled }, set: { enabled in
                        Task { await configure(reminder, enabled: enabled) }
                    }))
                }
            }
            if !trip.reminders.filter({ $0.timelineItem == nil }).isEmpty {
                Section("Checklist") {
                    ForEach(trip.reminders.filter { $0.timelineItem == nil }) { reminder in
                        Toggle(reminder.title, isOn: Binding(get: { reminder.isCompleted }, set: { reminder.isCompleted = $0; try? modelContext.save() }))
                    }
                }
            }
            Section("Documents") {
                Button("Reimport or replace trip", systemImage: "arrow.triangle.2.circlepath") { showingReimport = true }
                Button("Export canonical JSON", systemImage: "curlybraces") {
                    if let text = (try? TripExporter().data(for: trip)).flatMap({ String(data: $0, encoding: .utf8) }) {
                        exportDocument = TripTextDocument(text: text); showingExporter = true
                    }
                }
                if let source = trip.sourceDocument { ShareLink(item: source.rawContent) { Label("Share preserved source", systemImage: "doc") } }
            }
            Section {
                Button(trip.archivedAt == nil ? "Archive trip" : "Restore trip", systemImage: "archivebox") {
                    trip.archivedAt = trip.archivedAt == nil ? .now : nil; trip.updatedAt = .now; try? modelContext.save()
                }
                Button("Delete trip", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Trip Settings")
        .sheet(isPresented: $showingEditor) { TripEditorView(trip: trip) }
        .sheet(isPresented: $showingReimport) { ImportView(targetTrip: trip) }
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: .json, defaultFilename: "\(trip.title).lighttrip") { _ in exportDocument = nil }
        .confirmationDialog("Delete \(trip.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                NotificationScheduler.shared.removeAll(for: trip); modelContext.delete(trip); try? modelContext.save(); dismiss()
            }
        } message: { Text("This removes its itinerary, bookings, reminders, and original source from this device.") }
        .alert("Reminder unavailable", isPresented: Binding(get: { reminderError != nil }, set: { if !$0 { reminderError = nil } })) {
            Button("OK") {}
        } message: { Text(reminderError ?? "") }
    }

    private func configure(_ reminder: ReminderRule, enabled: Bool) async {
        do {
            if enabled { try await NotificationScheduler.shared.enable(reminder) }
            else { reminder.isEnabled = false; NotificationScheduler.shared.remove(reminder) }
            try modelContext.save()
        } catch { reminderError = error.localizedDescription }
    }
}
