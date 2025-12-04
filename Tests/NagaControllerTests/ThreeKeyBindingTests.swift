import XCTest
@testable import NagaController
import Carbon.HIToolbox

final class ThreeKeyBindingTests: XCTestCase {
    func testThreeModifierParsing() {
        // Test that a KeyStroke with three modifiers is correctly represented
        let stroke = KeyStroke(key: "1", modifiers: ["cmd", "ctrl", "shift"], keyCode: UInt16(kVK_ANSI_1))

        XCTAssertEqual(stroke.modifiers.count, 3)
        XCTAssertTrue(stroke.modifiers.contains("cmd"))
        XCTAssertTrue(stroke.modifiers.contains("ctrl"))
        XCTAssertTrue(stroke.modifiers.contains("shift"))
    }

    func testThreeModifierFormatting() {
        // Test that formatted shortcut includes all three modifiers
        let stroke = KeyStroke(key: "1", modifiers: ["cmd", "ctrl", "shift"], keyCode: UInt16(kVK_ANSI_1))
        let formatted = stroke.formattedShortcut()

        // Should contain symbols for cmd (⌘), ctrl (⌃), and shift (⇧)
        XCTAssertTrue(formatted.contains("⌘"))
        XCTAssertTrue(formatted.contains("⌃"))
        XCTAssertTrue(formatted.contains("⇧"))
        XCTAssertTrue(formatted.contains("1"))
    }

    func testFourModifierParsing() {
        // Test that even four modifiers work (cmd+ctrl+alt+shift)
        let stroke = KeyStroke(key: "a", modifiers: ["cmd", "ctrl", "alt", "shift"], keyCode: UInt16(kVK_ANSI_A))

        XCTAssertEqual(stroke.modifiers.count, 4)
        XCTAssertTrue(stroke.modifiers.contains("cmd"))
        XCTAssertTrue(stroke.modifiers.contains("ctrl"))
        XCTAssertTrue(stroke.modifiers.contains("alt"))
        XCTAssertTrue(stroke.modifiers.contains("shift"))
    }
}
