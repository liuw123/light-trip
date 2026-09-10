import SwiftData
import SwiftUI

@main
struct LightTripApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            Trip.self, TripDay.self, TimelineItem.self, Booking.self,
            SourceDocument.self, ReminderRule.self
        ])
        do {
            if CommandLine.arguments.contains("-ui-testing-reset") {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            }
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create Light Trip store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
