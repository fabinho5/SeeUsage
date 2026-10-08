import Foundation

/// UI preferences are keyed by account identity, separately from provider configuration.
struct ProfilePresentation: Codable, Equatable, Sendable {
    private(set) var displayNames: [UUID: String] = [:]
    private(set) var collapsedProfiles: Set<UUID> = []

    func displayName(for id: UUID, defaultName: String) -> String {
        displayNames[id] ?? defaultName
    }

    func isCollapsed(_ id: UUID) -> Bool { collapsedProfiles.contains(id) }

    mutating func setDisplayName(_ name: String, for id: UUID) {
        let cleaned = String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(60))
        if cleaned.isEmpty { displayNames.removeValue(forKey: id) }
        else { displayNames[id] = cleaned }
    }

    mutating func setCollapsed(_ collapsed: Bool, for id: UUID) {
        if collapsed { collapsedProfiles.insert(id) }
        else { collapsedProfiles.remove(id) }
    }
}
