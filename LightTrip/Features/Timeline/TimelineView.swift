import SwiftUI

struct TimelineView: View {
    let trip: Trip
    @State private var selectedDayID: UUID?
    @State private var filter: TimelineFilter = .all
    @State private var showingEditor = false
    @State private var query = ""

    private var selectedDay: TripDay? {
        trip.sortedDays.first { $0.id == selectedDayID } ?? trip.sortedDays.first
    }

    var body: some View {
        Group {
            if trip.days.isEmpty {
                EmptyStateView(symbol: "calendar", title: "No itinerary yet", message: "Add an activity or import a plan.", actionTitle: "Add Activity") { showingEditor = true }
            } else {
                VStack(spacing: 0) {
                    dayPicker
                    filterPicker
                    List {
                        if let selectedDay {
                            if let summary = selectedDay.summary { Text(summary).foregroundStyle(.secondary) }
                            ForEach(filtered(selectedDay.sortedItems)) { item in
                                NavigationLink { ActivityDetailView(item: item) } label: { TimelineItemCard(item: item) }
                            }
                            ForEach(selectedDay.importantNotes, id: \.self) { note in
                                Label(note, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                    }.listStyle(.plain)
                }
            }
        }
        .navigationTitle("Timeline")
        .searchable(text: $query, prompt: "Search activities and places")
        .toolbar { Button("Add", systemImage: "plus") { showingEditor = true } }
        .sheet(isPresented: $showingEditor) { ActivityEditorView(trip: trip, preferredDay: selectedDay) }
        .onAppear { selectedDayID = selectedDayID ?? trip.sortedDays.first?.id }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trip.sortedDays) { day in
                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 2) {
                            Text("DAY \(day.sequence)").font(.caption2.bold())
                            Text(TripFormatters.shortDateString(day.date, timeZone: trip.timeZone)).font(.subheadline.bold())
                        }.padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedDay?.id == day.id ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(selectedDay?.id == day.id ? .white : .primary)
                    }
                }
            }.padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(TimelineFilter.allCases) { Text($0.label).tag($0) }
        }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)
    }

    private func filtered(_ items: [TimelineItem]) -> [TimelineItem] {
        let categoryFiltered = filter.categories.map { categories in items.filter { categories.contains($0.category) } } ?? items
        return categoryFiltered.filter(matchesQuery)
    }

    private func matchesQuery(_ item: TimelineItem) -> Bool {
        guard !query.isEmpty else { return true }
        return [item.title, item.notes, item.origin, item.destination, item.locationName]
            .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all, transport, activities, hotels, meals, important
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var categories: Set<TimelineCategory>? {
        switch self {
        case .all: nil
        case .transport: [.transport]
        case .activities: [.activity]
        case .hotels: [.accommodation]
        case .meals: [.meal, .breakTime]
        case .important: [.reminder]
        }
    }
}
