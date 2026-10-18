import Foundation

public struct KeyboardShortcut: Codable, Equatable {
    public static let shift: UInt32 = 1, control: UInt32 = 2, option: UInt32 = 4, command: UInt32 = 8
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let keyName: String
    public init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName
    }
    public var isValid: Bool {
        keyCode < 128 && !(54...63).contains(keyCode) && keyCode != 53 &&
        modifiers & ~UInt32(15) == 0 && modifiers & 14 != 0 && !keyName.isEmpty && keyName.count <= 12
    }
    public func matches(_ other: KeyboardShortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public var display: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyName
    }
    public static let defaultCapture = KeyboardShortcut(keyCode: 8, modifiers: control | option, keyName: "C")
}

public final class UniCopySettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var joinLines: Bool {
        get { defaults.bool(forKey: "joinLines") }
        set { defaults.set(newValue, forKey: "joinLines") }
    }
    public var automaticLanguage: Bool {
        get { defaults.bool(forKey: "automaticLanguage") }
        set { defaults.set(newValue, forKey: "automaticLanguage") }
    }
    public var correctLanguage: Bool {
        get { defaults.bool(forKey: "correctLanguage") }
        set { defaults.set(newValue, forKey: "correctLanguage") }
    }
    /// The capture shortcut. Nil when the user cleared it; the default until they change it.
    public var shortcut: KeyboardShortcut? {
        get {
            guard let data = defaults.data(forKey: "captureShortcut") else {
                return defaults.bool(forKey: "captureShortcutCleared") ? nil : .defaultCapture
            }
            return (try? JSONDecoder().decode(KeyboardShortcut.self, from: data)).flatMap { $0.isValid ? $0 : nil } ?? .defaultCapture
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "captureShortcut"); defaults.removeObject(forKey: "captureShortcutCleared")
            } else {
                defaults.removeObject(forKey: "captureShortcut"); defaults.set(true, forKey: "captureShortcutCleared")
            }
        }
    }
    /// Text as it is copied: code payloads first, one per line, then the text, optionally
    /// joined into one paragraph. `flipJoin` reverses the join setting for one capture.
    public func output(_ recognised: String, codes: [String] = [], flipJoin: Bool = false) -> String {
        let text = joinLines != flipJoin ? recognised.split(whereSeparator: \.isNewline).joined(separator: " ") : recognised
        return (codes + [text]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
