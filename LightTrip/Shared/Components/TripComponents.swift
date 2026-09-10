import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
        }
    }
}

struct CategoryBadge: View {
    let category: TimelineCategory
    var body: some View {
        Label(category.label, systemImage: category.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(category.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(category.tint.opacity(0.12), in: Capsule())
    }
}

struct TimelineItemCard: View {
    let item: TimelineItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(item.startDate.map { TripFormatters.timeString($0, timeZone: item.day?.trip?.timeZone ?? .current) } ?? "Anytime")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: item.category.symbol)
                    .frame(width: 34, height: 34).background(item.category.tint.opacity(0.14), in: Circle())
                    .foregroundStyle(item.category.tint)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline)
                if let origin = item.origin, let destination = item.destination {
                    Label("\(origin) → \(destination)", systemImage: "arrow.right")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if let location = item.locationName ?? item.destination {
                    Label(location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                }
                if item.requiresConfirmation {
                    Label("Confirmation needed", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                if let buffer = item.bufferMinutes {
                    Text("Includes \(buffer) min buffer").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct BookingRow: View {
    let booking: Booking
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: booking.category.symbol)
                .font(.title3).frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(booking.provider).font(.headline)
                Text(booking.details.summaryRows.first?.1 ?? booking.category.label)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let start = booking.startDate { Text("\(TripFormatters.shortDateString(start, timeZone: booking.trip?.timeZone ?? .current)) · \(TripFormatters.timeString(start, timeZone: booking.trip?.timeZone ?? .current))").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(booking.status.label).font(.caption.weight(.semibold))
                .foregroundStyle(booking.status == .needsConfirmation ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
