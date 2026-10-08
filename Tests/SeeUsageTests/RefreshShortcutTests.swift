import AppKit
import XCTest
@testable import SeeUsage

final class RefreshShortcutTests: XCTestCase {
    func testCommandRMatchesAcrossKeyboardCaseAndCapsLock() throws {
        XCTAssertTrue(RefreshShortcut.matches(try event(.command)))
        XCTAssertTrue(RefreshShortcut.matches(try event([.command, .capsLock], character: "R")))
    }

    func testOtherKeysModifiersAndRepeatsAreNotConsumed() throws {
        for modifiers: NSEvent.ModifierFlags in [[], .control, [.command, .shift], [.command, .option], [.command, .control]] {
            XCTAssertFalse(RefreshShortcut.matches(try event(modifiers)))
        }
        XCTAssertFalse(RefreshShortcut.matches(try event(.command, character: "s")))
        XCTAssertFalse(RefreshShortcut.matches(try event(.command, repeatKey: true)))
        XCTAssertFalse(RefreshShortcut.matches(try event(.command, type: .keyUp)))
    }

    private func event(_ modifiers: NSEvent.ModifierFlags, character: String = "r",
                       repeatKey: Bool = false, type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil, characters: character,
                                      charactersIgnoringModifiers: character, isARepeat: repeatKey, keyCode: 15))
    }
}
