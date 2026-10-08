import SwiftUI

/// Edits stay inside the parent popover so clicking a field won't dismiss it.
struct AccountSectionHeader: View {
    let profileID: UUID
    let originalName: String
    var detail: String? = nil
    var summary: String? = nil
    @Bindable private var settings: SettingsStore
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @FocusState private var isNameFocused: Bool

    init(profileID: UUID, originalName: String, detail: String? = nil, summary: String? = nil,
         settings: SettingsStore = .shared) {
        self.profileID = profileID
        self.originalName = originalName
        self.detail = detail
        self.summary = summary
        self.settings = settings
    }

    private var collapsed: Bool { settings.profilePresentation.isCollapsed(profileID) }
    private var displayName: String { settings.displayName(for: profileID, defaultName: originalName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        settings.setProfileCollapsed(!collapsed, for: profileID)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(displayName)
                            .font(settings.uiProfile.accountFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let text = collapsed ? summary : detail {
                            Text(text)
                                .font(settings.uiProfile.detailFont.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(collapsed ? "Expand" : "Collapse") \(displayName)")
                .accessibilityLabel(displayName)
                .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
                .contextMenu { nameActions }

                Menu { nameActions } label: {
                    Image(systemName: "ellipsis")
                        .font(settings.uiProfile.quotaFont)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Account options")
                .accessibilityLabel("Options for \(displayName)")
            }

            if isEditingName {
                HStack(spacing: 5) {
                    TextField(originalName, text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .focused($isNameFocused)
                        .onSubmit { saveName() }
                        .onExitCommand { isEditingName = false }
                        .accessibilityLabel("Display name for \(originalName)")
                    Button("Save") { saveName() }
                    Button("Cancel") { isEditingName = false }
                }
                .controlSize(settings.uiProfile.controlSize)
                .onAppear { isNameFocused = true }
                Text("Leave blank to use \"\(originalName)\".")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var nameActions: some View {
        Button("Change display name…") {
            nameDraft = displayName
            isEditingName = true
        }
        if settings.profilePresentation.displayNames[profileID] != nil {
            Button("Use original name") {
                settings.setDisplayName("", for: profileID)
                isEditingName = false
            }
        }
    }

    private func saveName() {
        settings.setDisplayName(nameDraft, for: profileID)
        isEditingName = false
    }

    static func quotaSummary(windows: [UsageWindow]) -> String? {
        let parts = [FloatingQuotaPeriod.fiveHours, .weekly].compactMap { period -> String? in
            guard let remaining = windows.filter(period.matches).compactMap(\.remainingPercent)
                .filter({ $0.isFinite && (0...100).contains($0) }).min() else { return nil }
            return "\(period.label) \(Int(remaining.rounded()))%"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
