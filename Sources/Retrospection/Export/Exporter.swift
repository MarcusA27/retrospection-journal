import Foundation

/// Renders a single day into one clean, app-grouped, timestamped text document — the v0 bridge for
/// testing distillation by hand. Times are rendered in the timezone the day was captured in, so an
/// exported day reads correctly regardless of where it is later opened.
struct Exporter {
    let store: Store

    /// Returns the rendered document, or nil if the day has no entries.
    func exportText(for logicalDate: String) throws -> String? {
        guard let day = try store.day(logicalDate) else { return nil }
        let entries = try store.entries(for: logicalDate)
        guard !entries.isEmpty else { return nil }

        let tz = TimeZone(identifier: day.timezoneIdentifier) ?? .current
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = tz
        clock.dateFormat = "HH:mm"
        func hm(_ utc: Double) -> String { clock.string(from: Date(timeIntervalSince1970: utc)) }

        var out = ""
        out += "Retrospection — \(logicalDate) (\(day.timezoneIdentifier))\n"
        out += "Captured \(hm(day.startUTC))–\(hm(day.endUTC)) local\n"
        out += String(repeating: "=", count: 56) + "\n\n"

        // Group by app, preserving the order each app first appears in the day.
        var order: [String] = []
        var byApp: [String: [Entry]] = [:]
        for entry in entries {
            if byApp[entry.appName] == nil { order.append(entry.appName) }
            byApp[entry.appName, default: []].append(entry)
        }

        for app in order {
            out += "## \(app)\n\n"
            for entry in byApp[app] ?? [] {
                let title = entry.windowTitle ?? "—"
                out += "[\(hm(entry.startUTC))–\(hm(entry.endUTC))] \(title)\n"
                out += entry.text + "\n\n"
            }
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
