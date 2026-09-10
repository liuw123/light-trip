import CryptoKit
import Foundation

struct MarkdownTripParser: TripImportParser {
    static let parserVersion = 1

    static func looksLikeMarkdown(_ source: String) -> Bool {
        source.range(of: #"(?m)^#{1,3}\s+.+$"#, options: .regularExpression) != nil ||
        source.range(of: #"(?m)^\|.+\|$"#, options: .regularExpression) != nil
    }

    func parse(_ rawSource: String, sourceName: String?) throws -> TripImportDraft {
        let source = rawSource.replacingOccurrences(of: "\r\n", with: "\n")
        let document = MarkdownDocument(source)
        guard document.title != nil || !document.tables.isEmpty || !document.dayHeadings.isEmpty else {
            throw ImportServiceError.unsupported
        }

        var diagnostics: [ImportDiagnostic] = []
        let timeZoneIdentifier = document.metadata["timezone"] ?? document.metadata["timezoneidentifier"] ?? document.metadata["时区"] ?? "Asia/Shanghai"
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
        if TimeZone(identifier: timeZoneIdentifier) == nil {
            diagnostics.append(.init(severity: .warning, path: "metadata.timeZone", message: "Unknown timezone; Asia/Shanghai was used."))
        }
        let calendar = ContractDate.calendar(timeZoneIdentifier: timeZone.identifier)
        let explicitRange = parseDateRange(document.metadata["dates"] ?? document.metadata["日期"] ?? document.metadata["行程日期"], calendar: calendar)
        let detectedYear = source.matches(#"(?:19|20)\d{2}"#).first.flatMap(Int.init)
        let headingDates = document.dayHeadings.compactMap { resolveDayDate($0.date, range: explicitRange, fallbackYear: detectedYear, calendar: calendar) }
        guard let startDate = explicitRange?.0 ?? headingDates.min(),
              let endDate = explicitRange?.1 ?? headingDates.max() else {
            throw ContractError.diagnostics([.init(severity: .error, path: "metadata.dates", message: "Add a YYYY-MM-DD date range or dated Day heading.")])
        }

        let bookingResult = parseBookings(document.tables, calendar: calendar, diagnostics: &diagnostics)
        let keyToBooking = Dictionary(uniqueKeysWithValues: bookingResult.map { ($0.matchKey, $0.draft) })
        var parsedDays: [TripDayDraft] = []
        for heading in document.dayHeadings.sorted(by: { $0.sequence < $1.sequence }) {
            guard let date = resolveDayDate(heading.date, range: explicitRange, fallbackYear: detectedYear, calendar: calendar) else {
                diagnostics.append(.init(severity: .error, path: "days[\(heading.sequence - 1)].date", message: "Date must use YYYY-MM-DD."))
                continue
            }
            let table = document.tables.first { $0.heading2 == heading.raw && $0.hasAnyColumn(["time", "时间"]) && $0.hasAnyColumn(["plan", "具体安排", "安排", "行程"]) }
            let items = table.map { parseTimeline($0, date: date, calendar: calendar, bookingMap: keyToBooking, diagnostics: &diagnostics) } ?? []
            if table == nil {
                diagnostics.append(.init(severity: .warning, path: "days[\(heading.sequence - 1)].items", message: "No timeline table was found for this day."))
            }
            parsedDays.append(.init(id: StableID.make("day|\(heading.date)|\(heading.title)"), date: date,
                                    sequence: heading.sequence, title: heading.title, summary: nil,
                                    importantNotes: [], items: items))
        }

        if parsedDays.isEmpty {
            diagnostics.append(.init(severity: .error, path: "days", message: "No dated Day headings were recognized."))
        }
        let importantNotes = document.bulletItems(inSections: ["importantnotes", "warnings", "重要提示", "注意事项"])
        if !parsedDays.isEmpty { parsedDays[0].importantNotes.append(contentsOf: importantNotes) }
        let itemKeyToID: [String: UUID] = Dictionary(uniqueKeysWithValues: parsedDays.flatMap(\.items).map {
            (Self.itemMatchKey($0), $0.id)
        })
        var bookings = bookingResult.map(\.draft)
        for index in bookings.indices {
            let keys = bookingResult[index].timelineKeys
            bookings[index].timelineItemIDs = keys.compactMap { itemKeyToID[$0] }
        }

        let reminderTexts = document.checklistItems(inSections: ["reminders", "提醒", "待办"])
        let reminders = reminderTexts.enumerated().map { index, title in
            ReminderDraft(id: StableID.make("reminder|\(index)|\(title)"), timelineItemID: nil,
                          offsetMinutes: 0, title: title, isEnabled: false)
        }
        let recognizedRanges = Set(document.tables.flatMap(\.lineRange)).union(document.dayHeadings.map(\.line))
        let unknown = document.unrecognizedSections(excluding: recognizedRanges)
        let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? sourceName ?? "Imported Trip"
        let destination = (document.metadata["destination"] ?? document.metadata["目的地"])?.nonEmpty ?? title
        let travelers = Int(document.metadata["travelers"] ?? document.metadata["人数"] ?? "") ?? 1
        let trip = TripDraft(id: StableID.make("trip|\(title)|\(ContractDate.dayString(startDate, timeZone: timeZone))"),
                             title: title, destination: destination, startDate: startDate,
                             endDate: endDate, timeZoneIdentifier: timeZone.identifier,
                             travelerCount: max(1, travelers))
        return TripImportDraft(trip: trip, days: parsedDays, bookings: bookings, reminders: reminders,
                               unrecognizedContent: unknown, diagnostics: diagnostics, rawSource: rawSource,
                               sourceFormat: .markdown, contractVersion: nil,
                               parserVersion: Self.parserVersion, sourceName: sourceName)
    }

    private func parseTimeline(_ table: MarkdownTable, date: Date, calendar: Calendar,
                               bookingMap: [String: BookingDraft], diagnostics: inout [ImportDiagnostic]) -> [TimelineItemDraft] {
        table.rows.enumerated().map { index, row in
            let timeValue = row.value(forAny: ["time", "时间"])
            let times = parseTimeRange(timeValue)
            let title = row.value(forAny: ["plan", "具体安排", "安排", "行程"]).nonEmpty ?? "Untitled activity"
            let category = timelineCategory(row.value(forAny: ["type", "类型", "类别"]) + " " + title)
            let bookingKey = normalizeBookingKey(row.value(forAny: ["booking", "预订", "订单", "车票"]))
            let buffer = integer(in: row.value(forAny: ["buffer", "缓冲", "预留"]))
            let notes = row.value(forAny: ["notes", "备注", "交通与取舍", "说明"]).dashToNil
            let confirmation = row.value(forAny: ["confirmation", "确认", "状态"]).lowercased()
            if timeValue.nonEmpty != nil && times.0 == nil {
                diagnostics.append(.init(severity: .warning, path: "timeline[\(index)].time", message: "Unrecognized time; item was imported as untimed."))
            }
            let start = ContractDate.localTime(times.0, on: date, calendar: calendar)
            let end = ContractDate.localTime(times.1, on: date, calendar: calendar)
            let fingerprint = "\(ContractDate.dayString(date, timeZone: calendar.timeZone))|\(timeValue)|\(title)|\(category.rawValue)"
            let bookingID = bookingMap[bookingKey]?.id
            let latest = notes.flatMap { parseLatestDeparture(in: $0, date: date, calendar: calendar) }
            return TimelineItemDraft(
                id: StableID.make("item|\(fingerprint)"), title: title, category: category,
                startDate: start, endDate: end, isUntimed: start == nil,
                origin: row.value(forAny: ["from", "出发地", "起点"]).dashToNil,
                destination: row.value(forAny: ["to/location", "to", "目的地", "终点"]).dashToNil,
                locationName: row.value(forAny: ["location", "地点", "位置"]).dashToNil,
                meetingPoint: row.value(forAny: ["meetingpoint", "集合点", "上车点"]).dashToNil,
                notes: notes, bufferMinutes: buffer, latestSafeDeparture: latest,
                officialURL: firstURL(in: notes), contactPhone: firstPhone(in: notes),
                requiresConfirmation: confirmation.contains("required") || confirmation.contains("待确认"),
                sequence: index, bookingIDs: bookingID.map { [$0] } ?? [], sourceFingerprint: fingerprint
            )
        }
    }

    private struct ParsedBooking {
        var matchKey: String
        var draft: BookingDraft
        var timelineKeys: [String]
    }

    private func parseBookings(_ tables: [MarkdownTable], calendar: Calendar,
                               diagnostics: inout [ImportDiagnostic]) -> [ParsedBooking] {
        var result: [ParsedBooking] = []
        for table in tables where table.heading2.lowercased().contains("booking") || table.heading2.contains("预订") {
            guard let category = bookingCategory(table.heading3) else { continue }
            for (index, row) in table.rows.enumerated() {
                let service = firstValue(row, keys: ["service", "train", "flight", "reference", "hotel", "attraction", "服务", "车次", "航班号", "订单号", "酒店", "景区"]).dashToNil
                let reference = row.value(forAny: ["reference", "订单号", "预订号"]).dashToNil ?? service
                let provider = firstValue(row, keys: ["provider", "hotel", "attraction", "供应商", "航司", "酒店", "景区"]).dashToNil ?? service ?? category.label
                let dateText = firstValue(row, keys: ["date", "visitdate", "check-in", "日期", "游览日期", "入住"])
                let endDateText = row.value(forAny: ["check-out", "退房"])
                let departure = firstValue(row, keys: ["departure", "pickup", "entrywindow", "出发", "起飞", "上车点", "入园时段"])
                let arrival = row.value(forAny: ["arrival", "到达"])
                let start = combine(date: dateText, time: departure, calendar: calendar)
                let end = combine(date: endDateText.nonEmpty == nil ? dateText : endDateText, time: arrival, calendar: calendar)
                let route = row.value(forAny: ["route", "路线"])
                let routeParts = route.split(whereSeparator: { $0 == "→" || $0 == "-" }).map { String($0).trimmingCharacters(in: .whitespaces) }
                let details: BookingDetails
                switch category {
                case .flight:
                    details = .flight(.init(flightNumber: service ?? "—", originAirport: routeParts.first ?? "—",
                                            destinationAirport: routeParts.dropFirst().first ?? "—",
                                            departureTerminal: nil, arrivalTerminal: nil, baggageNote: nil))
                case .train:
                    details = .train(.init(trainNumber: service ?? "—", originStation: routeParts.first ?? "—",
                                          destinationStation: routeParts.dropFirst().first ?? "—",
                                          seatClass: row.value(forAny: ["seat", "席别"]).dashToNil, carriage: nil, seat: nil))
                case .hotel:
                    details = .hotel(.init(propertyName: row.value(forAny: ["hotel", "酒店"]).dashToNil ?? provider,
                                          address: row.value(forAny: ["location", "位置", "地址"]).dashToNil,
                                          checkInNote: nil, checkOutNote: nil, roomInformation: row.value(forAny: ["room", "房型"]).dashToNil))
                case .attraction:
                    details = .attraction(.init(attractionName: row.value(forAny: ["attraction", "景区"]).dashToNil ?? provider,
                                               ticketType: row.value(forAny: ["product", "票种", "产品"]).dashToNil,
                                               entrance: row.value(forAny: ["entrance", "入口"]).dashToNil,
                                               meetingPoint: nil, openingWindow: row.value(forAny: ["entrywindow", "入园时段"]).dashToNil))
                case .groundTransport:
                    details = .groundTransport(.init(origin: routeParts.first, destination: routeParts.dropFirst().first,
                                                     pickup: row.value(forAny: ["pickup", "上车点", "接车点"]).dashToNil, dropOff: nil,
                                                     driver: nil, vehicleNumber: nil, meetingPoint: nil))
                case .other:
                    details = .other(.init(fields: row.values))
                }
                let status = bookingStatus(row.value(forAny: ["status", "状态"]))
                let key = normalizeBookingKey(reference ?? service ?? "\(category.rawValue)-\(index)")
                let id = StableID.make("booking|\(category.rawValue)|\(key)|\(dateText)")
                let link = firstValue(row, keys: ["officiallink", "url", "官方链接"]).dashToNil.flatMap(URL.init(string:))
                let contact = row.value(forAny: ["contact", "联系电话", "电话"]).dashToNil
                let draft = BookingDraft(id: id, category: category, provider: provider, status: status,
                                         reference: reference, startDate: start, endDate: end, officialURL: link,
                                         contactPhone: contact, notes: row.value(forAny: ["notes", "备注"]).dashToNil,
                                         details: details, timelineItemIDs: [],
                                         sourceFingerprint: "\(category.rawValue)|\(key)|\(dateText)")
                result.append(.init(matchKey: key, draft: draft, timelineKeys: []))
            }
        }
        return result
    }

    private func parseDateRange(_ value: String?, calendar: Calendar) -> (Date, Date)? {
        guard let value else { return nil }
        let matches = value.matches(#"\d{4}-\d{2}-\d{2}"#)
        if matches.count >= 2, let start = ContractDate.day(matches[0], calendar: calendar),
           let end = ContractDate.day(matches[1], calendar: calendar) { return (start, end) }
        let chinese = value.matches(#"(?:\d{4}年)?\d{1,2}月\d{1,2}日"#)
        guard chinese.count >= 2 else { return nil }
        let firstNumbers = chinese[0].matches(#"\d+"#).compactMap(Int.init)
        let secondNumbers = chinese[1].matches(#"\d+"#).compactMap(Int.init)
        guard firstNumbers.count == 3 else { return nil }
        let second = secondNumbers.count == 3 ? secondNumbers : [firstNumbers[0]] + secondNumbers
        guard second.count == 3,
              let start = calendar.date(from: DateComponents(year: firstNumbers[0], month: firstNumbers[1], day: firstNumbers[2])),
              let end = calendar.date(from: DateComponents(year: second[0], month: second[1], day: second[2])) else { return nil }
        return (start, end)
    }

    private func resolveDayDate(_ value: String, range: (Date, Date)?, fallbackYear: Int?, calendar: Calendar) -> Date? {
        if let date = ContractDate.day(value, calendar: calendar) { return date }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        let year = range.map { calendar.component(.year, from: $0.0) } ?? fallbackYear
        guard parts.count == 2, let year else { return nil }
        return calendar.date(from: DateComponents(year: year, month: parts[0], day: parts[1]))
    }

    private func parseTimeRange(_ value: String) -> (String?, String?) {
        let matches = value.matches(#"\d{1,2}:\d{2}"#).map { raw -> String in
            let parts = raw.split(separator: ":")
            return String(format: "%02d:%02d", Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        return (matches.first, matches.dropFirst().first)
    }

    private func timelineCategory(_ value: String) -> TimelineCategory {
        let value = value.lowercased()
        if value.contains("flight") || value.contains("train") || value.contains("transport") || value.contains("交通") || value.contains("动车") || value.contains("航班") { return .transport }
        if value.contains("hotel") || value.contains("accommodation") || value.contains("酒店") || value.contains("住宿") || value.contains("入住") { return .accommodation }
        if value.contains("meal") || value.contains("餐") { return .meal }
        if value.contains("break") || value.contains("休息") { return .breakTime }
        if value.contains("reminder") || value.contains("提醒") { return .reminder }
        if value.contains("attraction") || value.contains("activity") || value.contains("景区") || value.contains("游览") { return .activity }
        return .other
    }

    private func bookingCategory(_ heading: String) -> BookingCategory? {
        let value = heading.lowercased()
        if value.contains("flight") || value.contains("航班") { return .flight }
        if value.contains("train") || value.contains("动车") || value.contains("火车") { return .train }
        if value.contains("hotel") || value.contains("酒店") { return .hotel }
        if value.contains("attraction") || value.contains("ticket") || value.contains("景区") || value.contains("门票") { return .attraction }
        if value.contains("ground") || value.contains("car") || value.contains("包车") || value.contains("接驳") { return .groundTransport }
        return nil
    }

    private func bookingStatus(_ value: String) -> BookingStatus {
        let value = value.lowercased()
        if value.contains("confirmed") || value.contains("已确认") { return .confirmed }
        if value.contains("required") || value.contains("待确认") { return .needsConfirmation }
        if value.contains("complete") || value.contains("已完成") { return .completed }
        if value.contains("cancel") || value.contains("取消") { return .cancelled }
        return .planned
    }

    private func combine(date: String, time: String, calendar: Calendar) -> Date? {
        guard let day = ContractDate.day(date, calendar: calendar) else { return nil }
        return ContractDate.localTime(parseTimeRange(time).0, on: day, calendar: calendar) ?? day
    }

    private func normalizeBookingKey(_ value: String) -> String {
        value.replacingOccurrences(of: "—", with: "").replacingOccurrences(of: "-", with: "")
            .filter { !$0.isWhitespace }.lowercased()
    }

    private func integer(in value: String) -> Int? { value.matches(#"\d+"#).first.flatMap(Int.init) }
    private func firstValue(_ row: MarkdownRow, keys: [String]) -> String { keys.lazy.map { row.value(for: $0) }.first(where: { !$0.isEmpty }) ?? "" }
    private func firstURL(in value: String?) -> URL? { value?.matches(#"https?://[^\s)>]+"#).first.flatMap(URL.init(string:)) }
    private func firstPhone(in value: String?) -> String? { value?.matches(#"(?:\+?\d[\d -]{6,}\d)"#).first }
    private func parseLatestDeparture(in value: String, date: Date, calendar: Calendar) -> Date? {
        guard value.lowercased().contains("latest safe") || value.contains("最晚") else { return nil }
        return ContractDate.localTime(parseTimeRange(value).0, on: date, calendar: calendar)
    }
    private static func itemMatchKey(_ item: TimelineItemDraft) -> String { item.sourceFingerprint ?? item.id.uuidString }
}

private struct MarkdownDayHeading {
    var raw: String
    var sequence: Int
    var date: String
    var title: String
    var line: Int
}

private struct MarkdownRow {
    var values: [String: String]
    func value(for key: String) -> String { values[MarkdownTable.normalize(key)] ?? "" }
    func value(forAny keys: [String]) -> String { keys.lazy.map { value(for: $0) }.first(where: { !$0.isEmpty }) ?? "" }
}

private struct MarkdownTable {
    var heading2: String
    var heading3: String
    var headers: [String]
    var rows: [MarkdownRow]
    var lineRange: Range<Int>
    func hasColumn(_ value: String) -> Bool { headers.contains(Self.normalize(value)) }
    func hasAnyColumn(_ values: [String]) -> Bool { values.contains { hasColumn($0) } }
    static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "／", with: "/")
    }
}

private struct MarkdownDocument {
    var lines: [String]
    var title: String?
    var metadata: [String: String] = [:]
    var dayHeadings: [MarkdownDayHeading] = []
    var tables: [MarkdownTable] = []

    init(_ source: String) {
        lines = source.components(separatedBy: "\n")
        var heading2 = ""
        var heading3 = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("# "), title == nil { title = String(line.dropFirst(2)) }
            if line.hasPrefix("## ") {
                heading2 = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                heading3 = ""
                if let day = Self.dayHeading(heading2, line: index, fallback: dayHeadings.count + 1) { dayHeadings.append(day) }
            } else if line.hasPrefix("### ") {
                heading3 = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix(">") {
                let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if let colon = content.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                    let key = MarkdownTable.normalize(String(content[..<colon]))
                    let value = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    metadata[key] = value
                }
            }
            if Self.isTableHeader(line), index + 1 < lines.count, Self.isSeparator(lines[index + 1]) {
                let headers = Self.cells(line).map(MarkdownTable.normalize)
                let start = index
                index += 2
                var rows: [MarkdownRow] = []
                while index < lines.count, Self.isTableHeader(lines[index]) {
                    let cells = Self.cells(lines[index])
                    var values: [String: String] = [:]
                    for (column, header) in headers.enumerated() where column < cells.count { values[header] = cells[column] }
                    rows.append(.init(values: values))
                    index += 1
                }
                tables.append(.init(heading2: heading2, heading3: heading3, headers: headers, rows: rows, lineRange: start..<index))
                continue
            }
            index += 1
        }
    }

    func checklistItems(inSections sections: [String]) -> [String] {
        var active = false
        var result: [String] = []
        for line in lines {
            if line.hasPrefix("## ") {
                let heading = MarkdownTable.normalize(String(line.dropFirst(3)))
                active = sections.contains { heading.contains(MarkdownTable.normalize($0)) }
            }
            if active, line.range(of: #"^\s*-\s*\[[ xX]\]\s+"#, options: .regularExpression) != nil {
                result.append(line.replacingOccurrences(of: #"^\s*-\s*\[[ xX]\]\s+"#, with: "", options: .regularExpression))
            }
        }
        return result
    }

    func bulletItems(inSections sections: [String]) -> [String] {
        var active = false
        var result: [String] = []
        for line in lines {
            if line.hasPrefix("## ") {
                let heading = MarkdownTable.normalize(String(line.dropFirst(3)))
                active = sections.contains { heading.contains(MarkdownTable.normalize($0)) }
            } else if active, line.range(of: #"^\s*-\s+(?!\[).+"#, options: .regularExpression) != nil {
                result.append(line.replacingOccurrences(of: #"^\s*-\s+"#, with: "", options: .regularExpression))
            }
        }
        return result
    }

    func unrecognizedSections(excluding linesToSkip: Set<Int>) -> [SourceFragment] {
        var result: [SourceFragment] = []
        var heading: String?
        var content: [String] = []
        func append() {
            let text = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.init(heading: heading, content: text)) }
        }
        for (index, line) in lines.enumerated() {
            if linesToSkip.contains(index) { continue }
            if line.hasPrefix("## ") { append(); heading = String(line.dropFirst(3)); content = [] }
            else if heading != nil, !line.hasPrefix("# "), !line.hasPrefix(">") { content.append(line) }
        }
        append()
        return result
    }

    private static func dayHeading(_ value: String, line: Int, fallback: Int) -> MarkdownDayHeading? {
        let isoDate = value.matches(#"\d{4}-\d{2}-\d{2}"#).first
        let chineseDate = value.matches(#"\d{1,2}月\d{1,2}日"#).first.map {
            $0.replacingOccurrences(of: "月", with: "-").replacingOccurrences(of: "日", with: "")
        }
        guard let date = isoDate ?? chineseDate else { return nil }
        let lower = value.lowercased()
        guard lower.contains("day") || value.contains("第") || value.contains("日") else { return nil }
        let number = lower.matches(#"day\s*(\d+)"#).first?.matches(#"\d+"#).first.flatMap(Int.init) ?? fallback
        let title = value.components(separatedBy: "—").last?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Day \(number)"
        return .init(raw: value, sequence: number, date: date, title: title, line: line)
    }

    private static func isTableHeader(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
    private static func isSeparator(_ line: String) -> Bool { line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces).isEmpty }
    private static func cells(_ line: String) -> [String] {
        line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private enum StableID {
    static func make(_ value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        let bytes = Array(digest.prefix(16))
        let string = String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", arguments: bytes.map { $0 as CVarArg })
        return UUID(uuidString: string) ?? UUID()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var dashToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || ["—", "-", "–"].contains(trimmed) ? nil : trimmed
    }
    func matches(_ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { Range($0.range, in: self).map { String(self[$0]) } }
    }
}
