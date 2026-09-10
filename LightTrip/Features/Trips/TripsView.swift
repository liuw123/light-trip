import SwiftUI

struct TripsView: View {
    let trips: [Trip]
    @Binding var showingImport: Bool
    @Binding var showingCreate: Bool

    var body: some View {
        Group {
            if trips.isEmpty {
                EmptyStateView(symbol: "suitcase.rolling.fill", title: "Your trips, ready when you are",
                               message: "Import JSON or Markdown, or create a trip manually.",
                               actionTitle: "Import Trip") { showingImport = true }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(trips) { trip in
                            NavigationLink { TripWorkspaceView(trip: trip) } label: { TripCard(trip: trip) }
                                .buttonStyle(.plain)
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Import", systemImage: "square.and.arrow.down") { showingImport = true } }
            ToolbarItem { Button("New", systemImage: "plus") { showingCreate = true } }
        }
    }
}

private struct TripCard: View {
    let trip: Trip
    private var daysUntil: Int { var calendar = Calendar.current; calendar.timeZone = trip.timeZone; return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: trip.startDate)).day ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title).font(.title3.bold())
                    Label(trip.destination, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            Divider()
            HStack {
                Text(TripFormatters.range(trip.startDate, trip.endDate, timeZone: trip.timeZone)).font(.subheadline)
                Spacer()
                Text(daysUntil > 0 ? "In \(daysUntil) days" : daysUntil == 0 ? "Today" : "Completed")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule()).foregroundStyle(.tint)
            }
        }
        .padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
