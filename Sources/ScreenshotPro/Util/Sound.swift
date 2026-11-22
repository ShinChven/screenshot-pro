import AppKit

/// 截图快门声（使用系统截图同款音效）
enum ShutterSound {
    private static let candidates = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
    ]

    private static let sound: NSSound? = {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let s = NSSound(contentsOfFile: path, byReference: true) { return s }
        }
        return NSSound(named: "Tink")
    }()

    static var isAvailable: Bool { sound != nil }

    static func play() {
        guard Settings.shared.playSound, let sound else { return }
        sound.stop()
        sound.play()
    }
}
