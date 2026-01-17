//
//  ContentView.swift
//  LiveSalary
//
//  Created by jiquanbai on 2026/1/16.
//

import AppKit
import Combine
import Foundation
import SwiftUI

enum SalaryStatus: String {
    case noSet = "noSet"
    case stop = "Rest"
    case working = "Working"
    case paused = "Paused"

    var displayName: String {
        switch self {
        case .noSet:
            return "noSet"
        case .stop:
            return "Rest"
        case .working:
            return "Working"
        case .paused:
            return "Paused"
        }
    }
}

struct SalarySnapshot {
    let status: SalaryStatus
    let todayEarned: Double?
    let monthAccumulated: Double?
    let workdaysElapsed: Int?
    let workdayCount: Int?
    let todayWorkedHours: Double?
    let totalWorkHours: Double?
    let daysInMonth: Int?
}

struct SalaryCalculator {
    static func snapshot(
        now: Date,
        monthSalary: Double,
        nonWorkDays: Set<Int>,
        monthSalarySet: Bool,
        nonWorkDaysSet: Bool,
        startSeconds: Double,
        endSeconds: Double,
        calendar: Calendar
    ) -> SalarySnapshot {
        let hasConfig = monthSalarySet && nonWorkDaysSet
        guard hasConfig else {
            return SalarySnapshot(
                status: .noSet,
                todayEarned: nil,
                monthAccumulated: nil,
                workdaysElapsed: nil,
                workdayCount: nil,
                todayWorkedHours: nil,
                totalWorkHours: nil,
                daysInMonth: nil
            )
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 0
        let workdayCount = max(daysInMonth - nonWorkDays.count, 0)
        let dailyPay = workdayCount > 0 ? monthSalary / Double(workdayCount) : 0
        let totalWorkSeconds = max(endSeconds - startSeconds, 0)
        let totalWorkHours = totalWorkSeconds / 3600.0

        let startOfDay = calendar.startOfDay(for: now)
        let startTime = startOfDay.addingTimeInterval(startSeconds)
        let endTime = startOfDay.addingTimeInterval(endSeconds)
        let todayDay = calendar.component(.day, from: now)
        let isNonWorkDay = nonWorkDays.contains(todayDay)

        let status: SalaryStatus
        let todayEarned: Double
        let todayWorkedHours: Double

        if isNonWorkDay {
            status = .stop
            todayEarned = 0
            todayWorkedHours = 0
        } else if now >= startTime && now < endTime {
            status = .working
            let elapsedSeconds = max(0, min(now.timeIntervalSince(startTime), totalWorkSeconds))
            todayEarned = totalWorkSeconds > 0 ? dailyPay * (elapsedSeconds / totalWorkSeconds) : 0
            todayWorkedHours = elapsedSeconds / 3600.0
        } else {
            status = .paused
            if now < startTime {
                todayEarned = 0
                todayWorkedHours = 0
            } else {
                todayEarned = dailyPay
                todayWorkedHours = totalWorkHours
            }
        }

        let workdaysElapsed = countWorkdaysElapsed(today: todayDay, nonWorkDays: nonWorkDays)
        let monthAccumulated = accumulatedPay(
            today: todayDay,
            isNonWorkDay: isNonWorkDay,
            dailyPay: dailyPay,
            todayEarned: todayEarned,
            nonWorkDays: nonWorkDays
        )

        return SalarySnapshot(
            status: status,
            todayEarned: todayEarned,
            monthAccumulated: monthAccumulated,
            workdaysElapsed: workdaysElapsed,
            workdayCount: workdayCount,
            todayWorkedHours: todayWorkedHours,
            totalWorkHours: totalWorkHours,
            daysInMonth: daysInMonth
        )
    }

    private static func countWorkdaysElapsed(today: Int, nonWorkDays: Set<Int>) -> Int {
        guard today > 0 else { return 0 }
        var count = 0
        for day in 1...today where !nonWorkDays.contains(day) {
            count += 1
        }
        return count
    }

    private static func accumulatedPay(
        today: Int,
        isNonWorkDay: Bool,
        dailyPay: Double,
        todayEarned: Double,
        nonWorkDays: Set<Int>
    ) -> Double {
        guard today > 0 else { return 0 }
        var total = 0.0
        if today > 1 {
            for day in 1..<(today) where !nonWorkDays.contains(day) {
                total += dailyPay
            }
        }
        if !isNonWorkDay {
            total += todayEarned
        }
        return total
    }
}

enum SalaryFormatting {
    static let yenSymbol = "\u{00A5}"
    static let formatLocale = Locale(identifier: "en_US_POSIX")

    static func money(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%@%.2f", locale: formatLocale, yenSymbol, value)
    }

    static func workdayCount(elapsed: Int?, total: Int?) -> String {
        guard let elapsed, let total else { return "--" }
        return "\(elapsed)/\(total)"
    }

    static func hoursRatio(elapsed: Double?, total: Double?) -> String {
        guard let elapsed, let total else { return "--" }
        return String(format: "%.1f/%.1f", locale: formatLocale, elapsed, total)
    }

    static func hours(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", locale: formatLocale, value)
    }

    static func timeString(seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    static func timeRange(startSeconds: Double, endSeconds: Double) -> String {
        "\(timeString(seconds: startSeconds))-\(timeString(seconds: endSeconds))"
    }
}

final class SalaryStore: ObservableObject {
    private enum Keys {
        static let monthKey = "monthKey"
        static let monthSalary = "monthSalary"
        static let monthSalarySet = "monthSalarySet"
        static let nonWorkDays = "nonWorkDays"
        static let nonWorkDaysSet = "nonWorkDaysSet"
        static let startSeconds = "startSeconds"
        static let endSeconds = "endSeconds"
        static let refreshInterval = "refreshInterval"
    }

    static let defaultStartSeconds = 9.0 * 3600.0
    static let defaultEndSeconds = 18.0 * 3600.0
    static let defaultRefreshInterval = 1.0

    @Published var now: Date
    @Published private(set) var monthSalary: Double
    @Published private(set) var nonWorkDays: Set<Int>
    @Published private(set) var monthSalarySet: Bool
    @Published private(set) var nonWorkDaysSet: Bool
    @Published private(set) var monthKey: String

    @Published var startSeconds: Double {
        didSet { persistStartSeconds() }
    }
    @Published var endSeconds: Double {
        didSet { persistEndSeconds() }
    }
    @Published var refreshInterval: Double {
        didSet {
            persistRefreshInterval()
            restartTimer()
        }
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var timer: Timer?
    weak var mainWindow: NSWindow?

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = Date()

        self.monthKey = defaults.string(forKey: Keys.monthKey) ?? ""
        self.monthSalary = defaults.double(forKey: Keys.monthSalary)
        self.monthSalarySet = defaults.bool(forKey: Keys.monthSalarySet)

        let daysArray = defaults.array(forKey: Keys.nonWorkDays) as? [Int] ?? []
        self.nonWorkDays = Set(daysArray)
        self.nonWorkDaysSet = defaults.bool(forKey: Keys.nonWorkDaysSet)

        self.startSeconds = Self.loadDouble(
            defaults: defaults,
            key: Keys.startSeconds,
            fallback: Self.defaultStartSeconds
        )
        self.endSeconds = Self.loadDouble(
            defaults: defaults,
            key: Keys.endSeconds,
            fallback: Self.defaultEndSeconds
        )
        self.refreshInterval = Self.loadDouble(
            defaults: defaults,
            key: Keys.refreshInterval,
            fallback: Self.defaultRefreshInterval
        )

        checkMonthRollover(for: now)
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    var snapshot: SalarySnapshot {
        SalaryCalculator.snapshot(
            now: now,
            monthSalary: monthSalary,
            nonWorkDays: nonWorkDays,
            monthSalarySet: monthSalarySet,
            nonWorkDaysSet: nonWorkDaysSet,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            calendar: calendar
        )
    }

    var isConfigured: Bool {
        monthSalarySet && nonWorkDaysSet
    }

    var menuBarTitle: String {
        let snapshot = snapshot
        switch snapshot.status {
        case .noSet:
            return "noSet"
        case .stop:
            // Menu bar shows "Rest" (not a currency value) on non-work days for consistency.
            return "Rest"
        case .working, .paused:
            return SalaryFormatting.money(snapshot.todayEarned)
        }
    }

    func setMonthSalary(_ value: Double) {
        monthSalary = value
        monthSalarySet = true
        monthKey = currentMonthKey(for: now)
        persistMonthSalary()
    }

    func setNonWorkDays(_ days: Set<Int>) {
        nonWorkDays = days
        nonWorkDaysSet = true
        monthKey = currentMonthKey(for: now)
        persistNonWorkDays()
    }

    func timeDate(forSeconds seconds: Double) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        return startOfDay.addingTimeInterval(seconds)
    }

    func secondsSinceStartOfDay(_ date: Date) -> Double {
        let startOfDay = calendar.startOfDay(for: date)
        return date.timeIntervalSince(startOfDay)
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = max(0.1, refreshInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = Date()
            self.now = current
            self.checkMonthRollover(for: current)
        }
    }

    private func restartTimer() {
        startTimer()
    }

    private func checkMonthRollover(for date: Date) {
        let currentKey = currentMonthKey(for: date)
        if monthKey != currentKey {
            monthKey = currentKey
            monthSalary = 0
            nonWorkDays = []
            monthSalarySet = false
            nonWorkDaysSet = false
            persistMonthReset()
        }
    }

    private func currentMonthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private static func loadDouble(defaults: UserDefaults, key: String, fallback: Double) -> Double {
        if defaults.object(forKey: key) == nil {
            return fallback
        }
        return defaults.double(forKey: key)
    }

    private func persistMonthSalary() {
        defaults.set(monthKey, forKey: Keys.monthKey)
        defaults.set(monthSalary, forKey: Keys.monthSalary)
        defaults.set(monthSalarySet, forKey: Keys.monthSalarySet)
    }

    private func persistNonWorkDays() {
        defaults.set(monthKey, forKey: Keys.monthKey)
        defaults.set(Array(nonWorkDays), forKey: Keys.nonWorkDays)
        defaults.set(nonWorkDaysSet, forKey: Keys.nonWorkDaysSet)
    }

    private func persistMonthReset() {
        defaults.set(monthKey, forKey: Keys.monthKey)
        defaults.set(monthSalary, forKey: Keys.monthSalary)
        defaults.set(monthSalarySet, forKey: Keys.monthSalarySet)
        defaults.set(Array(nonWorkDays), forKey: Keys.nonWorkDays)
        defaults.set(nonWorkDaysSet, forKey: Keys.nonWorkDaysSet)
    }

    private func persistStartSeconds() {
        defaults.set(startSeconds, forKey: Keys.startSeconds)
    }

    private func persistEndSeconds() {
        defaults.set(endSeconds, forKey: Keys.endSeconds)
    }

    private func persistRefreshInterval() {
        defaults.set(refreshInterval, forKey: Keys.refreshInterval)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case info
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .info:
            return "chart.line.uptrend.xyaxis"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .info
    @EnvironmentObject private var store: SalaryStore

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .info {
                    case .info:
                        InfoView()
                    case .settings:
                        SettingsView()
                    }
                }
                .navigationTitle((selection ?? .info).title)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
        .background(WindowAccessor { window in
            if let window {
                if window.identifier == nil {
                    window.identifier = NSUserInterfaceItemIdentifier("main")
                }
                store.mainWindow = window
            }
        })
    }
}

struct InfoView: View {
    @EnvironmentObject private var store: SalaryStore

    private var snapshot: SalarySnapshot {
        store.snapshot
    }

    private var todayDisplay: String {
        snapshot.status == .noSet ? "noSet" : SalaryFormatting.money(snapshot.todayEarned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoCard(title: "Today") {
                    HStack(spacing: 8) {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        StatusBadge(status: snapshot.status)
                        Spacer(minLength: 0)
                    }
                    Text(todayDisplay)
                        .font(.system(size: 32, weight: .semibold))
                        .monospacedDigit()
                    KeyValueRow(
                        key: "Hours",
                        value: SalaryFormatting.hoursRatio(elapsed: snapshot.todayWorkedHours, total: snapshot.totalWorkHours)
                    )
                }

                InfoCard(title: "Month") {
                    Text(SalaryFormatting.money(snapshot.monthAccumulated))
                        .font(.title2)
                        .monospacedDigit()
                    KeyValueRow(
                        key: "Workdays",
                        value: SalaryFormatting.workdayCount(elapsed: snapshot.workdaysElapsed, total: snapshot.workdayCount)
                    )
                }

                InfoCard(title: "Config Snapshot") {
                    KeyValueRow(
                        key: "Monthly Salary",
                        value: store.monthSalarySet ? SalaryFormatting.money(store.monthSalary) : "--"
                    )
                    KeyValueRow(
                        key: "Non-work Days",
                        value: store.nonWorkDaysSet ? "\(store.nonWorkDays.count)" : "--"
                    )
                    KeyValueRow(
                        key: "Work Time",
                        value: SalaryFormatting.timeRange(startSeconds: store.startSeconds, endSeconds: store.endSeconds)
                    )
                    KeyValueRow(
                        key: "Refresh Interval",
                        value: String(format: "%.1f s", locale: SalaryFormatting.formatLocale, store.refreshInterval)
                    )
                }
            }
            .padding(16)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SalaryStore
    @State private var monthSalaryText = ""
    @FocusState private var salaryFocused: Bool

    private var nonWorkDaysBinding: Binding<Set<Int>> {
        Binding(
            get: { store.nonWorkDays },
            set: { store.setNonWorkDays($0) }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { store.timeDate(forSeconds: store.startSeconds) },
            set: { store.startSeconds = store.secondsSinceStartOfDay($0) }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: { store.timeDate(forSeconds: store.endSeconds) },
            set: { store.endSeconds = store.secondsSinceStartOfDay($0) }
        )
    }

    private var refreshBinding: Binding<Double> {
        Binding(
            get: { store.refreshInterval },
            set: { store.refreshInterval = max(0.1, $0) }
        )
    }

    private var currentMonthDate: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: store.now)
        return calendar.date(from: components) ?? store.now
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionCard(title: "Month Configuration") {
                    LabeledContent("Monthly Salary") {
                        HStack(spacing: 6) {
                            Text(SalaryFormatting.yenSymbol)
                            TextField("", text: $monthSalaryText)
                                .frame(width: 140)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($salaryFocused)
                                .onChange(of: monthSalaryText) { _, newValue in
                                    if let value = parseSalaryText(newValue) {
                                        store.setMonthSalary(value)
                                    }
                                }
                                .onChange(of: salaryFocused) { _, focused in
                                    if !focused {
                                        syncSalaryText()
                                    }
                                }
                        }
                    }
                    LabeledContent("Refresh Interval") {
                        TextField("", value: refreshBinding, format: .number.precision(.fractionLength(1)))
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Work Time") {
                        HStack(spacing: 8) {
                            DatePicker("Start", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("to")
                                .foregroundStyle(.secondary)
                            DatePicker("End", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }

                SettingsSectionCard(title: "Non-work Days") {
                    MonthCalendarView(monthDate: currentMonthDate, selection: nonWorkDaysBinding)
                }

                Text("Changes apply immediately. When month changes, set monthly salary and non-work days again; otherwise status becomes noSet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .onAppear {
            syncSalaryText()
        }
        .onChange(of: store.monthSalary) { _, _ in
            if !salaryFocused {
                syncSalaryText()
            }
        }
        .onChange(of: store.monthSalarySet) { _, _ in
            if !salaryFocused {
                syncSalaryText()
            }
        }
    }

    private func syncSalaryText() {
        if store.monthSalarySet {
            monthSalaryText = String(format: "%.2f", locale: SalaryFormatting.formatLocale, store.monthSalary)
        } else {
            monthSalaryText = ""
        }
    }

    private func parseSalaryText(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

struct MonthCalendarView: View {
    let monthDate: Date
    @Binding var selection: Set<Int>

    private let calendar: Calendar

    init(monthDate: Date, selection: Binding<Set<Int>>, calendar: Calendar = .current) {
        self.monthDate = monthDate
        self._selection = selection
        self.calendar = calendar
    }

    private var year: Int {
        calendar.component(.year, from: monthDate)
    }

    private var month: Int {
        calendar.component(.month, from: monthDate)
    }

    private var monthTitle: String {
        String(format: "%04d-%02d", year, month)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 0
    }

    private var firstWeekdayOffset: Int {
        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstDay = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let base = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let startIndex = (calendar.firstWeekday - 1 + base.count) % base.count
        var ordered: [String] = []
        ordered.reserveCapacity(base.count)
        for index in 0..<base.count {
            ordered.append(base[(startIndex + index) % base.count])
        }
        return ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle)
                .font(.headline)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<rowCount, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if let day = dayCells[index] {
                                Button {
                                    toggle(day)
                                } label: {
                                    Text("\(day)")
                                        .frame(maxWidth: .infinity, minHeight: 22)
                                        .background(selection.contains(day) ? Color.accentColor.opacity(0.2) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(height: 22)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ day: Int) {
        var updated = selection
        if updated.contains(day) {
            updated.remove(day)
        } else {
            updated.insert(day)
        }
        selection = updated
    }

    private var dayCells: [Int?] {
        let total = ((firstWeekdayOffset + daysInMonth + 6) / 7) * 7
        return (0..<total).map { index in
            let day = index - firstWeekdayOffset + 1
            return (1...daysInMonth).contains(day) ? day : nil
        }
    }

    private var rowCount: Int {
        max(dayCells.count / 7, 1)
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var store: SalaryStore

    var body: some View {
        Text(store.menuBarTitle)
            .monospacedDigit()
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var store: SalaryStore
    @Environment(\.openWindow) private var openWindow

    private var snapshot: SalarySnapshot {
        store.snapshot
    }

    var body: some View {
        PopoverContentView(
            snapshot: snapshot,
            settingsAction: showMainWindow,
            quitAction: { NSApp.terminate(nil) }
        )
    }

    private func showMainWindow() {
        if let window = resolvedMainWindow() {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = resolvedMainWindow() {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func resolvedMainWindow() -> NSWindow? {
        if let window = store.mainWindow {
            return window
        }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            store.mainWindow = window
            return window
        }
        return nil
    }
}

struct PopoverContentView: View {
    let snapshot: SalarySnapshot
    let settingsAction: () -> Void
    let quitAction: () -> Void

    private var todayDisplay: String {
        snapshot.status == .noSet ? "noSet" : SalaryFormatting.money(snapshot.todayEarned)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("LiveSalary")
                    .font(.headline)
                Spacer(minLength: 8)
                StatusBadge(status: snapshot.status)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(todayDisplay)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                if snapshot.status == .working {
                    Text("Realtime")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            KeyValueRow(key: "Month Accumulated", value: SalaryFormatting.money(snapshot.monthAccumulated))
            KeyValueRow(
                key: "Workdays",
                value: SalaryFormatting.workdayCount(elapsed: snapshot.workdaysElapsed, total: snapshot.workdayCount)
            )
            KeyValueRow(
                key: "Hours",
                value: SalaryFormatting.hoursRatio(elapsed: snapshot.todayWorkedHours, total: snapshot.totalWorkHours)
            )

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Settings...") {
                    settingsAction()
                }
                .buttonStyle(.borderedProminent)
                Button("Quit") {
                    quitAction()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct StatusBadge: View {
    let status: SalaryStatus

    private var colors: (foreground: Color, background: Color) {
        switch status {
        case .working:
            return (.green, Color.green.opacity(0.18))
        case .paused:
            return (.orange, Color.orange.opacity(0.18))
        case .stop:
            return (.red, Color.red.opacity(0.18))
        case .noSet:
            return (.secondary, Color.secondary.opacity(0.16))
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.background)
            .clipShape(Capsule())
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
    }
}

struct InfoCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            self.onResolve(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.onResolve(nsView.window)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SalaryStore())
}
