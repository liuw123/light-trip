import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var selection: Trip?
    @State private var showingImport = false
    @State private var showingCreate = false

    private var activeTrips: [Trip] { trips.filter { $0.archivedAt == nil } }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    TripsSidebar(trips: activeTrips, selection: $selection,
                                 showingImport: $showingImport, showingCreate: $showingCreate)
                } detail: {
                    if let selection { TripWorkspaceView(trip: selection) }
                    else { EmptyStateView(symbol: "map", title: "Choose a trip", message: "Select a trip in the sidebar or import a new plan.", actionTitle: "Import Trip") { showingImport = true } }
                }
            } else {
                NavigationStack {
                    TripsView(trips: activeTrips, showingImport: $showingImport, showingCreate: $showingCreate)
                }
            }
        }
        .sheet(isPresented: $showingImport) { ImportView() }
        .sheet(isPresented: $showingCreate) { TripEditorView() }
    }
}
private struct TripsSidebar: View {
    let trips: [Trip]
    @Binding var selection: Trip?
    @Binding var showingImport: Bool
    @Binding var showingCreate: Bool

    var body: some View {
        List(trips, selection: $selection) { trip in
            VStack(alignment: .leading) {
                Text(trip.title).font(.headline)
                Text(trip.destination).font(.caption).foregroundStyle(.secondary)
            }.tag(trip)
        }
        .navigationTitle("Light Trip")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Import", systemImage: "square.and.arrow.down") { showingImport = true } }
            ToolbarItem { Button("New", systemImage: "plus") { showingCreate = true } }
        }
    }
}
