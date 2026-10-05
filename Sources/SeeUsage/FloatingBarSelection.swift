import SwiftUI

extension SettingsStore {
    func barVisibilityBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { !self.hudBarHiddenItems.contains(key) },
            set: { visible in
                if visible { self.hudBarHiddenItems.remove(key) }
                else { self.hudBarHiddenItems.insert(key) }
            }
        )
    }
}

/// Shared choices for Settings and the bar's context menu.
struct FloatingBarSelection: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        Group {
            Toggle("Codex", isOn: settings.barVisibilityBinding(for: FloatingBarVisibility.codex))
            ForEach(settings.orderedDisplayProfiles.filter { $0.provider == .codex }) { profile in
                Toggle(profile.name, isOn: settings.barVisibilityBinding(for: profile.id.uuidString))
                    .padding(.leading, 16)
                    .disabled(settings.hudBarHiddenItems.contains(FloatingBarVisibility.codex))
            }
            Toggle("Antigravity", isOn: settings.barVisibilityBinding(for: FloatingBarVisibility.antigravity))
            Toggle("Claude Code", isOn: settings.barVisibilityBinding(for: FloatingBarVisibility.claude))
        }
    }
}
