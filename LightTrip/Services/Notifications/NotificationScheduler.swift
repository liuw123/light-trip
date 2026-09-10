import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    func enable(_ reminder: ReminderRule) async throws {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }
        reminder.isEnabled = true
        try await schedule(reminder)
    }

    func schedule(_ reminder: ReminderRule) async throws {
        guard reminder.isEnabled, let item = reminder.timelineItem, let start = item.startDate else { return }
        if let existing = reminder.notificationIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [existing])
        }
        let identifier = "light-trip.\(reminder.id.uuidString)"
        let fireDate = start.addingTimeInterval(TimeInterval(-reminder.offsetMinutes * 60))
        guard fireDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = item.title
        content.sound = .default
        let calendar = item.day?.trip.map { ContractDate.calendar(timeZoneIdentifier: $0.timeZoneIdentifier) } ?? .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.timeZone = calendar.timeZone
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try await center.add(request)
        reminder.notificationIdentifier = identifier
    }

    func remove(_ reminder: ReminderRule) {
        guard let identifier = reminder.notificationIdentifier else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        reminder.notificationIdentifier = nil
    }

    func removeAll(for trip: Trip) {
        let ids = trip.reminders.compactMap(\.notificationIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
