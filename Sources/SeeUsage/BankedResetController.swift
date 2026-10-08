import AppKit
import Observation

/// Owns the confirmation and result independently of the transient menu bar popover.
@MainActor @Observable
final class BankedResetController {
    static let shared = BankedResetController(
        confirm: { name in
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Use a banked reset?"
            alert.informativeText = "This will use one reset credit on \(name)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Use Reset")
            return alert.runModal() == .alertSecondButtonReturn
        },
        consume: { profile, creditID in
            await UsageStore.shared.consumeBankedReset(for: profile, creditId: creditID)
        },
        showResult: { message in
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Banked Reset"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    )

    private(set) var activeProfileID: UUID?
    private let confirm: (String) -> Bool
    private let consume: (UsageProfile, String?) async -> (success: Bool, message: String)
    private let showResult: (String) -> Void

    init(confirm: @escaping (String) -> Bool,
         consume: @escaping (UsageProfile, String?) async -> (success: Bool, message: String),
         showResult: @escaping (String) -> Void) {
        self.confirm = confirm
        self.consume = consume
        self.showResult = showResult
    }

    @discardableResult
    func request(profile: UsageProfile, credit: BankedResetCredit, displayName: String) -> Task<Void, Never>? {
        guard activeProfileID == nil else { return nil }
        activeProfileID = profile.id
        // Defer until the native menu has finished dismissing. Capture the selection
        // here so closing/reopening the popover cannot change the intended account.
        return Task { @MainActor in
            defer { activeProfileID = nil }
            guard confirm(displayName) else { return }
            let result = await consume(profile, credit.serverCreditID)
            showResult(result.message)
        }
    }
}
