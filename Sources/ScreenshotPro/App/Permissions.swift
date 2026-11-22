import AppKit

enum Permissions {
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    private static var deniedAttempts = 0
    private static var guideShowing = false

    /// 检查屏幕录制权限，返回 false 表示暂时不能截图。
    /// 为避免反复弹窗：第一次只触发系统自带的授权提示；第二次显示一次说明弹窗；之后只显示底部提示。
    /// （授权后 CGPreflight 要重启应用才会变成 true，所以这里不能在每次检测失败时都弹窗。）
    @discardableResult
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        deniedAttempts += 1
        switch deniedAttempts {
        case 1:
            CGRequestScreenCaptureAccess()
            Toast.show(L("请在系统设置中允许屏幕录制，然后从菜单栏重新启动 Screenshot Pro"), duration: 4)
        case 2:
            showGuide()
        default:
            Toast.show(L("请在系统设置中允许屏幕录制，然后从菜单栏重新启动 Screenshot Pro"), duration: 4)
        }
        return false
    }

    static func showGuide() {
        guard !guideShowing else { return }
        guideShowing = true
        defer { guideShowing = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("需要「屏幕录制」权限")
        alert.informativeText = L("Screenshot Pro 需要屏幕录制权限才能截图。\n\n请在「系统设置 → 隐私与安全性 → 屏幕与系统录音」中打开 Screenshot Pro，然后点「重新启动」。\n\n如果列表里已经开着但仍然无法截图（常见于重新编译后），先把它删掉（−）再重新添加。")
        alert.addButton(withTitle: L("打开系统设置"))
        alert.addButton(withTitle: L("重新启动"))
        alert.addButton(withTitle: L("稍后"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSettings()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
