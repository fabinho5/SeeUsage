import AppKit

enum RefreshShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return event.type == .keyDown && !event.isARepeat && modifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "r"
    }
}
