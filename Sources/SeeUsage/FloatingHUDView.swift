import SwiftUI
import AppKit

// MARK: - Floating Mini-HUD View
public struct FloatingHUDView: View {
    @Bindable var settings = SettingsStore.shared
    var store = UsageStore.shared
    @State private var isHovered: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if settings.hudCompactMode {
                compactHUDContent
            } else {
                expandedHUDContent
                    .padding(10)
            }
        }
        .onHover { hovering in
            guard !settings.hudCompactMode else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }

    private var barItems: [FloatingQuotaItem] {
        FloatingQuotaItem.items(
            profiles: settings.orderedDisplayProfiles,
            snapshots: store.snapshots,
            claudeUsage: store.claudeUsageSnapshot,
            refreshIntervalMinutes: settings.refreshIntervalMinutes,
            quotas: settings.hudBarQuotas,
            hiddenItems: settings.hudBarHiddenItems
        )
    }

    // MARK: - Floating percentage bar
    private var compactHUDContent: some View {
        let items = barItems
        let key = FloatingBarLayout.SizeKey(items: items, orientation: settings.hudBarOrientation, quotas: settings.hudBarQuotas)
        return FloatingQuotaBar(items: items, orientation: settings.hudBarOrientation, quotas: settings.hudBarQuotas) { size in
            FloatingHUDManager.shared.updateBarContentSize(size, for: key)
        }
        .gesture(barDragGesture, including: .gesture)
        .contextMenu {
            Menu("Orientation") {
                Picker("Orientation", selection: $settings.hudBarOrientation) {
                    ForEach(FloatingBarOrientation.allCases) { orientation in
                        Text(orientation.title).tag(orientation)
                    }
                }
            }
            Menu("Quotas") {
                Picker("Quotas", selection: $settings.hudBarQuotas) {
                    ForEach(FloatingBarQuotas.allCases) { quotas in
                        Text(quotas.title).tag(quotas)
                    }
                }
            }
            Menu("Profiles and providers") {
                FloatingBarSelection()
            }
            Divider()
            Toggle("Always on top", isOn: $settings.hudAlwaysOnTop)
            Button("Hide floating bar") { FloatingHUDManager.shared.hide() }
        }
    }

    private var barDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in FloatingHUDManager.shared.dragBar() }
            .onEnded { _ in FloatingHUDManager.shared.finishDraggingBar() }
    }

    // MARK: - Expanded Mode (Card Dashboard)
    private var expandedHUDContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                // Quota status dot.
                Circle()
                    .fill(UIColors.quotaStatusColor(percent: store.minRemainingPercent.map(Double.init)))
                    .frame(width: 7, height: 7)

                Text("SEEUSAGE")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(UIColors.textPrimary)

                Text("HUD")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(UIColors.textMuted)

                Spacer()

                if let lowest = store.minRemainingPercent {
                    Text("\(lowest)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(UIColors.quotaTextColor(percent: Double(lowest)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(UIColors.track)
                        )
                }

                // Quick Header Actions
                HStack(spacing: 3) {
                    hudIconButton(
                        icon: "arrow.clockwise",
                        help: "Refresh Quotas",
                        isSpinning: store.isRefreshing
                    ) {
                        Task { await store.refresh() }
                    }

                    hudIconButton(
                        icon: "arrow.down.right.and.arrow.up.left",
                        help: "Compact Pill Mode"
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            settings.hudCompactMode = true
                        }
                    }

                    hudIconButton(
                        icon: settings.hudAlwaysOnTop ? "pin.fill" : "pin",
                        help: settings.hudAlwaysOnTop ? "Always on top (active)" : "Desktop level",
                        active: settings.hudAlwaysOnTop
                    ) {
                        settings.hudAlwaysOnTop.toggle()
                    }

                    hudIconButton(icon: "xmark", help: "Hide HUD") {
                        FloatingHUDManager.shared.hide()
                    }
                }
                .opacity(isHovered ? 1.0 : 0.6)
            }

            Rectangle()
                .fill(UIColors.border)
                .frame(height: 1)

            // Codex Section
            if !settings.codexProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CODEX")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(UIColors.textMuted)
                        Spacer()
                    }

                    ForEach(settings.codexProfiles) { profile in
                        if let snapshot = store.snapshots[profile.id], !snapshot.windows.isEmpty {
                            profileHUDCard(name: profile.name, windows: snapshot.windows)
                        } else {
                            HStack {
                                Text(profile.name)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(UIColors.textPrimary)
                                Spacer()
                                Text("syncing...")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(UIColors.textMuted)
                            }
                            .padding(6)
                            .background(UIColors.surface.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }

            // Antigravity Section (Routed Models)
            if let agySnap = store.snapshots[SettingsStore.antigravityProfileID], !agySnap.windows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ANTIGRAVITY (ROUTED MODELS)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(UIColors.textMuted)
                        Spacer()
                    }

                    let grouped = Dictionary(grouping: agySnap.windows) { $0.scope ?? "Antigravity" }
                    let sortedKeys = grouped.keys.sorted { s1, s2 in
                        if s1.contains("Gemini") { return true }
                        if s2.contains("Gemini") { return false }
                        return s1 < s2
                    }

                    ForEach(sortedKeys, id: \.self) { scope in
                        let tag = scope.contains("Claude") ? "agy: claude & gpt" : (scope.contains("Gemini") ? "agy: gemini" : "agy: \(scope.lowercased())")
                        profileHUDCard(name: tag, windows: grouped[scope] ?? [])
                    }
                }
            }

            // Subtle Footer
            HStack {
                Text(timeAgoString(from: store.lastUpdated))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(UIColors.textMuted)

                Spacer()

                Text("drag to move")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(UIColors.textMuted)
            }
        }
        .frame(width: 250)
    }

    // MARK: - Subcomponents
    private func profileHUDCard(name: String, windows: [UsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(UIColors.textPrimary)
                Spacer()
            }

            ForEach(windows.prefix(2)) { window in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(window.label)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(UIColors.textSecondary)

                        Spacer()

                        if let resets = window.resetsAt {
                            Text(WatchDashboard.countdownString(until: resets))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(UIColors.textMuted)
                        }

                        if let pct = window.remainingPercent {
                            Text("\(Int(round(pct)))%")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(UIColors.quotaTextColor(percent: pct))
                        }
                    }

                    if let pct = window.remainingPercent {
                        miniHorizontalGauge(percent: pct, width: nil, height: 3.5)
                    }
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(UIColors.surface.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(UIColors.border.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func miniHorizontalGauge(percent: Double, width: CGFloat?, height: CGFloat) -> some View {
        GeometryReader { geo in
            let w = width ?? geo.size.width
            let fillWidth = max(2, w * CGFloat(max(0, min(100, percent))) / 100.0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(UIColors.track)
                    .frame(width: w, height: height)

                Capsule()
                    .fill(UIColors.quotaFillColor(percent: percent, accent: settings.currentTheme.uiAccent))
                    .frame(width: fillWidth, height: height)
            }
        }
        .frame(width: width, height: height)
    }

    private func hudIconButton(
        icon: String,
        help: String,
        active: Bool = false,
        isSpinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(
                    active ? settings.currentTheme.uiAccent : UIColors.textMuted
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default,
                    value: isSpinning
                )
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func timeAgoString(from date: Date?) -> String {
        guard let date = date else { return "never synced" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        let mins = seconds / 60
        return "\(mins)m ago"
    }
}
