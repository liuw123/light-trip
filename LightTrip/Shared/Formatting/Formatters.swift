import Foundation

enum TripFormatters {
    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = timeZone
        return formatter
    }

    private static func shortDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        formatter.timeZone = timeZone
        return formatter
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = timeZone
        return formatter
    }

    static func dateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateFormatter(timeZone: timeZone).string(from: date)
    }

    static func shortDateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        shortDateFormatter(timeZone: timeZone).string(from: date)
    }

    static func timeString(_ date: Date, timeZone: TimeZone = .current) -> String {
        timeFormatter(timeZone: timeZone).string(from: date)
    }

    static func range(_ start: Date, _ end: Date, timeZone: TimeZone = .current) -> String {
        "\(dateString(start, timeZone: timeZone)) – \(dateString(end, timeZone: timeZone))"
    }
}
