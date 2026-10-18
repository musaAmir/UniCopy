import XCTest
@testable import UniCopyCore

final class SettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "UniCopySettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    func testExistingPreferencesCarryOver() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "joinLines"); defaults.set(true, forKey: "correctLanguage")
        let settings = UniCopySettings(defaults: defaults)
        XCTAssertTrue(settings.joinLines); XCTAssertTrue(settings.correctLanguage); XCTAssertFalse(settings.automaticLanguage)
        XCTAssertEqual(settings.shortcut, .defaultCapture)
    }
    func testShortcutCanBeChangedClearedAndRestored() {
        let defaults = makeDefaults()
        let custom = KeyboardShortcut(keyCode: 17, modifiers: KeyboardShortcut.command | KeyboardShortcut.shift, keyName: "T")
        UniCopySettings(defaults: defaults).shortcut = custom
        XCTAssertEqual(UniCopySettings(defaults: defaults).shortcut, custom)
        UniCopySettings(defaults: defaults).shortcut = nil
        XCTAssertNil(UniCopySettings(defaults: defaults).shortcut)
        UniCopySettings(defaults: defaults).shortcut = .defaultCapture
        XCTAssertEqual(UniCopySettings(defaults: defaults).shortcut, .defaultCapture)
    }
    func testInvalidStoredShortcutFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "captureShortcut")
        XCTAssertEqual(UniCopySettings(defaults: defaults).shortcut, .defaultCapture)
        XCTAssertFalse(KeyboardShortcut(keyCode: 8, modifiers: KeyboardShortcut.shift, keyName: "C").isValid, "Shift alone is not enough")
    }
    func testJoinLinesOutput() {
        let settings = UniCopySettings(defaults: makeDefaults())
        XCTAssertEqual(settings.output("one\ntwo"), "one\ntwo")
        settings.joinLines = true
        XCTAssertEqual(settings.output("one\ntwo\n\nthree"), "one two three")
    }
}
