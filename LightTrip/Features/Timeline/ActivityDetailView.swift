import MapKit
import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: TimelineItem
    @State private var showingEditor = false
    @State private var showingDelete = false
    @State private var reminderError: String?
    @State private var phoneToCall: String?

    var body: some View {
        List {
            Section {
                CategoryBadge(category: item.category)
                LabeledContent("Start") { Text(item.startDate.map { TripFormatters.dateString($0, timeZone: item.day?.trip?.timeZone ?? .current) + " · " + TripFormatters.timeString($0, timeZone: item.day?.trip?.timeZone ?? .current) } ?? "Anytime") }
                if let end = item.endDate { LabeledContent("End", value: TripFormatters.timeString(end, timeZone: item.day?.trip?.timeZone ?? .current)) }
                if let latest = item.latestSafeDeparture { LabeledContent("Latest safe departure", value: TripFormatters.timeString(latest, timeZone: item.day?.trip?.timeZone ?? .current)).foregroundStyle(.orange) }
                if let buffer = item.bufferMinutes { LabeledContent("Buffer", value: "\(buffer) minutes") }
            }
            if item.origin != nil || item.destination != nil || item.locationName != nil {
                Section("Location") {
                    if let origin = item.origin { LabeledContent("From", value: origin) }
                    if let destination = item.destination { LabeledContent("To", value: destination) }
                    if let location = item.locationName { LabeledContent("At", value: location) }
                    if let meeting = item.meetingPoint { LabeledContent("Meeting point", value: meeting) }
                    if let query = item.locationName ?? item.destination {
                        Button("Open in Maps", systemImage: "map") { openMaps(query) }
                    }
                }
            }
            if let notes = item.notes { Section("Notes") { Text(notes) } }
            if !item.bookings.isEmpty {
                Section("Related bookings") {
                    ForEach(item.bookings) { booking in NavigationLink { BookingDetailView(booking: booking) } label: { BookingRow(booking: booking) } }
                }
            }
            Section("Reminder") {
                if let reminder = item.reminders.first {
                    Toggle("\(reminder.offsetMinutes) minutes before", isOn: Binding(get: { reminder.isEnabled }, set: { enabled in
                        Task { await setReminder(reminder, enabled: enabled) }
                    }))
                } else {
                    Button("Remind me 30 minutes before", systemImage: "bell.badge") { Task { await addReminder() } }
                        .disabled(item.startDate == nil)
                }
            }
            if item.officialURL != nil || item.contactPhone != nil {
                Section("Contact") {
                    if let url = item.officialURL { Button("Open official website", systemImage: "safari") { openURL(url) } }
                    if let phone = item.contactPhone { Button("Call \(phone)", systemImage: "phone") { phoneToCall = phone } }
                }
            }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu { Button("Edit", systemImage: "pencil") { showingEditor = true }; Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true } } label: { Image(systemName: "ellipsis.circle") } }
        .sheet(isPresented: $showingEditor) { ActivityEditorView(item: item) }
        .confirmationDialog("Delete this activity?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { modelContext.delete(item); try? modelContext.save(); dismiss() }
        }
        .alert("Reminder unavailable", isPresented: Binding(get: { reminderError != nil }, set: { if !$0 { reminderError = nil } })) { Button("OK") {} } message: { Text(reminderError ?? "") }
        .confirmationDialog("Call this contact?", isPresented: Binding(get: { phoneToCall != nil }, set: { if !$0 { phoneToCall = nil } }), titleVisibility: .visible) {
            if let phoneToCall, let url = URL(string: "tel:\(phoneToCall.filter { $0.isNumber || $0 == "+" })") {
                Button("Call \(phoneToCall)") { openURL(url); self.phoneToCall = nil }
            }
            Button("Cancel", role: .cancel) { phoneToCall = nil }
        }
    }

    private func openMaps(_ query: String) {
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        Task { if let item = try? await MKLocalSearch(request: request).start().mapItems.first { item.openInMaps() } }
    }

    private func addReminder() async {
        let reminder = ReminderRule(offsetMinutes: 30, title: "Upcoming trip activity")
        item.reminders.append(reminder); item.day?.trip?.reminders.append(reminder)
        modelContext.insert(reminder)
        do { try await NotificationScheduler.shared.enable(reminder); try modelContext.save() }
        catch { reminderError = error.localizedDescription }
    }

    private func setReminder(_ reminder: ReminderRule, enabled: Bool) async {
        do {
            if enabled { try await NotificationScheduler.shared.enable(reminder) }
            else { reminder.isEnabled = false; NotificationScheduler.shared.remove(reminder) }
            try modelContext.save()
        } catch { reminderError = error.localizedDescription }
    }
}
