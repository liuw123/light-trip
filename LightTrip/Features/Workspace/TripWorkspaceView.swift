import SwiftUI

struct TripWorkspaceView: View {
    let trip: Trip

    var body: some View {
        TabView {
            NavigationStack { OverviewView(trip: trip) }
                .tabItem { Label("Overview", systemImage: "sparkles") }
            NavigationStack { TimelineView(trip: trip) }
                .tabItem { Label("Timeline", systemImage: "list.bullet.rectangle") }
            NavigationStack { BookingsView(trip: trip) }
                .tabItem { Label("Bookings", systemImage: "ticket") }
            NavigationStack { OriginalPlanView(trip: trip) }
                .tabItem { Label("Plan", systemImage: "doc.text") }
        }
    }
}
