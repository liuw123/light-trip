import SwiftData
import SwiftUI

struct BookingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let booking: Booking
    @State private var revealReference = false
    @State private var showingEditor = false
    @State private var showingDelete = false
    @State private var phoneToCall: String?

    var body: some View {
        List {
            Section {
                Label(booking.category.label, systemImage: booking.category.symbol).font(.headline)
                LabeledContent("Provider", value: booking.provider)
                LabeledContent("Status", value: booking.status.label)
                if let start = booking.startDate { LabeledContent("Starts", value: "\(TripFormatters.dateString(start, timeZone: booking.trip?.timeZone ?? .current)) · \(TripFormatters.timeString(start, timeZone: booking.trip?.timeZone ?? .current))") }
                if let end = booking.endDate { LabeledContent("Ends", value: "\(TripFormatters.dateString(end, timeZone: booking.trip?.timeZone ?? .current)) · \(TripFormatters.timeString(end, timeZone: booking.trip?.timeZone ?? .current))") }
            }
            if let reference = booking.reference {
                Section("Reservation reference") {
                    HStack {
                        Text(revealReference ? reference : Self.mask(reference)).font(.body.monospaced())
                        Spacer()
                        Button(revealReference ? "Hide" : "Reveal") { revealReference.toggle() }
                    }
                    if revealReference { ShareLink(item: reference) { Label("Copy or share", systemImage: "square.and.arrow.up") } }
                }
            }
            Section("Details") {
                ForEach(Array(booking.details.summaryRows.enumerated()), id: \.offset) { _, row in
                    LabeledContent(row.0, value: row.1.isEmpty ? "—" : row.1)
                }
            }
            if let notes = booking.notes { Section("Notes") { Text(notes) } }
            if !booking.timelineItems.isEmpty {
                Section("Related timeline") {
                    ForEach(booking.timelineItems) { item in NavigationLink { ActivityDetailView(item: item) } label: { TimelineItemCard(item: item) } }
                }
            }
            if booking.officialURL != nil || booking.contactPhone != nil {
                Section("Contact") {
                    if let url = booking.officialURL { Button("Open official website", systemImage: "safari") { openURL(url) } }
                    if let phone = booking.contactPhone { Button("Call \(phone)", systemImage: "phone") { phoneToCall = phone } }
                }
            }
        }
        .navigationTitle(booking.provider).navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu { Button("Edit", systemImage: "pencil") { showingEditor = true }; Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true } } label: { Image(systemName: "ellipsis.circle") } }
        .sheet(isPresented: $showingEditor) { BookingEditorView(booking: booking) }
        .confirmationDialog("Delete this booking?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { modelContext.delete(booking); try? modelContext.save(); dismiss() }
        }
        .confirmationDialog("Call this contact?", isPresented: Binding(get: { phoneToCall != nil }, set: { if !$0 { phoneToCall = nil } }), titleVisibility: .visible) {
            if let phoneToCall, let url = URL(string: "tel:\(phoneToCall.filter { $0.isNumber || $0 == "+" })") {
                Button("Call \(phoneToCall)") { openURL(url); self.phoneToCall = nil }
            }
            Button("Cancel", role: .cancel) { phoneToCall = nil }
        }
    }

    private static func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        return String(value.prefix(2)) + String(repeating: "•", count: value.count - 4) + String(value.suffix(2))
    }
}
