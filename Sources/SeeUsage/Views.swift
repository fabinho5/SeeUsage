import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show(tab: SettingsTab = .general) {
        NotificationCenter.default.post(name: NSNotification.Name("app.seeusage.closePopover"), object: nil)
        if let window {
            NotificationCenter.default.post(
                name: NSNotification.Name("app.seeusage.selectSettingsTab"),
                object: tab.rawValue
            )
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "SeeUsage Settings"
        panel.contentMinSize = NSSize(width: 560, height: 440)
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: SettingsView(initialTab: tab))
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

public enum SettingsTab: String, Sendable {
    case general, profiles
}

public enum Formatters {
    public static func dayMonth(_ date: Date) -> String {
        dateString(date, format: "d/M")
    }

    public static func dayMonthName(_ date: Date) -> String {
        dateString(date, format: "d MMM")
    }

    public static func dayMonthYear(_ date: Date) -> String {
        dateString(date, format: "d MMM yyyy")
    }

    public static func longDayMonthYear(_ date: Date) -> String {
        dateString(date, format: "d MMMM yyyy")
    }

    public static func dayMonthTime(_ date: Date) -> String {
        dateString(date, format: "d MMM, HH:mm")
    }

    public static func resetDescription(for date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds == 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(max(1, minutes))m"
    }

    private static func dateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    public static func bankedCreditTitle(_ credit: BankedResetCredit) -> String {
        let title = credit.title ?? "Available reset credit"
        guard let expiration = credit.expiresAt else { return title }
        return "\(title) — expires on \(dayMonth(expiration))"
    }
}

public struct UsagePopoverView: View {
    @Bindable private var store = UsageStore.shared
    @Bindable private var settings: SettingsStore
    @Bindable private var analytics = AnalyticsManager.shared
    @Bindable private var resetController = BankedResetController.shared

    public init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    private var layout: UIProfile { settings.uiProfile }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: layout.contentSpacing) {
                    if settings.codexProfiles.isEmpty,
                       store.snapshots[SettingsStore.antigravityProfileID] == nil,
                       store.claudeUsageSnapshot == nil {
                        ContentUnavailableView {
                            Label("No usage data", systemImage: "person.crop.circle.badge.questionmark")
                        } description: {
                            Text("Add a Codex profile or enable Claude Code usage in Settings.")
                        } actions: {
                            Button("Open Settings") { SettingsWindowManager.shared.show(tab: .profiles) }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        ForEach(settings.orderedDisplayProfiles) { profile in
                            if profile.provider == .codex {
                                profileSection(profile: profile, snapshot: store.snapshots[profile.id], provider: "Codex")
                                Divider().opacity(0.6)
                            } else if let snapshot = store.snapshots[profile.id] {
                                profileSection(profile: profile, snapshot: snapshot, provider: "Antigravity")
                                Divider().opacity(0.6)
                            }
                        }
                        if let claudeUsage = store.claudeUsageSnapshot {
                            if !settings.codexProfiles.isEmpty || store.snapshots[SettingsStore.antigravityProfileID] != nil {
                                Divider().opacity(0.6)
                            }
                            claudeUsageSection(claudeUsage)
                        }
                    }

                    if store.snapshots.isEmpty && store.claudeUsageSnapshot == nil && !store.isRefreshing {
                        Text("Usage will appear here after the first refresh.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }

                    if !analytics.snapshots.isEmpty {
                        activitySection
                    }
                }
                .padding(.horizontal, layout.contentHorizontalPadding)
                .padding(.vertical, layout.contentVerticalPadding)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: layout.popoverSize.width, height: layout.popoverSize.height)
        .overlay { GlassEdgeHighlight() }
        .tint(settings.currentTheme.uiAccent)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SeeUsage").font(layout.titleFont)
                Text("Remaining quota").font(layout.detailFont).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await store.refresh(forceAfterCurrent: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh usage (⌘R)")
            }
            Button {
                if settings.hudEnabled {
                    FloatingHUDManager.shared.hide()
                } else {
                    settings.hudCompactMode = true
                    FloatingHUDManager.shared.show()
                }
            } label: {
                Image(systemName: settings.hudEnabled ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                    .foregroundStyle(settings.hudEnabled ? settings.currentTheme.uiAccent : Color.primary)
            }
            .buttonStyle(.bordered)
            .help(settings.hudEnabled ? "Hide floating bar" : "Show floating bar")
            .accessibilityLabel("Floating bar")
            .accessibilityValue(settings.hudEnabled ? "On" : "Off")
            Button {
                SettingsWindowManager.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .help("Settings")
        }
        .controlSize(layout.controlSize)
        .padding(.horizontal, 14)
        .padding(.vertical, layout.headerVerticalPadding)
    }

    @ViewBuilder
    private func profileSection(profile: UsageProfile, snapshot: UsageSnapshot?, provider: String) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            AccountSectionHeader(profileID: profile.id, originalName: profile.name,
                                 detail: snapshot?.plan, summary: profileSummary(snapshot), settings: settings)

            if !settings.profilePresentation.isCollapsed(profile.id) {
                if let snapshot {
                    if let error = snapshot.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if snapshot.isStale {
                        Label("Showing old data", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(provider == "Codex" ? CodexQuotaPresentation.ordered(snapshot.windows) : snapshot.windows) { window in
                        quotaRow(window, profileID: profile.id, provider: provider, windows: snapshot.windows,
                                 fetchedAt: snapshot.fetchedAt, hasError: snapshot.error != nil)
                    }

                    if provider == "Codex" {
                        let credits = snapshot.bankedCredits.filter { $0.status.lowercased() == "available" }
                        let creditCount = max(snapshot.availableResetCredits ?? 0, credits.count)
                        if creditCount > 0 {
                            Menu {
                                ForEach(credits) { credit in
                                    Button(Formatters.bankedCreditTitle(credit)) {
                                        resetController.request(profile: profile, credit: credit,
                                                                displayName: settings.displayName(for: profile))
                                    }
                                }
                            } label: {
                                Label("Use banked reset (\(creditCount))", systemImage: "bolt.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .font(layout.actionFont)
                            .controlSize(layout.controlSize)
                            .disabled(snapshot.error != nil || snapshot.isStale || resetController.activeProfileID != nil)
                        }
                    }

                    if snapshot.windows.isEmpty && snapshot.error == nil {
                        Text("No quota windows returned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if store.isRefreshing {
                    ProgressView("Loading usage…").controlSize(.small)
                } else {
                    Text("No usage data yet.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout.sectionVerticalPadding)
    }

    private func claudeUsageSection(_ snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            AccountSectionHeader(profileID: ClaudeUsageSnapshot.profileID, originalName: "Claude Code",
                                 detail: "Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))",
                                 summary: Date().timeIntervalSince(snapshot.updatedAt) <= Double(max(600, settings.refreshIntervalMinutes * 120))
                                     ? AccountSectionHeader.quotaSummary(windows: snapshot.windows) : "Outdated", settings: settings)
            if !settings.profilePresentation.isCollapsed(ClaudeUsageSnapshot.profileID) {
                ForEach(snapshot.windows) { window in
                    quotaRow(window, profileID: ClaudeUsageSnapshot.profileID, provider: "Claude Code",
                             windows: snapshot.windows, fetchedAt: snapshot.updatedAt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout.sectionVerticalPadding)
    }

    private func profileSummary(_ snapshot: UsageSnapshot?) -> String? {
        guard let snapshot else { return "Unavailable" }
        if snapshot.error != nil { return "Unavailable" }
        if snapshot.isStale { return "Outdated" }
        return AccountSectionHeader.quotaSummary(windows: snapshot.windows)
    }

    private func quotaRow(
        _ window: UsageWindow, profileID: UUID, provider: String,
        windows: [UsageWindow], fetchedAt: Date, hasError: Bool = false
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let hints = analytics.quotaHints(
                for: window, profileID: profileID, service: provider,
                windows: windows, fetchedAt: fetchedAt, hasError: hasError, now: context.date
            )
            VStack(alignment: .leading, spacing: layout.rowSpacing) {
                if layout == .compact {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 4) {
                            quotaLabel(window, provider: provider)
                            quotaPercent(window, includesLeft: true)
                        }
                        .font(layout.quotaFont)
                        Spacer(minLength: 4)
                        resetLabel(window)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        quotaLabel(window, provider: provider)
                        Spacer(minLength: 4)
                        quotaPercent(window, includesLeft: false)
                            .font(layout.quotaFont.weight(.semibold))
                    }
                    .font(layout.quotaFont)
                }
                if let percent = window.remainingPercent {
                    QuotaGauge(percent: percent,
                               color: UIColors.quotaFillColor(percent: percent, accent: settings.currentTheme.uiAccent),
                               height: layout.barHeight, pacing: hints?.pacing)
                }
                if layout == .classic { resetLabel(window) }
                if let hints {
                    QuotaHintView(hints: hints, uiProfile: layout)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func quotaLabel(_ window: UsageWindow, provider: String) -> some View {
        Text(quotaTitle(window, provider: provider))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(quotaTitle(window, provider: provider))
    }

    @ViewBuilder private func quotaPercent(_ window: UsageWindow, includesLeft: Bool) -> some View {
        if let percent = window.remainingPercent {
            Text("\(Int(percent.rounded()))%\(includesLeft ? " left" : "")")
                .monospacedDigit()
                .foregroundStyle(UIColors.quotaTextColor(percent: percent))
                .fixedSize()
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func resetLabel(_ window: UsageWindow) -> some View {
        if let reset = window.resetsAt {
            Text("Resets \(Formatters.resetDescription(for: reset))")
                .font(layout.detailFont)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func quotaTitle(_ window: UsageWindow, provider: String) -> String {
        if provider == "Codex", CodexQuotaPresentation.isReserve(window) { return "GPT reserve" }
        if layout == .classic {
            return [window.scope, window.label].compactMap { $0 }.joined(separator: " · ")
        }
        let period: String
        if FloatingQuotaPeriod.fiveHours.matches(window) { period = "Session" }
        else if FloatingQuotaPeriod.weekly.matches(window) { period = "Weekly" }
        else { period = window.label }
        guard let scope = window.scope, scope.lowercased() != "codex" else { return period }
        let name = scope == "base_model_inference" ? "Base model" : scope.replacingOccurrences(of: "Claude and GPT", with: "Claude/GPT")
        return "\(name) · \(period)"
    }

    private var footer: some View {
        HStack {
            if let date = store.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    .font(layout.detailFont)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not updated yet").font(layout.detailFont).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit SeeUsage") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(layout.detailFont)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, layout.footerVerticalPadding)
    }

    private var activitySection: some View {
        // Keep the heatmap's identity and selected day while avoiding hidden analytics work.
        let daily: [DailyConsumption] = settings.activityCollapsed ? [] : analytics.computeDailyConsumption(days: 85)
        let cutoff = Date().addingTimeInterval(-85 * 86_400)
        let history: [QuotaHistorySnapshot] = settings.activityCollapsed ? [] : analytics.snapshots.filter { $0.timestamp >= cutoff }
        return ActivityHeatmap(dailyConsumption: daily, historySnapshots: history,
                               codexProfiles: settings.codexProfiles,
                               displayNames: settings.profilePresentation.displayNames,
                               accent: settings.currentTheme.uiAccent,
                               isCollapsed: $settings.activityCollapsed)
    }
}

private struct ActivityProfileUsage: Identifiable {
    let id: String
    let profileName: String
    let consumptionPercent: Double
}

private struct ActivityHeatmap: View {
    let dailyConsumption: [DailyConsumption]
    let historySnapshots: [QuotaHistorySnapshot]
    let codexProfiles: [UsageProfile]
    let displayNames: [UUID: String]
    let accent: Color
    @Binding var isCollapsed: Bool
    @State private var hoveredDate: Date?
    @State private var selectedDate: Date?

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -11, to: currentWeekStart) ?? currentWeekStart
        let usageByDay = Dictionary(grouping: dailyConsumption) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { entries in
            entries.reduce(0) { $0 + $1.consumptionPercent }
        }
        let peakUsage = usageByDay.values.max() ?? 0
        let selectedProfileUsage: [ActivityProfileUsage] = selectedDate.map { selectedDate in
            var sampledProfiles: [UUID: (name: String, service: String)] = [:]
            for snapshot in historySnapshots where calendar.isDate(snapshot.timestamp, inSameDayAs: selectedDate) {
                for record in snapshot.records {
                    sampledProfiles[record.profileID] = (record.profileName, record.service)
                }
            }

            let usageByProfile = Dictionary(
                dailyConsumption
                    .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
                    .map { ($0.profileID, $0.consumptionPercent) },
                uniquingKeysWith: { first, _ in first }
            )

            let currentProfileNames = Dictionary(
                codexProfiles.map { ($0.id, $0.name) },
                uniquingKeysWith: { _, newest in newest }
            )
            var profileUsage: [ActivityProfileUsage] = []
            var otherCodexUsage = 0.0
            var hasOtherCodexSamples = false

            for (profileID, profile) in sampledProfiles {
                let usage = usageByProfile[profileID] ?? 0
                if profileID == SettingsStore.antigravityProfileID {
                    profileUsage.append(ActivityProfileUsage(
                        id: profileID.uuidString,
                        profileName: "agy",
                        consumptionPercent: usage
                    ))
                } else if let currentName = currentProfileNames[profileID] {
                    profileUsage.append(ActivityProfileUsage(
                        id: profileID.uuidString,
                        profileName: currentName,
                        consumptionPercent: usage
                    ))
                } else if profile.service == "Codex" {
                    otherCodexUsage += usage
                    hasOtherCodexSamples = true
                } else {
                    profileUsage.append(ActivityProfileUsage(
                        id: profileID.uuidString,
                        profileName: profile.name,
                        consumptionPercent: usage
                    ))
                }
            }

            if hasOtherCodexSamples {
                profileUsage.append(ActivityProfileUsage(
                    id: "other-codex",
                    profileName: "Other Codex",
                    consumptionPercent: otherCodexUsage
                ))
            }

            return profileUsage.sorted { $0.consumptionPercent > $1.consumptionPercent }
        } ?? []
        let hoverSummary = hoveredDate.map { date in
            activitySummary(for: date, usage: usageByDay[calendar.startOfDay(for: date)] ?? 0)
        } ?? "Last 12 weeks"

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCollapsed.toggle()
                    hoveredDate = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text("Activity")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(isCollapsed ? "Last 12 weeks" : hoverSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(isCollapsed ? "Expand" : "Collapse") Activity")
            .accessibilityLabel("Activity")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            if !isCollapsed {
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { day in
                                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: firstWeekStart) ?? today
                                let usage = usageByDay[date] ?? 0
                                let intensity = activityIntensity(for: usage, peak: peakUsage)

                                Button {
                                    selectedDate = selectedDate == date ? nil : date
                                } label: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(activityColor(for: intensity))
                                        .overlay {
                                            if selectedDate == date {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1)
                                            }
                                        }
                                        .frame(width: 12, height: 12)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .onHover { isHovering in
                                    if isHovering { hoveredDate = date }
                                }
                                .accessibilityLabel(activityDescription(for: date, usage: usage))
                                .accessibilityHint("Show usage by profile")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if let selectedDate {
                    Divider()

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(Formatters.dayMonthYear(selectedDate))
                                .font(.caption.weight(.medium))
                            Spacer()
                            Button {
                                self.selectedDate = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Close activity details")
                        }

                        if selectedProfileUsage.isEmpty {
                            Text("No recorded usage")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedProfileUsage) { entry in
                                HStack {
                                    Text(UUID(uuidString: entry.id).flatMap { displayNames[$0] } ?? entry.profileName)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(entry.consumptionPercent.formatted(.number.precision(.fractionLength(0...1)))) quota pts")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func activityIntensity(for usage: Double, peak: Double) -> Int {
        guard usage > 0, peak > 0 else { return 0 }
        return min(4, max(1, Int(ceil(usage / peak * 4))))
    }

    private func activityColor(for intensity: Int) -> Color {
        switch intensity {
        case 1: accent.opacity(0.22)
        case 2: accent.opacity(0.42)
        case 3: accent.opacity(0.68)
        case 4: accent
        default: Color.primary.opacity(0.07)
        }
    }

    private func activitySummary(for date: Date, usage: Double) -> String {
        let dateLabel = Formatters.dayMonthName(date)
        guard usage > 0 else { return "\(dateLabel) · no use" }
        let usageLabel = usage.formatted(.number.precision(.fractionLength(0...1)))
        return "\(dateLabel) · \(usageLabel) quota pts"
    }

    private func activityDescription(for date: Date, usage: Double) -> String {
        let dateLabel = Formatters.longDayMonthYear(date)
        guard usage > 0 else { return "\(dateLabel) · No recorded usage" }
        let usageLabel = usage.formatted(.number.precision(.fractionLength(0...1)))
        return "\(dateLabel) · \(usageLabel) quota points used"
    }
}

private enum PreferenceTab: String, CaseIterable, Identifiable {
    case general, providers
    var id: String { rawValue }
}

private enum ClaudeProviderStatus {
    case checking
    case notInstalled
    case signedIn
    case signedOut
    case unavailable

    var title: String {
        switch self {
        case .checking: return "Checking…"
        case .notInstalled: return "Not installed"
        case .signedIn: return "Signed in"
        case .signedOut: return "Not signed in"
        case .unavailable: return "Status unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .checking: return "circle.dotted"
        case .notInstalled, .signedOut: return "xmark.circle"
        case .signedIn: return "checkmark.circle.fill"
        case .unavailable: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .signedIn: return .green
        case .checking, .notInstalled, .signedOut, .unavailable: return .secondary
        }
    }
}

public struct SettingsView: View {
    @Bindable private var settings = SettingsStore.shared
    @ObservedObject private var updater = AppUpdater.shared
    @State private var selectedTab: PreferenceTab
    @State private var claudeProviderStatus: ClaudeProviderStatus = .checking
    @State private var claudeUsageSyncEnabled = false
    @State private var claudeUsageSyncError: String?

    public init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab == .profiles ? .providers : .general)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            generalPreferences
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferenceTab.general)
            providerPreferences
                .tabItem { Label("Providers", systemImage: "network") }
                .tag(PreferenceTab.providers)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 440)
        .background(UIColors.background)
        .tint(settings.currentTheme.uiAccent)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("app.seeusage.selectSettingsTab"))) { note in
            if (note.object as? String) == SettingsTab.profiles.rawValue {
                selectedTab = .providers
            } else {
                selectedTab = .general
            }
        }
        .task(id: selectedTab) {
            guard selectedTab == .providers else { return }
            claudeUsageSyncEnabled = ClaudeStatusLineIntegration.isEnabled()
            await refreshClaudeProviderStatus()
        }
    }

    private var generalPreferences: some View {
        Form {
            Section("Menu Bar") {
                Picker("Display style", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(settings.menuBarDisplayMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.menuBarDisplayMode.usesAccountSelection {
                    menuBarAccountOptions
                }
                Toggle("Show SeeUsage icon", isOn: $settings.menuBarShowIcon)
                    .disabled([.stackedBars, .stackedPercentages, .iconOnly].contains(settings.menuBarDisplayMode))
                Picker("Quota refresh interval", selection: $settings.refreshIntervalMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Appearance") {
                Picker("UI profile", selection: $settings.uiProfile) {
                    ForEach(UIProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.uiProfile.description + " Both profiles share all features and account preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show floating bar", isOn: Binding(
                    get: { settings.hudEnabled },
                    set: { enabled in
                        if enabled { settings.hudCompactMode = true }
                        settings.hudEnabled = enabled
                        FloatingHUDManager.shared.applySettings()
                    }
                ))
                if settings.hudEnabled {
                    Picker("Bar orientation", selection: $settings.hudBarOrientation) {
                        ForEach(FloatingBarOrientation.allCases) { orientation in
                            Text(orientation.title).tag(orientation)
                        }
                    }
                    Picker("Bar quotas", selection: $settings.hudBarQuotas) {
                        ForEach(FloatingBarQuotas.allCases) { quotas in
                            Text(quotas.title).tag(quotas)
                        }
                    }
                    DisclosureGroup("Profiles and providers") {
                        FloatingBarSelection()
                    }
                }
                Toggle("Show Lume companion", isOn: Binding(
                    get: { settings.companionEnabled },
                    set: { enabled in
                        settings.companionEnabled = enabled
                        CompanionManager.shared.applySettings()
                    }
                ))
                if settings.companionEnabled {
                    Toggle("Let Lume move around", isOn: $settings.companionWanders)
                    Text("Checks quotas every 5 minutes. Drag to move; right-click for options.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Accent color", selection: $settings.selectedThemeID) {
                    ForEach(appearancePickerThemes) { theme in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(theme.uiAccent)
                                .frame(width: 10, height: 10)
                            Text(theme.name)
                        }
                        .tag(theme.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { NotificationManager.shared.requestAuthorization() }
                    }
                Toggle("Alert when quota is low", isOn: $settings.notifyOnCritical)
                    .disabled(!settings.notificationsEnabled)
                HStack {
                    Text("Low quota threshold")
                    Slider(value: Binding(
                        get: { Double(settings.criticalThresholdPercent) },
                        set: { settings.criticalThresholdPercent = Int($0.rounded()) }
                    ), in: 5...50, step: 5)
                    Text("\(settings.criticalThresholdPercent)%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
                .disabled(!settings.notificationsEnabled || !settings.notifyOnCritical)
                Toggle("Notify when quotas reset", isOn: $settings.notifyOnReset)
                    .disabled(!settings.notificationsEnabled)
                Toggle("Alert before banked reset expires", isOn: $settings.notifyOnBankedResetExpiring)
                    .disabled(!settings.notificationsEnabled)
                Toggle("Play notification sounds", isOn: $settings.notificationSoundEnabled)
                    .disabled(!settings.notificationsEnabled)
            }

            Section("App updates") {
                if updater.supportsInAppUpdates {
                    Toggle("Check automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticChecks($0) }
                    ))
                    Text("Checks at launch and every hour. You choose whether to install an update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Install the latest DMG to enable in-app updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(updater.supportsInAppUpdates ? "Check for updates…" : "View latest release…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                if let error = updater.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Source build")
        }
        .formStyle(.grouped)
        .tabItem { Label("General", systemImage: "gearshape") }
    }

    private var menuBarAccountOptions: some View {
        let items = settings.menuBarItems
        return Group {
            if MenuBarQuotaItem.isSessionWeeklyPair(items) {
                LabeledContent("Bars", value: "Session (5h) above Weekly")
            } else {
                Picker("Show quota", selection: $settings.menuBarPreferences.quota) {
                    ForEach(MenuBarQuota.allCases) { quota in
                        Text(quota.title).tag(quota)
                    }
                }
            }
            Picker("Show separately", selection: $settings.menuBarPreferences.grouping) {
                ForEach(MenuBarGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            DisclosureGroup("Accounts and providers in menu bar") {
                MenuBarSelection(settings: settings)
            }
            LabeledContent("Preview") {
                MenuBarPreview(items: items, mode: settings.menuBarDisplayMode,
                               showIcon: settings.menuBarShowIcon)
                    .help(MenuBarQuotaItem.tooltip(items: items,
                                                 quota: settings.menuBarPreferences.quota,
                                                 mode: settings.menuBarDisplayMode))
            }
            Text("Uses your account order. Hover over the menu bar indicator to identify each reading. Provider groups show their lowest selected account quota.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.menuBarDisplayMode == .stackedBars {
                Text("With one selected account or provider, the top bar shows the 5-hour session and the bottom bar shows the weekly quota.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearancePickerThemes: [AppTheme] {
        let themes = ThemeRegistry.appearanceThemes
        guard !themes.contains(where: { $0.id == settings.selectedThemeID }) else { return themes }
        return [settings.currentTheme] + themes
    }

    private var providerPreferences: some View {
        Form {
            Section("Codex") {
                providerStatusRow(executablePath: codexExecutablePath)
                DisclosureGroup("CLI path") {
                    LabeledContent {
                        TextField("Auto-detect", text: $settings.codexExecutableOverride)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } label: {
                        Text("Path").font(.caption)
                    }
                    Text("Leave empty to search common locations.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section {
                ForEach(settings.orderedDisplayProfiles) { profile in
                    profileOrderRow(profile)
                }
            } header: {
                HStack {
                    Text("Display order")
                    Spacer()
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Codex profiles") {
                if settings.codexProfiles.isEmpty {
                    Text("No profiles configured.").foregroundStyle(.secondary)
                }
                ForEach(settings.codexProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(settings.displayName(for: profile))
                            Text(profile.homePath ?? "No CODEX_HOME path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            settings.removeProfile(id: profile.id)
                        }
                        .controlSize(.small)
                    }
                }
                Button {
                    addProfileFromFolderPicker()
                } label: {
                    Label("Add Profile…", systemImage: "plus")
                }
            }

            Section("Antigravity") {
                providerStatusRow(executablePath: antigravityExecutablePath)
                DisclosureGroup("CLI path") {
                    LabeledContent {
                        TextField("Auto-detect", text: $settings.antigravityExecutableOverride)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } label: {
                        Text("Path").font(.caption)
                    }
                    Text("Leave empty to search common locations.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Claude Code") {
                claudeProviderStatusRow
                if claudeExecutablePath != nil {
                    HStack {
                        Text("Usage sync")
                            .font(.caption)
                        Spacer()
                        Button(claudeUsageSyncEnabled ? "Turn Off" : "Enable") {
                            setClaudeUsageSync(!claudeUsageSyncEnabled)
                        }
                        .controlSize(.small)
                    }
                    Text(claudeUsageSyncEnabled
                         ? "Usage updates as you use Claude Code."
                         : "Show Claude Code usage in SeeUsage.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let claudeUsageSyncError {
                        Text(claudeUsageSyncError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var codexExecutablePath: String? {
        ProcessRunner.resolveExecutable(named: "codex", overridePath: settings.codexExecutableOverride)
    }

    private var antigravityExecutablePath: String? {
        ProcessRunner.resolveExecutable(named: "agy", overridePath: settings.antigravityExecutableOverride)
    }

    private var claudeExecutablePath: String? {
        ProcessRunner.resolveExecutable(named: "claude")
    }

    private var claudeProviderStatusRow: some View {
        HStack(spacing: 8) {
            Label(claudeProviderStatus.title, systemImage: claudeProviderStatus.symbol)
                .font(.caption)
                .foregroundStyle(claudeProviderStatus.color)
            Spacer(minLength: 8)
            Text(claudeExecutablePath ?? "CLI not found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func refreshClaudeProviderStatus() async {
        guard let executablePath = claudeExecutablePath else {
            claudeProviderStatus = .notInstalled
            return
        }

        claudeProviderStatus = .checking
        do {
            let result = try await ProcessRunner.run(
                executable: executablePath,
                arguments: ["auth", "status"],
                timeout: 5
            )

            guard (try? JSONSerialization.jsonObject(with: result.standardOutput, options: [.fragmentsAllowed])) != nil else {
                claudeProviderStatus = .unavailable
                return
            }

            if result.terminationStatus == 0 {
                claudeProviderStatus = .signedIn
            } else if result.terminationStatus == 1 {
                let output = (result.outputString + "\n" + result.errorString).lowercased()
                let commandUnavailable = ["unknown command", "unrecognized command", "unknown subcommand", "invalid command"]
                    .contains(where: output.contains)
                claudeProviderStatus = commandUnavailable ? .unavailable : .signedOut
            } else {
                claudeProviderStatus = .unavailable
            }
        } catch {
            claudeProviderStatus = .unavailable
        }
    }

    private func setClaudeUsageSync(_ enabled: Bool) {
        do {
            if enabled {
                try ClaudeStatusLineIntegration.enable()
            } else {
                try ClaudeStatusLineIntegration.disable()
            }
            claudeUsageSyncEnabled = ClaudeStatusLineIntegration.isEnabled()
            claudeUsageSyncError = nil
        } catch {
            claudeUsageSyncEnabled = ClaudeStatusLineIntegration.isEnabled()
            claudeUsageSyncError = error.localizedDescription
        }
    }

    private func providerStatusRow(executablePath: String?) -> some View {
        HStack(spacing: 8) {
            Label(executablePath == nil ? "Not installed" : "Installed", systemImage: executablePath == nil ? "xmark.circle" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(executablePath == nil ? Color.secondary : Color.green)
            Spacer(minLength: 8)
            Text(executablePath ?? "CLI not found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private func profileOrderRow(_ profile: UsageProfile) -> some View {
        return HStack(spacing: 10) {
            Image(systemName: profile.provider == .antigravity ? "sparkles" : "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(settings.displayName(for: profile))
                .font(.system(.body, weight: .medium))
            Spacer()
            Text(profile.provider == .antigravity ? "Antigravity" : "Codex")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .draggable(profile.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let draggedProfileID = UUID(uuidString: value) else { return false }
            settings.moveDisplayProfile(draggedProfileID, relativeTo: profile.id)
            return true
        }
    }

    private func addProfileFromFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Codex profile folder"
        panel.message = "Select a folder containing Codex account data."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.addProfile(name: url.lastPathComponent.capitalized, path: url.path)
    }
}
