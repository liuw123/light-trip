import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    private let service = NextItemService()

    private var next: TimelineItem? { service.nextItem(in: trip) }
    private var confirmations: [TimelineItem] { trip.days.flatMap(\.items).filter(\.requiresConfirmation) }
    private var checklist: [ReminderRule] { trip.reminders.filter { $0.timelineItem == nil && !$0.isCompleted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.destination).font(.title.bold())
                    Text(TripFormatters.range(trip.startDate, trip.endDate, timeZone: trip.timeZone)).foregroundStyle(.secondary)
                    Label("\(trip.travelerCount) traveler\(trip.travelerCount == 1 ? "" : "s")", systemImage: "person.2")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let next {
                    NavigationLink { ActivityDetailView(item: next) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NEXT UP").font(.caption.bold()).foregroundStyle(.secondary)
                            CategoryBadge(category: next.category)
                            Text(next.title).font(.title2.bold()).foregroundStyle(.primary)
                            if let start = next.startDate { Text("\(TripFormatters.dateString(start, timeZone: trip.timeZone)) · \(TripFormatters.timeString(start, timeZone: trip.timeZone))").foregroundStyle(.secondary) }
                            if let latest = next.latestSafeDeparture {
                                Label("Leave no later than \(TripFormatters.timeString(latest, timeZone: trip.timeZone))", systemImage: "clock.badge.exclamationmark")
                                    .font(.subheadline.bold()).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                } else {
                    ContentUnavailableView("Nothing else scheduled", systemImage: "checkmark.circle", description: Text("Your complete timeline is still available."))
                }
                if !confirmations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Needs attention").font(.title3.bold())
                        ForEach(confirmations.prefix(4)) { item in
                            NavigationLink { ActivityDetailView(item: item) } label: { TimelineItemCard(item: item) }
                        }
                    }
                }
                if !checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Checklist").font(.title3.bold())
                        ForEach(checklist) { reminder in
                            Button {
                                reminder.isCompleted = true; try? modelContext.save()
                            } label: {
                                Label(reminder.title, systemImage: "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).padding(.vertical, 4)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bookings").font(.title3.bold())
                    Text("\(trip.bookings.count) reservations across \(Set(trip.bookings.map(\.categoryRawValue)).count) categories")
                        .foregroundStyle(.secondary)
                }
            }.padding()
        }
        .navigationTitle(trip.title)
        .toolbar { NavigationLink(destination: TripSettingsView(trip: trip)) { Image(systemName: "gearshape") } }
    }
}
