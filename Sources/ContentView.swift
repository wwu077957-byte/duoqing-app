import SwiftUI

let goldColor = Color(red: 176.0 / 255, green: 141.0 / 255, blue: 62.0 / 255)
private let inkColor = Color(red: 43.0 / 255, green: 38.0 / 255, blue: 32.0 / 255)
private let paperColor = Color(red: 251.0 / 255, green: 249.0 / 255, blue: 244.0 / 255)

// MARK: - Model

struct DayEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var date: Date
    var repeatsYearly: Bool = false
    var isPinned: Bool = false
}

// MARK: - Date math

enum DayMath {
    static var calendar: Calendar { Calendar.current }

    static func startOfDay(_ d: Date) -> Date { calendar.startOfDay(for: d) }

    static func daysFromToday(to target: Date) -> Int {
        let today = startOfDay(Date())
        return calendar.dateComponents([.day], from: today, to: startOfDay(target)).day ?? 0
    }

    /// Yearly events roll to this year's date, or next year's once passed.
    static func effectiveDate(for event: DayEvent) -> Date {
        guard event.repeatsYearly else { return startOfDay(event.date) }
        let today = startOfDay(Date())
        let comps = calendar.dateComponents([.month, .day], from: event.date)
        var dc = DateComponents()
        dc.month = comps.month
        dc.day = comps.day
        dc.year = calendar.component(.year, from: today)
        if let thisYear = calendar.date(from: dc), startOfDay(thisYear) >= today {
            return startOfDay(thisYear)
        }
        dc.year = calendar.component(.year, from: today) + 1
        if let nextYear = calendar.date(from: dc) {
            return startOfDay(nextYear)
        }
        return startOfDay(event.date)
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: d)
    }

    static func weekdayText(_ d: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let wd = calendar.component(.weekday, from: d)
        return names[(wd - 1 + 7) % 7]
    }
}

// MARK: - Store

final class EventStore: ObservableObject {
    @Published var events: [DayEvent] = [] {
        didSet { save() }
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("day-events.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([DayEvent].self, from: data) {
            events = decoded
        } else {
            events = Self.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    func upsert(_ event: DayEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = event
        } else {
            events.append(event)
        }
    }

    func remove(_ event: DayEvent) {
        events.removeAll { $0.id == event.id }
    }

    var sortedEvents: [DayEvent] {
        events.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            let da = DayMath.daysFromToday(to: DayMath.effectiveDate(for: a))
            let db = DayMath.daysFromToday(to: DayMath.effectiveDate(for: b))
            if (da >= 0) != (db >= 0) { return da >= 0 }
            return da >= 0 ? da < db : da > db
        }
    }

    var featured: DayEvent? {
        sortedEvents.first { DayMath.daysFromToday(to: DayMath.effectiveDate(for: $0)) >= 0 } ?? sortedEvents.first
    }

    static var defaults: [DayEvent] {
        func make(_ title: String, _ y: Int, _ m: Int, _ d: Int, yearly: Bool = false, pinned: Bool = false) -> DayEvent {
            var dc = DateComponents()
            dc.year = y
            dc.month = m
            dc.day = d
            let date = Calendar.current.date(from: dc) ?? Date()
            return DayEvent(title: title, date: date, repeatsYearly: yearly, isPinned: pinned)
        }
        return [
            make("我的生日", 2010, 1, 31, yearly: true, pinned: true),
            make("春节 · 大年初一", 2027, 2, 6),
            make("黑色星期五", 2026, 11, 27),
            make("宝可梦机场到期", 2026, 12, 1),
            make("服务器 1 到期", 2027, 11, 8),
        ]
    }
}

// MARK: - Main screen

struct ContentView: View {
    @EnvironmentObject var store: EventStore
    @State private var editingEvent: DayEvent? = nil
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let f = store.featured {
                            FeaturedCard(event: f)
                                .onTapGesture { editingEvent = f }
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(store.sortedEvents) { event in
                                EventRow(event: event)
                                    .onTapGesture { editingEvent = event }
                                    .contextMenu {
                                        Button {
                                            var e = event
                                            e.isPinned.toggle()
                                            store.upsert(e)
                                        } label: {
                                            Label(event.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                                        }
                                        Button(role: .destructive) {
                                            store.remove(event)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        if store.events.isEmpty {
                            Text("还没有日子，点右上角 + 添加第一个吧")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("多情倒数日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(goldColor)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                EventEditor(event: DayEvent(title: "", date: Date())) { store.upsert($0) }
            }
            .sheet(item: $editingEvent) { event in
                EventEditor(event: event) { store.upsert($0) }
            }
        }
    }
}

// MARK: - Cards

struct FeaturedCard: View {
    let event: DayEvent

    var body: some View {
        let eff = DayMath.effectiveDate(for: event)
        let diff = DayMath.daysFromToday(to: eff)
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                if event.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(goldColor)
                }
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(inkColor)
            }
            if diff == 0 {
                Text("今天")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
                Text("就是今天，好好过")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(diff > 0 ? "还有" : "已经")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(abs(diff))")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(goldColor)
                    Text("天")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Text("\(DayMath.dateText(eff)) · \(DayMath.weekdayText(eff))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct EventRow: View {
    let event: DayEvent

    var body: some View {
        let eff = DayMath.effectiveDate(for: event)
        let diff = DayMath.daysFromToday(to: eff)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if event.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(goldColor)
                    }
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(inkColor)
                }
                HStack(spacing: 6) {
                    Text(DayMath.dateText(eff))
                    Text(DayMath.weekdayText(eff))
                    if event.repeatsYearly {
                        Text("每年")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(goldColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(goldColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            if diff == 0 {
                Text("今天")
                    .font(.title2.weight(.bold))
                    .foregroundColor(goldColor)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(abs(diff))")
                            .font(.title2.weight(.bold))
                            .foregroundColor(goldColor)
                        Text("天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(diff > 0 ? "还有" : "已经")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Editor

struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: DayEvent
    private let onSave: (DayEvent) -> Void

    init(event: DayEvent, onSave: @escaping (DayEvent) -> Void) {
        _event = State(initialValue: event)
        self.onSave = onSave
    }

    private var trimmedTitle: String {
        event.title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日子") {
                    TextField("比如：生日、出门旅行…", text: $event.title)
                    DatePicker("日期", selection: $event.date, displayedComponents: .date)
                }
                Section("选项") {
                    Toggle("每年重复（生日、纪念日）", isOn: $event.repeatsYearly)
                    Toggle("置顶", isOn: $event.isPinned)
                }
                Section {
                    let eff = DayMath.effectiveDate(for: event)
                    let diff = DayMath.daysFromToday(to: eff)
                    if diff == 0 {
                        Text("就是今天")
                    } else if diff > 0 {
                        Text("还有 \(diff) 天 · \(DayMath.dateText(eff)) \(DayMath.weekdayText(eff))")
                    } else {
                        Text("已经 \(-diff) 天 · \(DayMath.dateText(eff)) \(DayMath.weekdayText(eff))")
                    }
                } header: {
                    Text("预览")
                }
            }
            .navigationTitle(trimmedTitle.isEmpty ? "新日子" : "编辑日子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var e = event
                        e.title = trimmedTitle
                        onSave(e)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }
}
