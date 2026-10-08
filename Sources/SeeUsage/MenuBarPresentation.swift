import AppKit
import SwiftUI

enum MenuBarQuota: String, CaseIterable, Codable, Identifiable {
    case fiveHours, weekly, lowest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveHours: "Session (5h)"
        case .weekly: "Weekly"
        case .lowest: "Lowest quota"
        }
    }

    func matches(_ window: UsageWindow) -> Bool {
        switch self {
        case .fiveHours: FloatingQuotaPeriod.fiveHours.matches(window)
        case .weekly: FloatingQuotaPeriod.weekly.matches(window)
        case .lowest: true
        }
    }
}

enum MenuBarGrouping: String, CaseIterable, Codable, Identifiable {
    case accounts, providers
    var id: String { rawValue }
    var title: String { self == .accounts ? "Each account" : "Each provider" }
}

struct MenuBarPreferences: Codable, Equatable {
    var quota: MenuBarQuota = .fiveHours
    var grouping: MenuBarGrouping = .accounts
    var hiddenItems: Set<String> = []
}

struct MenuBarQuotaItem: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Int?
    var quota: MenuBarQuota? = nil
    var percentText: String { percent.map { "\($0)%" } ?? "–" }

    static func items(
        profiles: [UsageProfile], snapshots: [UUID: UsageSnapshot], claudeUsage: ClaudeUsageSnapshot?,
        preferences: MenuBarPreferences, displayNames: [UUID: String] = [:],
        refreshIntervalMinutes: Int = 5, now: Date = Date(), mode: MenuBarDisplayMode = .percent
    ) -> [Self] {
        let staleAfter = Double(max(600, refreshIntervalMinutes * 120))
        var sources: [(provider: String, item: Self)] = profiles.compactMap { profile in
            guard FloatingBarVisibility.includes(profile, hiddenItems: preferences.hiddenItems) else { return nil }
            let snapshot = snapshots[profile.id]
            let isCurrent = snapshot.map {
                $0.error == nil && now.timeIntervalSince($0.fetchedAt) <= staleAfter
                    && $0.fetchedAt.timeIntervalSince(now) <= 60
            } ?? false
            let windows = (snapshot?.windows ?? []).filter {
                profile.provider != .codex || !CodexQuotaPresentation.isReserve($0)
            }
            return (profile.provider.rawValue, Self(
                id: profile.id.uuidString, label: displayNames[profile.id] ?? profile.name,
                percent: isCurrent ? remaining(in: windows, quota: preferences.quota, now: now) : nil
            ))
        }
        if let claudeUsage, !preferences.hiddenItems.contains(FloatingBarVisibility.claude) {
            let isCurrent = now.timeIntervalSince(claudeUsage.updatedAt) <= staleAfter
                && claudeUsage.updatedAt.timeIntervalSince(now) <= 60
            sources.append(("claude", Self(
                id: ClaudeUsageSnapshot.profileID.uuidString,
                label: displayNames[ClaudeUsageSnapshot.profileID] ?? "Claude Code",
                percent: isCurrent ? remaining(in: claudeUsage.windows, quota: preferences.quota, now: now) : nil
            )))
        }
        var result = sources.map(\.item)
        if preferences.grouping == .providers {
            var providerOrder: [String] = []
            for source in sources where !providerOrder.contains(source.provider) {
                providerOrder.append(source.provider)
            }
            result = providerOrder.map { provider in
                let entries = sources.filter { $0.provider == provider }.map(\.item)
                let name = provider == "codex" ? "Codex" : provider == "antigravity" ? "Antigravity" : "Claude Code"
                let accounts = entries.map(\.label).joined(separator: ", ")
                return Self(id: "provider:\(provider)", label: "\(name) (\(accounts))",
                            percent: entries.compactMap(\.percent).min())
            }
        }
        guard mode == .stackedBars, result.count == 1 else { return result }
        // Reuse the same selection, freshness checks, and provider grouping for each period.
        return [MenuBarQuota.fiveHours, .weekly].compactMap { quota in
            var periodPreferences = preferences
            periodPreferences.quota = quota
            guard let item = items(profiles: profiles, snapshots: snapshots, claudeUsage: claudeUsage,
                                  preferences: periodPreferences, displayNames: displayNames,
                                  refreshIntervalMinutes: refreshIntervalMinutes, now: now).first else { return nil }
            return Self(id: "\(item.id):\(quota.rawValue)", label: "\(item.label) · \(quota.title)",
                        percent: item.percent, quota: quota)
        }
    }

    static func isSessionWeeklyPair(_ items: [Self]) -> Bool {
        items.count == 2 && items[0].quota == .fiveHours && items[1].quota == .weekly
    }

    private static func remaining(in windows: [UsageWindow], quota: MenuBarQuota, now: Date) -> Int? {
        windows.filter { quota.matches($0) && ($0.resetsAt.map { $0 > now } ?? true) }
            .compactMap(\.remainingPercent)
            .filter { $0.isFinite && (0...100).contains($0) }
            .min().map { Int($0.rounded()) }
    }

    static func tooltip(items: [Self], quota: MenuBarQuota, mode: MenuBarDisplayMode) -> String {
        guard !items.isEmpty else { return "SeeUsage · No accounts selected" }
        let order = mode == .accountPercentages ? "Left to right" : "Top to bottom, then left to right"
        let quotaTitle = isSessionWeeklyPair(items) ? "Session (5h) + Weekly" : quota.title
        return "SeeUsage · \(quotaTitle) remaining\n\(order)\n"
            + items.map { "\($0.label): \($0.percent.map { "\($0)%" } ?? "Unavailable")" }.joined(separator: "\n")
    }
}

/// Template images keep the small menu bar indicators readable in light and dark appearances.
enum MenuBarIndicators {
    static func image(items: [MenuBarQuotaItem], mode: MenuBarDisplayMode) -> NSImage {
        let entries = items.isEmpty ? [MenuBarQuotaItem(id: "empty", label: "No accounts selected", percent: nil)] : items
        let isBars = mode == .stackedBars
        let rowsPerColumn = isBars ? 3 : 2
        let rows = min(rowsPerColumn, entries.count)
        let columns = (entries.count + rowsPerColumn - 1) / rowsPerColumn
        let columnWidth: CGFloat = isBars ? 15 : 27
        let columnGap: CGFloat = 4
        let rowHeight: CGFloat = isBars ? (rows == 3 ? 5 : 6) : 9
        let rowGap: CGFloat = isBars ? (rows == 3 ? 1.5 : 3) : 0
        let height = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowGap
        let size = NSSize(width: CGFloat(columns) * columnWidth + CGFloat(columns - 1) * columnGap, height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            for (index, item) in entries.enumerated() {
                let x = CGFloat(index / rowsPerColumn) * (columnWidth + columnGap)
                let y = CGFloat(index % rowsPerColumn) * (rowHeight + rowGap)
                if isBars {
                    let rect = NSRect(x: x, y: y, width: columnWidth, height: rowHeight)
                    NSColor.black.withAlphaComponent(0.22).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: rowHeight / 2, yRadius: rowHeight / 2).fill()
                    if let percent = item.percent, percent > 0 {
                        NSColor.black.setFill()
                        let width = max(1, columnWidth * CGFloat(percent) / 100)
                        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: rowHeight),
                                     xRadius: rowHeight / 2, yRadius: rowHeight / 2).fill()
                    } else if item.percent == nil {
                        NSColor.black.withAlphaComponent(0.55).setFill()
                        NSBezierPath(rect: NSRect(x: x + columnWidth / 2 - 1, y: y, width: 2, height: rowHeight)).fill()
                    }
                } else {
                    let text = item.percentText as NSString
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                        .foregroundColor: NSColor.black
                    ]
                    let width = text.size(withAttributes: attributes).width
                    text.draw(at: NSPoint(x: x + (columnWidth - width) / 2, y: y - 1), withAttributes: attributes)
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = entries.map { "\($0.label): \($0.percentText)" }.joined(separator: ", ")
        return image
    }
}

extension SettingsStore {
    @MainActor var menuBarItems: [MenuBarQuotaItem] {
        MenuBarQuotaItem.items(profiles: orderedDisplayProfiles, snapshots: UsageStore.shared.snapshots,
                              claudeUsage: UsageStore.shared.claudeUsageSnapshot,
                              preferences: menuBarPreferences, displayNames: profilePresentation.displayNames,
                              refreshIntervalMinutes: refreshIntervalMinutes, mode: menuBarDisplayMode)
    }

    func menuBarVisibilityBinding(for key: String) -> Binding<Bool> {
        Binding(get: { !self.menuBarPreferences.hiddenItems.contains(key) }, set: { visible in
            if visible { self.menuBarPreferences.hiddenItems.remove(key) }
            else { self.menuBarPreferences.hiddenItems.insert(key) }
        })
    }
}

struct MenuBarSelection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Toggle("Codex", isOn: settings.menuBarVisibilityBinding(for: FloatingBarVisibility.codex))
        ForEach(settings.orderedDisplayProfiles.filter { $0.provider == .codex }) { profile in
            Toggle(settings.displayName(for: profile), isOn: settings.menuBarVisibilityBinding(for: profile.id.uuidString))
                .padding(.leading, 16)
                .disabled(settings.menuBarPreferences.hiddenItems.contains(FloatingBarVisibility.codex))
        }
        Toggle(settings.displayName(for: SettingsStore.antigravityProfileID, defaultName: "Antigravity"),
               isOn: settings.menuBarVisibilityBinding(for: FloatingBarVisibility.antigravity))
        Toggle(settings.displayName(for: ClaudeUsageSnapshot.profileID, defaultName: "Claude Code"),
               isOn: settings.menuBarVisibilityBinding(for: FloatingBarVisibility.claude))
    }
}

struct MenuBarPreview: View {
    let items: [MenuBarQuotaItem]
    let mode: MenuBarDisplayMode
    var showIcon = false

    var body: some View {
        Group {
            if mode == .accountPercentages {
                HStack(spacing: 4) {
                    if showIcon { Image(systemName: "gauge.with.needle") }
                    Text(items.isEmpty ? "–" : items.map(\.percentText).joined(separator: " · "))
                }
                .font(.system(size: 12).monospacedDigit())
            } else {
                Image(nsImage: MenuBarIndicators.image(items: items, mode: mode))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
