import SwiftUI

/// The look-back reading surface. Entries are organized by week, not as one long date list: the
/// sidebar is a spine of weeks you expand into their days. Selecting a week reads its over-time
/// mirror; selecting a day reads that day's entry. Restrained on purpose — the writing front and center.
struct LookBackView: View {
    @State private var days: [JournalDay] = []
    @State private var mirrors: [JournalMirror] = []
    @State private var sentiment: [SentimentPoint] = []
    @State private var selection: Selection?

    enum Selection: Equatable { case day(String), week(String) }

    /// A week in the spine: its date-range label, the mirror covering it (if any), and its days.
    struct WeekSection: Identifiable {
        let id: String
        let label: String
        let mirror: JournalMirror?
        let days: [JournalDay]
        let sortKey: String
    }

    var body: some View {
        Group {
            if days.isEmpty && mirrors.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 300)
                    Divider()
                    detail
                }
            }
        }
        .frame(minWidth: 580, minHeight: 520)
        .onAppear(perform: reload)
    }

    // MARK: - Sidebar spine

    private var sidebar: some View {
        VStack(spacing: 0) {
            if !sentiment.isEmpty {
                Sparkline(points: sentiment, selected: selectedDayDate)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sections) { sec in
                        weekHeader(sec)
                        if expandedId == sec.id {
                            ForEach(sec.days) { dayRow($0) }
                                .padding(.bottom, 6)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func weekHeader(_ sec: WeekSection) -> some View {
        let on = isWeekSelected(sec.id)
        return HStack(spacing: 8) {
            Image(systemName: expandedId == sec.id ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Text(sec.label)
                .font(.system(.callout, design: .serif).weight(.medium))
                .foregroundStyle(on ? Color.primary : Color.secondary)
            Spacer()
            if sec.mirror != nil {
                Image(systemName: "circle.hexagongrid")
                    .font(.caption2)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(on ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectWeek(sec) }
    }

    private func dayRow(_ day: JournalDay) -> some View {
        let on = selectedDayDate == day.date
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.dayNum(day.date))
                .font(.callout.weight(.medium))
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(day.subject ?? Self.monthDay(day.date))
                .font(.system(.callout, design: .serif))
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6).padding(.leading, 34).padding(.trailing, 16)
        .background(on ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = .day(day.date) }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        ScrollView {
            Group {
                if case .week = selection { mirrorDetail } else { entryDetail }
            }
            .padding(28)
        }
    }

    private var entryDetail: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let day = selectedDay {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Self.longDate(day.date))
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .fixedSize()
                    if let s = day.subject, !s.isEmpty {
                        Text(s)
                            .font(.system(.subheadline, design: .serif).italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 14)
                JournalText(text: day.body)
                if let m = mirrorForSelected {
                    Divider().padding(.vertical, 4)
                    DisclosureGroup {
                        JournalText(text: m.body).padding(.top, 10)
                    } label: {
                        Label("This week's mirror — \(Self.range(m))", systemImage: "circle.hexagongrid")
                            .font(.callout.weight(.medium))
                    }
                }
            } else {
                Text("Pick a day.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var mirrorDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let m = selectedMirror {
                Text(Self.range(m))
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .padding(.top, 40)
                    .padding(.bottom, 14)
                JournalText(text: m.body)
            } else {
                Text("No mirror for this week yet.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
            Text("No entries yet").font(.headline)
            Text("Your first entry writes itself tonight at 5am.")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

    /// Bucket days into weeks. A day joins the mirror that covers it; days no mirror covers fall into
    /// their own calendar-week bucket, so every entry still has a home.
    private var sections: [WeekSection] {
        var byKey: [String: [JournalDay]] = [:]
        var meta: [String: (mirror: JournalMirror?, sort: String)] = [:]
        for day in days {
            if let m = mirrors.first(where: { $0.covers(day.date) }) {
                byKey[m.id, default: []].append(day)
                meta[m.id] = (m, m.start)
            } else {
                let b = Self.weekBucket(day.date)
                byKey[b.key, default: []].append(day)
                meta[b.key] = (nil, b.start)
            }
        }
        return byKey.map { key, ds in
            let sorted = ds.sorted { $0.date > $1.date }
            let mirror = meta[key]!.mirror
            // Mirror weeks show the mirror's range; bucketed weeks show the days they actually hold,
            // so a half-covered week (e.g. a mirror through the 12th + a loose 13th) doesn't read as a
            // duplicate of the mirror's span.
            let label: String
            if let m = mirror {
                label = Self.range(m)
            } else if let lo = sorted.last?.date, let hi = sorted.first?.date {
                label = lo == hi ? Self.monthDay(lo) : "\(Self.monthDay(lo)) – \(Self.monthDay(hi))"
            } else {
                label = ""
            }
            return WeekSection(id: key, label: label, mirror: mirror, days: sorted, sortKey: meta[key]!.sort)
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    private var expandedId: String? {
        switch selection {
        case .week(let w): return w
        case .day(let d): return sections.first { $0.days.contains { $0.date == d } }?.id
        case nil: return sections.first?.id
        }
    }

    private func isWeekSelected(_ id: String) -> Bool {
        if case .week(let w) = selection { return w == id }
        return false
    }

    private func selectWeek(_ sec: WeekSection) {
        if sec.mirror != nil {
            selection = .week(sec.id)
        } else if let latest = sec.days.first {
            selection = .day(latest.date)   // no mirror to read — just open the week
        }
    }

    // MARK: - Data

    private var selectedDayDate: String? {
        if case .day(let d) = selection { return d }
        return nil
    }
    private var selectedDay: JournalDay? {
        guard let d = selectedDayDate else { return nil }
        return days.first { $0.date == d }
    }
    private var selectedMirror: JournalMirror? {
        if case .week(let w) = selection { return mirrors.first { $0.id == w } }
        return nil
    }
    private var mirrorForSelected: JournalMirror? {
        guard let d = selectedDayDate else { return nil }
        return mirrors.first { $0.covers(d) }
    }

    private func reload() {
        days = JournalStore.loadDays()
        mirrors = JournalStore.loadMirrors()
        sentiment = SentimentStore.load()
        if selection == nil, let first = days.first?.date { selection = .day(first) }
    }

    // MARK: - Date formatting

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
    private static func fmt(_ s: String, _ pattern: String) -> String {
        guard let d = parse(s) else { return s }
        let f = DateFormatter(); f.dateFormat = pattern; return f.string(from: d)
    }

    /// Monday-based calendar-week bucket key (+ sortable start) for a day with no covering mirror.
    private static func weekBucket(_ s: String) -> (key: String, start: String) {
        guard let d = parse(s) else { return (s, s) }
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2   // Monday
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        let key = String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
        let start = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        return (key, iso.string(from: start))
    }

    private static func dayNum(_ s: String) -> String { fmt(s, "d") }
    static func longDate(_ s: String) -> String { fmt(s, "EEEE, MMMM d") }
    static func monthDay(_ s: String) -> String { fmt(s, "MMM d") }
    static func range(_ m: JournalMirror) -> String { "\(fmt(m.start, "MMM d")) – \(fmt(m.end, "MMM d"))" }
}
