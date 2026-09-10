import Foundation

enum TimelineState { case upcoming, current, completed }

struct NextItemService {
    func nextItem(in trip: Trip, now: Date = .now) -> TimelineItem? {
        let items = trip.sortedDays.flatMap(\.sortedItems).filter { !$0.isUntimed && !$0.isManuallyCompleted }
        if let current = items.first(where: { item in
            guard let start = item.startDate, let end = item.endDate else { return false }
            return start <= now && now <= end
        }) { return current }
        return items.first { ($0.startDate ?? .distantPast) > now }
    }

    func state(of item: TimelineItem, now: Date = .now) -> TimelineState {
        if item.isManuallyCompleted { return .completed }
        guard let start = item.startDate else { return .upcoming }
        if let end = item.endDate, end < now { return .completed }
        if start <= now { return .current }
        return .upcoming
    }
}
