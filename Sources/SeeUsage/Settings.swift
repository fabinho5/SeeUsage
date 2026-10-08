import Foundation
import Observation
import ServiceManagement

public extension Notification.Name {
    static let menuBarSettingsChanged = Notification.Name("app.seeusage.menuBarSettingsChanged")
    static let uiProfileChanged = Notification.Name("app.seeusage.uiProfileChanged")
}

@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()
    private let presentationDefaults: UserDefaults
    private let usesSharedPresentationDefaults: Bool

    public static let antigravityProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static let suiteName = "app.seeusage.SeeUsage"
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public var selectedThemeID: String {
        didSet {
            Self.defaults.set(selectedThemeID, forKey: "selectedThemeID")
            UserDefaults.standard.set(selectedThemeID, forKey: "selectedThemeID")
            postDistributedChange("app.seeusage.themeChanged")
        }
    }

    public var currentTheme: AppTheme {
        ThemeRegistry.theme(for: selectedThemeID)
    }

    public var uiProfile: UIProfile {
        didSet {
            guard uiProfile != oldValue else { return }
            presentationDefaults.set(uiProfile.rawValue, forKey: "uiProfile")
            guard usesSharedPresentationDefaults else { return }
            UserDefaults.standard.set(uiProfile.rawValue, forKey: "uiProfile")
            NotificationCenter.default.post(name: .uiProfileChanged, object: self)
            postDistributedChange(Notification.Name.uiProfileChanged.rawValue)
        }
    }

    public var activityCollapsed: Bool {
        didSet {
            guard activityCollapsed != oldValue else { return }
            presentationDefaults.set(activityCollapsed, forKey: "activityCollapsed")
            guard usesSharedPresentationDefaults else { return }
            UserDefaults.standard.set(activityCollapsed, forKey: "activityCollapsed")
            postDistributedChange("app.seeusage.activityPresentationChanged")
        }
    }

    var menuBarPreferences: MenuBarPreferences {
        didSet {
            guard menuBarPreferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(menuBarPreferences) {
                presentationDefaults.set(data, forKey: "menuBarPreferences")
                if usesSharedPresentationDefaults {
                    UserDefaults.standard.set(data, forKey: "menuBarPreferences")
                }
            }
            guard usesSharedPresentationDefaults else { return }
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: self)
            postDistributedChange(Notification.Name.menuBarSettingsChanged.rawValue)
        }
    }

    public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            Self.defaults.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
            postDistributedChange("app.seeusage.menuBarSettingsChanged")
        }
    }

    public var menuBarShowIcon: Bool {
        didSet {
            Self.defaults.set(menuBarShowIcon, forKey: "menuBarShowIcon")
            UserDefaults.standard.set(menuBarShowIcon, forKey: "menuBarShowIcon")
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
            postDistributedChange("app.seeusage.menuBarSettingsChanged")
        }
    }

    public var launchAtLogin: Bool {
        didSet {
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    public var notificationsEnabled: Bool {
        didSet {
            Self.defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            postPreferencesChanged()
        }
    }

    public var notifyOnCritical: Bool {
        didSet {
            Self.defaults.set(notifyOnCritical, forKey: "notifyOnCritical")
            UserDefaults.standard.set(notifyOnCritical, forKey: "notifyOnCritical")
            postPreferencesChanged()
        }
    }

    public var criticalThresholdPercent: Int {
        didSet {
            Self.defaults.set(criticalThresholdPercent, forKey: "criticalThresholdPercent")
            UserDefaults.standard.set(criticalThresholdPercent, forKey: "criticalThresholdPercent")
            postPreferencesChanged()
        }
    }

    public var notifyOnReset: Bool {
        didSet {
            Self.defaults.set(notifyOnReset, forKey: "notifyOnReset")
            UserDefaults.standard.set(notifyOnReset, forKey: "notifyOnReset")
            postPreferencesChanged()
        }
    }

    public var notifyOnBankedResetExpiring: Bool {
        didSet {
            Self.defaults.set(notifyOnBankedResetExpiring, forKey: "notifyOnBankedResetExpiring")
            UserDefaults.standard.set(notifyOnBankedResetExpiring, forKey: "notifyOnBankedResetExpiring")
            postPreferencesChanged()
        }
    }

    public var notificationSoundEnabled: Bool {
        didSet {
            Self.defaults.set(notificationSoundEnabled, forKey: "notificationSoundEnabled")
            UserDefaults.standard.set(notificationSoundEnabled, forKey: "notificationSoundEnabled")
            postPreferencesChanged()
        }
    }

    public var hudEnabled: Bool {
        didSet {
            Self.defaults.set(hudEnabled, forKey: "hudEnabled")
            UserDefaults.standard.set(hudEnabled, forKey: "hudEnabled")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var companionEnabled: Bool {
        didSet {
            guard oldValue != companionEnabled else { return }
            Self.defaults.set(companionEnabled, forKey: "companionEnabled")
            UserDefaults.standard.set(companionEnabled, forKey: "companionEnabled")
            postDistributedChange("app.seeusage.companionSettingsChanged")
        }
    }

    public var companionWanders: Bool {
        didSet {
            guard oldValue != companionWanders else { return }
            Self.defaults.set(companionWanders, forKey: "companionWanders")
            UserDefaults.standard.set(companionWanders, forKey: "companionWanders")
            postDistributedChange("app.seeusage.companionSettingsChanged")
        }
    }

    public var hudAlwaysOnTop: Bool {
        didSet {
            Self.defaults.set(hudAlwaysOnTop, forKey: "hudAlwaysOnTop")
            UserDefaults.standard.set(hudAlwaysOnTop, forKey: "hudAlwaysOnTop")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var hudCompactMode: Bool {
        didSet {
            Self.defaults.set(hudCompactMode, forKey: "hudCompactMode")
            UserDefaults.standard.set(hudCompactMode, forKey: "hudCompactMode")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var hudOpacity: Double {
        didSet {
            Self.defaults.set(hudOpacity, forKey: "hudOpacity")
            UserDefaults.standard.set(hudOpacity, forKey: "hudOpacity")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var hudBarOrientation: FloatingBarOrientation {
        didSet {
            Self.defaults.set(hudBarOrientation.rawValue, forKey: "hudBarOrientation")
            UserDefaults.standard.set(hudBarOrientation.rawValue, forKey: "hudBarOrientation")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var hudBarQuotas: FloatingBarQuotas {
        didSet {
            Self.defaults.set(hudBarQuotas.rawValue, forKey: "hudBarQuotas")
            UserDefaults.standard.set(hudBarQuotas.rawValue, forKey: "hudBarQuotas")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var hudBarHiddenItems: Set<String> {
        didSet {
            guard oldValue != hudBarHiddenItems else { return }
            let items = hudBarHiddenItems.sorted()
            Self.defaults.set(items, forKey: "hudBarHiddenItems")
            UserDefaults.standard.set(items, forKey: "hudBarHiddenItems")
            postDistributedChange("app.seeusage.hudSettingsChanged")
        }
    }

    public var refreshIntervalMinutes: Int {
        didSet {
            Self.defaults.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
            postPreferencesChanged()
        }
    }

    public var codexExecutableOverride: String {
        didSet {
            Self.defaults.set(codexExecutableOverride, forKey: "codexExecutableOverride")
            UserDefaults.standard.set(codexExecutableOverride, forKey: "codexExecutableOverride")
            postPreferencesChanged()
        }
    }

    public var antigravityExecutableOverride: String {
        didSet {
            Self.defaults.set(antigravityExecutableOverride, forKey: "antigravityExecutableOverride")
            UserDefaults.standard.set(antigravityExecutableOverride, forKey: "antigravityExecutableOverride")
            postPreferencesChanged()
        }
    }

    public var codexProfiles: [UsageProfile] {
        didSet {
            saveProfiles()
        }
    }

    public var profileDisplayOrder: [UUID] {
        didSet {
            let values = profileDisplayOrder.map(\.uuidString)
            Self.defaults.set(values, forKey: "profileDisplayOrder")
            UserDefaults.standard.set(values, forKey: "profileDisplayOrder")
            postPreferencesChanged()
        }
    }

    var profilePresentation: ProfilePresentation {
        didSet {
            guard profilePresentation != oldValue else { return }
            if let data = try? JSONEncoder().encode(profilePresentation) {
                presentationDefaults.set(data, forKey: "profilePresentation")
                if usesSharedPresentationDefaults {
                    UserDefaults.standard.set(data, forKey: "profilePresentation")
                }
            }
            guard usesSharedPresentationDefaults else { return }
            postDistributedChange("app.seeusage.profilePresentationChanged")
            if profilePresentation.displayNames != oldValue.displayNames {
                postDistributedChange("app.seeusage.hudSettingsChanged")
            }
        }
    }

    public init(presentationDefaults: UserDefaults? = nil) {
        self.presentationDefaults = presentationDefaults ?? Self.defaults
        self.usesSharedPresentationDefaults = presentationDefaults == nil
        let prefs = Self.defaults
        let fallback = UserDefaults.standard

        self.selectedThemeID = prefs.string(forKey: "selectedThemeID")
            ?? fallback.string(forKey: "selectedThemeID")
            ?? "t3-default"

        let rawMode = prefs.string(forKey: "menuBarDisplayMode")
            ?? fallback.string(forKey: "menuBarDisplayMode")
            ?? "percent"
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: rawMode) ?? .percent

        let showIcon = prefs.object(forKey: "menuBarShowIcon") as? Bool
            ?? fallback.object(forKey: "menuBarShowIcon") as? Bool
            ?? true
        self.menuBarShowIcon = showIcon

        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = false
        }

        self.notificationsEnabled = prefs.object(forKey: "notificationsEnabled") as? Bool
            ?? fallback.object(forKey: "notificationsEnabled") as? Bool
            ?? true

        self.notifyOnCritical = prefs.object(forKey: "notifyOnCritical") as? Bool
            ?? fallback.object(forKey: "notifyOnCritical") as? Bool
            ?? true

        let thresh = prefs.integer(forKey: "criticalThresholdPercent") != 0
            ? prefs.integer(forKey: "criticalThresholdPercent")
            : fallback.integer(forKey: "criticalThresholdPercent")
        self.criticalThresholdPercent = thresh > 0 ? thresh : 15

        self.notifyOnReset = prefs.object(forKey: "notifyOnReset") as? Bool
            ?? fallback.object(forKey: "notifyOnReset") as? Bool
            ?? true

        self.notifyOnBankedResetExpiring = prefs.object(forKey: "notifyOnBankedResetExpiring") as? Bool
            ?? fallback.object(forKey: "notifyOnBankedResetExpiring") as? Bool
            ?? true

        self.notificationSoundEnabled = prefs.object(forKey: "notificationSoundEnabled") as? Bool
            ?? fallback.object(forKey: "notificationSoundEnabled") as? Bool
            ?? true

        self.hudEnabled = prefs.object(forKey: "hudEnabled") as? Bool
            ?? fallback.object(forKey: "hudEnabled") as? Bool
            ?? false

        self.companionEnabled = prefs.object(forKey: "companionEnabled") as? Bool
            ?? fallback.object(forKey: "companionEnabled") as? Bool
            ?? false
        self.companionWanders = prefs.object(forKey: "companionWanders") as? Bool
            ?? fallback.object(forKey: "companionWanders") as? Bool
            ?? true

        self.hudAlwaysOnTop = prefs.object(forKey: "hudAlwaysOnTop") as? Bool
            ?? fallback.object(forKey: "hudAlwaysOnTop") as? Bool
            ?? true

        self.hudCompactMode = prefs.object(forKey: "hudCompactMode") as? Bool
            ?? fallback.object(forKey: "hudCompactMode") as? Bool
            ?? true

        let op = prefs.double(forKey: "hudOpacity") != 0
            ? prefs.double(forKey: "hudOpacity")
            : fallback.double(forKey: "hudOpacity")
        self.hudOpacity = op > 0 ? op : 0.88

        self.hudBarOrientation = FloatingBarOrientation(rawValue:
            prefs.string(forKey: "hudBarOrientation") ?? fallback.string(forKey: "hudBarOrientation") ?? "horizontal"
        ) ?? .horizontal
        self.hudBarQuotas = FloatingBarQuotas(rawValue:
            prefs.string(forKey: "hudBarQuotas") ?? fallback.string(forKey: "hudBarQuotas") ?? "both"
        ) ?? .both
        self.hudBarHiddenItems = Set(prefs.stringArray(forKey: "hudBarHiddenItems")
            ?? fallback.stringArray(forKey: "hudBarHiddenItems") ?? [])

        let interval = prefs.integer(forKey: "refreshIntervalMinutes") != 0
            ? prefs.integer(forKey: "refreshIntervalMinutes")
            : fallback.integer(forKey: "refreshIntervalMinutes")
        self.refreshIntervalMinutes = interval > 0 ? interval : 5

        self.codexExecutableOverride = prefs.string(forKey: "codexExecutableOverride")
            ?? fallback.string(forKey: "codexExecutableOverride")
            ?? ""
        self.antigravityExecutableOverride = prefs.string(forKey: "antigravityExecutableOverride")
            ?? fallback.string(forKey: "antigravityExecutableOverride")
            ?? ""

        let profileData = prefs.data(forKey: "codexProfiles") ?? fallback.data(forKey: "codexProfiles")
        let profiles: [UsageProfile]
        if let data = profileData,
           let storedProfiles = try? JSONDecoder().decode([UsageProfile].self, from: data) {
            profiles = storedProfiles
        } else {
            profiles = Self.discoverCodexProfiles()
            if let data = try? JSONEncoder().encode(profiles) {
                prefs.set(data, forKey: "codexProfiles")
                fallback.set(data, forKey: "codexProfiles")
            }
        }
        self.codexProfiles = profiles

        let storedDisplayOrder = (prefs.stringArray(forKey: "profileDisplayOrder")
            ?? fallback.stringArray(forKey: "profileDisplayOrder") ?? [])
            .compactMap(UUID.init(uuidString:))
        self.profileDisplayOrder = Self.normalizedDisplayOrder(storedDisplayOrder, profiles: profiles)
        let presentationData = self.presentationDefaults.data(forKey: "profilePresentation")
            ?? (usesSharedPresentationDefaults ? fallback.data(forKey: "profilePresentation") : nil)
        self.profilePresentation = presentationData.flatMap { try? JSONDecoder().decode(ProfilePresentation.self, from: $0) }
            ?? ProfilePresentation()
        let storedUIProfile = self.presentationDefaults.string(forKey: "uiProfile")
            ?? (usesSharedPresentationDefaults ? fallback.string(forKey: "uiProfile") : nil)
        self.uiProfile = storedUIProfile.flatMap(UIProfile.init(rawValue:)) ?? .compact
        self.activityCollapsed = (self.presentationDefaults.object(forKey: "activityCollapsed") as? Bool)
            ?? (usesSharedPresentationDefaults ? fallback.object(forKey: "activityCollapsed") as? Bool : nil)
            ?? false
        let menuBarData = self.presentationDefaults.data(forKey: "menuBarPreferences")
            ?? (usesSharedPresentationDefaults ? fallback.data(forKey: "menuBarPreferences") : nil)
        self.menuBarPreferences = menuBarData.flatMap { try? JSONDecoder().decode(MenuBarPreferences.self, from: $0) }
            ?? MenuBarPreferences()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.activityPresentationChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.usesSharedPresentationDefaults,
                  let collapsed = self.presentationDefaults.object(forKey: "activityCollapsed") as? Bool,
                  collapsed != self.activityCollapsed else { return }
            self.activityCollapsed = collapsed
        }

        DistributedNotificationCenter.default().addObserver(
            forName: .uiProfileChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.usesSharedPresentationDefaults,
                  let raw = self.presentationDefaults.string(forKey: "uiProfile"),
                  let profile = UIProfile(rawValue: raw), profile != self.uiProfile else { return }
            self.uiProfile = profile
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.profilePresentationChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.usesSharedPresentationDefaults,
                  let data = self.presentationDefaults.data(forKey: "profilePresentation"),
                  let presentation = try? JSONDecoder().decode(ProfilePresentation.self, from: data),
                  presentation != self.profilePresentation else { return }
            self.profilePresentation = presentation
        }

        // Listen for live theme updates across processes
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.themeChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let newTheme = Self.defaults.string(forKey: "selectedThemeID"),
               newTheme != self?.selectedThemeID {
                self?.selectedThemeID = newTheme
            }
        }

        // Listen for live menu bar settings updates across processes
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.menuBarSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let raw = Self.defaults.string(forKey: "menuBarDisplayMode"),
               let mode = MenuBarDisplayMode(rawValue: raw),
               mode != self.menuBarDisplayMode {
                self.menuBarDisplayMode = mode
            }
            if let icon = Self.defaults.object(forKey: "menuBarShowIcon") as? Bool,
               icon != self.menuBarShowIcon {
                self.menuBarShowIcon = icon
            }
            if self.usesSharedPresentationDefaults,
               let data = self.presentationDefaults.data(forKey: "menuBarPreferences"),
               let preferences = try? JSONDecoder().decode(MenuBarPreferences.self, from: data),
               preferences != self.menuBarPreferences {
                self.menuBarPreferences = preferences
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.companionSettingsChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let enabled = Self.defaults.object(forKey: "companionEnabled") as? Bool,
               enabled != self.companionEnabled { self.companionEnabled = enabled }
            if let wanders = Self.defaults.object(forKey: "companionWanders") as? Bool,
               wanders != self.companionWanders { self.companionWanders = wanders }
        }

        // Listen for live HUD settings updates across processes
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.hudSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let enabled = Self.defaults.object(forKey: "hudEnabled") as? Bool,
               enabled != self.hudEnabled {
                self.hudEnabled = enabled
            }
            if let onTop = Self.defaults.object(forKey: "hudAlwaysOnTop") as? Bool,
               onTop != self.hudAlwaysOnTop {
                self.hudAlwaysOnTop = onTop
            }
            if let compact = Self.defaults.object(forKey: "hudCompactMode") as? Bool,
               compact != self.hudCompactMode {
                self.hudCompactMode = compact
            }
            if let opacity = Self.defaults.object(forKey: "hudOpacity") as? Double,
               opacity != self.hudOpacity {
                self.hudOpacity = opacity
            }
            if let raw = Self.defaults.string(forKey: "hudBarOrientation"),
               let orientation = FloatingBarOrientation(rawValue: raw),
               orientation != self.hudBarOrientation {
                self.hudBarOrientation = orientation
            }
            if let raw = Self.defaults.string(forKey: "hudBarQuotas"),
               let quotas = FloatingBarQuotas(rawValue: raw),
               quotas != self.hudBarQuotas {
                self.hudBarQuotas = quotas
            }
            if let items = Self.defaults.stringArray(forKey: "hudBarHiddenItems"),
               Set(items) != self.hudBarHiddenItems {
                self.hudBarHiddenItems = Set(items)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.seeusage.preferencesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let prefs = Self.defaults
            let fallback = UserDefaults.standard

            if let value = prefs.object(forKey: "notificationsEnabled") as? Bool,
               value != self.notificationsEnabled {
                self.notificationsEnabled = value
                if value {
                    Task { @MainActor in NotificationManager.shared.requestAuthorization() }
                }
            }
            if let value = prefs.object(forKey: "notifyOnCritical") as? Bool,
               value != self.notifyOnCritical { self.notifyOnCritical = value }
            let threshold = prefs.integer(forKey: "criticalThresholdPercent")
            if threshold > 0, threshold != self.criticalThresholdPercent { self.criticalThresholdPercent = threshold }
            if let value = prefs.object(forKey: "notifyOnReset") as? Bool,
               value != self.notifyOnReset { self.notifyOnReset = value }
            if let value = prefs.object(forKey: "notifyOnBankedResetExpiring") as? Bool,
               value != self.notifyOnBankedResetExpiring { self.notifyOnBankedResetExpiring = value }
            if let value = prefs.object(forKey: "notificationSoundEnabled") as? Bool,
               value != self.notificationSoundEnabled { self.notificationSoundEnabled = value }
            let interval = prefs.integer(forKey: "refreshIntervalMinutes")
            if interval > 0, interval != self.refreshIntervalMinutes { self.refreshIntervalMinutes = interval }
            if let value = prefs.string(forKey: "codexExecutableOverride"), value != self.codexExecutableOverride {
                self.codexExecutableOverride = value
            }
            if let value = prefs.string(forKey: "antigravityExecutableOverride"), value != self.antigravityExecutableOverride {
                self.antigravityExecutableOverride = value
            }
            if let data = prefs.data(forKey: "codexProfiles") ?? fallback.data(forKey: "codexProfiles"),
               let profiles = try? JSONDecoder().decode([UsageProfile].self, from: data),
               profiles != self.codexProfiles {
                self.codexProfiles = profiles
            }
            let storedOrder = (prefs.stringArray(forKey: "profileDisplayOrder")
                ?? fallback.stringArray(forKey: "profileDisplayOrder") ?? [])
                .compactMap(UUID.init(uuidString:))
            let normalizedOrder = Self.normalizedDisplayOrder(storedOrder, profiles: self.codexProfiles)
            if normalizedOrder != self.profileDisplayOrder {
                self.profileDisplayOrder = normalizedOrder
            }
        }
    }

    public func selectTheme(_ id: String) {
        self.selectedThemeID = id
    }

    public func selectMenuBarMode(_ mode: MenuBarDisplayMode) {
        self.menuBarDisplayMode = mode
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Could not update Launch at Login: \(error)")
            }
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(codexProfiles) {
            Self.defaults.set(data, forKey: "codexProfiles")
            UserDefaults.standard.set(data, forKey: "codexProfiles")
        }
        let normalizedOrder = Self.normalizedDisplayOrder(profileDisplayOrder, profiles: codexProfiles)
        if normalizedOrder != profileDisplayOrder {
            profileDisplayOrder = normalizedOrder
        }
        postPreferencesChanged()
        Task { @MainActor in
            UsageStore.shared.pruneInactiveSnapshots()
            await UsageStore.shared.refresh(forceAfterCurrent: true)
        }
    }

    public var orderedDisplayProfiles: [UsageProfile] {
        let profilesByID = Dictionary(uniqueKeysWithValues: codexProfiles.map { ($0.id, $0) })
        return profileDisplayOrder.compactMap { id in
            if let profile = profilesByID[id] { return profile }
            if id == Self.antigravityProfileID {
                return UsageProfile(id: id, provider: .antigravity, name: "Antigravity")
            }
            return nil
        }
    }

    func displayName(for profile: UsageProfile) -> String {
        displayName(for: profile.id, defaultName: profile.name)
    }

    func displayName(for id: UUID, defaultName: String) -> String {
        profilePresentation.displayName(for: id, defaultName: defaultName)
    }

    func setDisplayName(_ name: String, for id: UUID) {
        profilePresentation.setDisplayName(name, for: id)
    }

    func setProfileCollapsed(_ collapsed: Bool, for id: UUID) {
        profilePresentation.setCollapsed(collapsed, for: id)
    }

    public func moveDisplayProfile(_ profileID: UUID, relativeTo targetID: UUID) {
        var reordered = orderedDisplayProfiles.map(\.id)
        guard let sourceIndex = reordered.firstIndex(of: profileID),
              let targetIndex = reordered.firstIndex(of: targetID),
              sourceIndex != targetIndex else { return }

        reordered.remove(at: sourceIndex)
        guard let updatedTargetIndex = reordered.firstIndex(of: targetID) else { return }
        let insertionIndex = sourceIndex < targetIndex ? updatedTargetIndex + 1 : updatedTargetIndex
        reordered.insert(profileID, at: insertionIndex)

        if reordered != profileDisplayOrder {
            profileDisplayOrder = reordered
        }
    }

    private static func normalizedDisplayOrder(_ preferred: [UUID], profiles: [UsageProfile]) -> [UUID] {
        let codexIDs = profiles.map(\.id)
        let validIDs = Set(codexIDs + [antigravityProfileID])
        var seen = Set<UUID>()
        var order = preferred.filter { validIDs.contains($0) && seen.insert($0).inserted }
        let missingCodexIDs = codexIDs.filter { seen.insert($0).inserted }

        if let antigravityIndex = order.firstIndex(of: antigravityProfileID) {
            order.insert(contentsOf: missingCodexIDs, at: antigravityIndex)
        } else {
            order.append(contentsOf: missingCodexIDs)
            order.append(antigravityProfileID)
        }
        return order
    }

    private func postPreferencesChanged() {
        postDistributedChange("app.seeusage.preferencesChanged")
    }

    private func postDistributedChange(_ name: String) {
        let bundleID = Bundle.main.bundleIdentifier
        guard bundleID == nil || bundleID == "app.seeusage.SeeUsage" else { return }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(name),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public func addProfile(name: String, path: String) {
        let cleanedPath = path.trimmingCharacters(in: .whitespaces)
        let profile = UsageProfile(
            id: UUIDHelper.deterministic(for: "codex:\(cleanedPath)"),
            provider: .codex,
            name: name.trimmingCharacters(in: .whitespaces),
            homePath: cleanedPath
        )
        if !codexProfiles.contains(where: { $0.id == profile.id }) {
            codexProfiles.append(profile)
        }
    }

    public func removeProfile(id: UUID) {
        codexProfiles.removeAll { $0.id == id }
    }

    public func renameProfile(id: UUID, newName: String) {
        if let index = codexProfiles.firstIndex(where: { $0.id == id }) {
            codexProfiles[index].name = newName.trimmingCharacters(in: .whitespaces)
        }
    }

    public static func discoverCodexProfiles() -> [UsageProfile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let defaultCodex = "\(home)/.codex"
        var paths: [(String, String)] = []

        if fm.fileExists(atPath: defaultCodex), isCodexHome(path: defaultCodex) {
            paths.append(("Main", defaultCodex))
        }

        let profilesDir = "\(home)/.codex-profiles"
        if let items = try? fm.contentsOfDirectory(atPath: profilesDir) {
            for item in items.sorted() {
                let fullPath = "\(profilesDir)/\(item)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir),
                   isDir.boolValue,
                   isCodexHome(path: fullPath) {
                    paths.append((item.capitalized, fullPath))
                }
            }
        }

        return paths.map { name, path in
            UsageProfile(
                id: UUIDHelper.deterministic(for: "codex:\(path)"),
                provider: .codex,
                name: name,
                homePath: path
            )
        }
    }

    private static func isCodexHome(path: String) -> Bool {
        let fm = FileManager.default
        let markers = ["auth.json", "config.toml", "state.sqlite", "sessions"]
        for marker in markers {
            if fm.fileExists(atPath: "\(path)/\(marker)") {
                return true
            }
        }
        return false
    }
}
