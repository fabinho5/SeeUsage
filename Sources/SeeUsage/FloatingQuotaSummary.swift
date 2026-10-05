import AppKit
import Foundation

public enum FloatingBarOrientation: String, CaseIterable, Identifiable, Sendable {
    case horizontal, vertical
    public var id: String { rawValue }
    public var title: String { self == .horizontal ? "Horizontal" : "Vertical" }
}

public enum FloatingBarQuotas: String, CaseIterable, Identifiable, Sendable {
    case both, fiveHours, weekly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .both: "5h + weekly"
        case .fiveHours: "5h only"
        case .weekly: "Weekly only"
        }
    }

    var periods: [FloatingQuotaPeriod] {
        switch self {
        case .both: [.fiveHours, .weekly]
        case .fiveHours: [.fiveHours]
        case .weekly: [.weekly]
        }
    }
}

enum FloatingBarVisibility {
    static let codex = "provider:codex"
    static let antigravity = "provider:antigravity"
    static let claude = "provider:claude"

    static func includes(_ profile: UsageProfile, hiddenItems: Set<String>) -> Bool {
        let providerKey = profile.provider == .codex ? codex : antigravity
        return !hiddenItems.contains(providerKey) && !hiddenItems.contains(profile.id.uuidString)
    }
}

enum FloatingQuotaPeriod: String {
    case fiveHours, weekly
    var label: String { self == .fiveHours ? "5h" : "7d" }
    var title: String { self == .fiveHours ? "5-hour quota" : "Weekly quota" }

    func matches(_ window: UsageWindow) -> Bool {
        if let duration = window.durationMinutes {
            return duration == (self == .fiveHours ? 300 : 10_080)
        }
        let label = window.label.lowercased().filter { $0.isLetter || $0.isNumber }
        switch self {
        case .fiveHours: return ["5h", "5hour", "5hours", "fivehour", "fivehours"].contains(label)
        case .weekly: return ["weekly", "week", "7d", "7day", "7days", "7dayquota"].contains(label)
        }
    }
}

struct FloatingQuotaValue: Identifiable, Equatable {
    let period: FloatingQuotaPeriod
    let percent: Double?
    var id: FloatingQuotaPeriod { period }
}

struct FloatingQuotaItem: Identifiable, Equatable {
    let id: String
    let label: String
    let values: [FloatingQuotaValue]

    static func items(
        profiles: [UsageProfile],
        snapshots: [UUID: UsageSnapshot],
        claudeUsage: ClaudeUsageSnapshot?,
        refreshIntervalMinutes: Int,
        quotas: FloatingBarQuotas = .both,
        hiddenItems: Set<String> = [],
        now: Date = Date()
    ) -> [FloatingQuotaItem] {
        let staleAfter = Double(max(600, refreshIntervalMinutes * 120))
        var items = profiles.compactMap { profile -> FloatingQuotaItem? in
            guard FloatingBarVisibility.includes(profile, hiddenItems: hiddenItems) else { return nil }
            let snapshot = snapshots[profile.id]
            let isCurrent = snapshot.map {
                $0.error == nil && now.timeIntervalSince($0.fetchedAt) <= staleAfter
            } ?? false
            return FloatingQuotaItem(
                id: profile.id.uuidString,
                label: profile.name,
                values: values(in: snapshot?.windows ?? [], quotas: quotas, isCurrent: isCurrent)
            )
        }
        if let claudeUsage, !hiddenItems.contains(FloatingBarVisibility.claude) {
            items.append(FloatingQuotaItem(
                id: "claude-code",
                label: "Claude",
                values: values(in: claudeUsage.windows, quotas: quotas,
                               isCurrent: now.timeIntervalSince(claudeUsage.updatedAt) <= staleAfter)
            ))
        }
        return items
    }

    private static func values(in windows: [UsageWindow], quotas: FloatingBarQuotas, isCurrent: Bool) -> [FloatingQuotaValue] {
        quotas.periods.map { period in
            FloatingQuotaValue(period: period, percent: isCurrent ? lowestPercent(in: windows.filter(period.matches)) : nil)
        }
    }

    private static func lowestPercent(in windows: [UsageWindow]) -> Double? {
        windows.compactMap(\.remainingPercent)
            .filter(\.isFinite)
            .min()
            .map { max(0, min(100, $0)) }
    }

    var labelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return min(96, ceil((label as NSString).size(withAttributes: [.font: font]).width))
    }
}

enum FloatingBarLayout {
    struct SizeKey: Hashable {
        private struct Profile: Hashable {
            let id: String
            let label: String
        }
        private let profiles: [Profile]
        private let orientation: FloatingBarOrientation
        private let quotas: FloatingBarQuotas

        init(items: [FloatingQuotaItem], orientation: FloatingBarOrientation, quotas: FloatingBarQuotas) {
            profiles = items.map { Profile(id: $0.id, label: $0.label) }
            self.orientation = orientation
            self.quotas = quotas
        }
    }

    static let cornerRadius: CGFloat = NativeGlassStyle.cornerRadius
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 10
    static let itemSpacing: CGFloat = 12
    static let labelSpacing: CGFloat = 10
    static let quotaSpacing: CGFloat = 10
    static let periodSpacing: CGFloat = 3
    static let periodWidth: CGFloat = 18
    static let percentageWidth: CGFloat = 38
    static let horizontalRowHeight: CGFloat = 36
    static let verticalRowHeight: CGFloat = 20

    static func valuesWidth(quotas: FloatingBarQuotas) -> CGFloat {
        quotas == .both ? 2 * (periodWidth + periodSpacing + percentageWidth) + quotaSpacing : percentageWidth
    }

    static func horizontalItemWidth(_ item: FloatingQuotaItem, quotas: FloatingBarQuotas) -> CGFloat {
        max(item.labelWidth, valuesWidth(quotas: quotas))
    }

    static func size(
        items: [FloatingQuotaItem],
        availableWidth: CGFloat,
        availableHeight: CGFloat = 800,
        orientation: FloatingBarOrientation = .horizontal,
        quotas: FloatingBarQuotas = .both
    ) -> NSSize {
        fittedSize(naturalSize(items: items, orientation: orientation, quotas: quotas),
                   availableWidth: availableWidth, availableHeight: availableHeight)
    }

    static func naturalSize(items: [FloatingQuotaItem], orientation: FloatingBarOrientation, quotas: FloatingBarQuotas) -> NSSize {
        // The view and panel share the same spacing and fixed percentage slots.
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        if orientation == .vertical {
            contentWidth = items.isEmpty ? 110 : (items.map(\.labelWidth).max() ?? 0) + labelSpacing + valuesWidth(quotas: quotas)
            let count = CGFloat(max(1, items.count))
            contentHeight = count * verticalRowHeight + max(0, count - 1) * itemSpacing
        } else {
            contentWidth = items.isEmpty ? 110 : items.reduce(CGFloat.zero) {
                $0 + horizontalItemWidth($1, quotas: quotas)
            } + CGFloat(max(0, items.count - 1)) * (2 * itemSpacing + 1)
            contentHeight = horizontalRowHeight
        }
        return NSSize(width: contentWidth + 2 * horizontalPadding,
                      height: contentHeight + 2 * verticalPadding)
    }

    static func fittedSize(_ naturalSize: NSSize, availableWidth: CGFloat, availableHeight: CGFloat) -> NSSize {
        NSSize(width: min(ceil(naturalSize.width), max(120, availableWidth - 32)),
               height: min(ceil(naturalSize.height), max(56, availableHeight - 32)))
    }
}
