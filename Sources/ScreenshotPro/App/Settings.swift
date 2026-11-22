import AppKit
import Carbon.HIToolbox

/// 一个全局快捷键（Carbon 键码 + Carbon 修饰键）
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var modifierSymbols: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    var keyName: String { KeyNames.name(for: keyCode) }
    var display: String { modifierSymbols + keyName }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

enum KeyNames {
    static let map: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    static func name(for code: UInt32) -> String { map[code] ?? "#\(code)" }
}

enum DefaultAction: String, CaseIterable, Identifiable {
    case copy, save, copyAndSave
    var id: String { rawValue }
    var title: String {
        switch self {
        case .copy: return L("复制到剪贴板")
        case .save: return L("保存到文件")
        case .copyAndSave: return L("复制并保存")
        }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpg
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// 所有用户设置，持久化到 UserDefaults
final class Settings: ObservableObject {
    static let shared = Settings()
    static let shortcutsChanged = Notification.Name("ScreenshotPro.shortcutsChanged")

    private let d = UserDefaults.standard

    @Published var captureShortcut: Shortcut { didSet { store(captureShortcut, "captureShortcut") } }
    @Published var scrollShortcut: Shortcut { didSet { store(scrollShortcut, "scrollShortcut") } }
    @Published var ocrShortcut: Shortcut { didSet { store(ocrShortcut, "ocrShortcut") } }

    @Published var defaultAction: DefaultAction { didSet { d.set(defaultAction.rawValue, forKey: "defaultAction") } }
    @Published var format: ImageFormat { didSet { d.set(format.rawValue, forKey: "format") } }
    @Published var exportRetina: Bool { didSet { d.set(exportRetina, forKey: "exportRetina") } }
    @Published var saveDirectory: String { didSet { d.set(saveDirectory, forKey: "saveDirectory") } }
    @Published var windowShadow: Bool { didSet { d.set(windowShadow, forKey: "windowShadow") } }
    @Published var showMagnifier: Bool { didSet { d.set(showMagnifier, forKey: "showMagnifier") } }
    @Published var showCursor: Bool { didSet { d.set(showCursor, forKey: "showCursor") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }

    var colorIndex: Int {
        get { d.integer(forKey: "colorIndex") }
        set { d.set(newValue, forKey: "colorIndex") }
    }
    var widthLevel: Int {
        get { d.integer(forKey: "widthLevel") }
        set { d.set(newValue, forKey: "widthLevel") }
    }
    var filled: Bool {
        get { d.bool(forKey: "filled") }
        set { d.set(newValue, forKey: "filled") }
    }
    var mosaicBrush: Bool {
        get { d.bool(forKey: "mosaicBrush") }
        set { d.set(newValue, forKey: "mosaicBrush") }
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: (saveDirectory as NSString).expandingTildeInPath, isDirectory: true)
    }

    private init() {
        d.register(defaults: [
            "exportRetina": true, "windowShadow": true, "showMagnifier": true, "showCursor": false, "playSound": true,
            "colorIndex": 0, "widthLevel": 1, "filled": false, "mosaicBrush": false,
        ])
        captureShortcut = Self.load(d, "captureShortcut")
            ?? Shortcut(keyCode: 19, carbonModifiers: UInt32(cmdKey | shiftKey))      // ⇧⌘2
        scrollShortcut = Self.load(d, "scrollShortcut")
            ?? Shortcut(keyCode: 19, carbonModifiers: UInt32(cmdKey | optionKey))     // ⌥⌘2
        ocrShortcut = Self.load(d, "ocrShortcut")
            ?? Shortcut(keyCode: 18, carbonModifiers: UInt32(cmdKey | shiftKey))      // ⇧⌘1
        defaultAction = DefaultAction(rawValue: d.string(forKey: "defaultAction") ?? "") ?? .copy
        format = ImageFormat(rawValue: d.string(forKey: "format") ?? "") ?? .png
        exportRetina = d.bool(forKey: "exportRetina")
        saveDirectory = d.string(forKey: "saveDirectory") ?? "~/Desktop"
        windowShadow = d.bool(forKey: "windowShadow")
        showMagnifier = d.bool(forKey: "showMagnifier")
        showCursor = d.bool(forKey: "showCursor")
        playSound = d.bool(forKey: "playSound")
    }

    private static func load(_ d: UserDefaults, _ key: String) -> Shortcut? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private func store(_ s: Shortcut, _ key: String) {
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: key) }
        NotificationCenter.default.post(name: Self.shortcutsChanged, object: nil)
    }
}
