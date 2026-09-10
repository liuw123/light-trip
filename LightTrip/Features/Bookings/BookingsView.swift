import SwiftUI

struct BookingsView: View {
    let trip: Trip
    @State private var category: BookingCategory?
    @State private var showingEditor = false
    @State private var query = ""

    private var filtered: [Booking] {
        trip.bookings.filter { category == nil || $0.category == category }
            .filter { query.isEmpty || $0.provider.localizedCaseInsensitiveContains(query) || $0.details.summaryRows.contains { $0.1.localizedCaseInsensitiveContains(query) } }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if trip.bookings.isEmpty {
                EmptyStateView(symbol: "ticket", title: "No bookings", message: "Add a reservation or import a trip plan.", actionTitle: "Add Booking") { showingEditor = true }
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            filterButton(nil, label: "All")
                            ForEach(BookingCategory.allCases) { item in filterButton(item, label: item.label) }
                        }.padding(.horizontal).padding(.vertical, 8)
                    }
                    List(filtered) { booking in
                        NavigationLink { BookingDetailView(booking: booking) } label: { BookingRow(booking: booking) }
                    }.listStyle(.plain)
                }
            }
        }
        .navigationTitle("Bookings")
        .searchable(text: $query, prompt: "Search provider or service")
        .toolbar { Button("Add", systemImage: "plus") { showingEditor = true } }
        .sheet(isPresented: $showingEditor) { BookingEditorView(trip: trip) }
    }

    private func filterButton(_ value: BookingCategory?, label: String) -> some View {
        Button(label) { category = value }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .tint(category == value ? Color.accentColor : Color.secondary)
    }
}
