import AppKit
import SwiftUI

/// 带闭包的菜单项
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], image: NSImage? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: L(title), action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        self.image = image
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot Pro")
            button.image?.isTemplate = true
            button.toolTip = "Screenshot Pro"
        }
        menu.delegate = self
        statusItem.menu = menu

        registerHotKeys()
        NotificationCenter.default.addObserver(forName: Settings.shortcutsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKeys()
        }
        // 启动时不弹授权窗口（否则「重新启动」后会循环弹出），等第一次截图时再处理
    }

    func registerHotKeys() {
        let s = Settings.shared
        let failed = HotKeyCenter.shared.register([
            (s.captureShortcut, { CaptureSession.start(.normal) }),
            (s.scrollShortcut, { CaptureSession.start(.scroll) }),
            (s.ocrShortcut, { CaptureSession.start(.ocr) }),
        ])
        if !failed.isEmpty {
            Toast.show(L("快捷键 %@ 注册失败，可能已被其他应用占用", failed.map(\.display).joined(separator: ", ")))
        }
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        menu.addItem(item("截图", s.captureShortcut, symbol: "crop") { CaptureSession.start(.normal) })
        menu.addItem(item("长截图（滚动）", s.scrollShortcut, symbol: "arrow.up.and.down.text.horizontal") {
            CaptureSession.start(.scroll)
        })
        menu.addItem(item("文字识别（OCR）", s.ocrShortcut, symbol: "text.viewfinder") { CaptureSession.start(.ocr) })
        menu.addItem(ActionMenuItem("延时 3 秒截图", image: symbol("timer")) {
            Toast.show(L("3 秒后截图…"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { CaptureSession.start(.normal) }
        })
        menu.addItem(.separator())

        let recent = NSMenuItem(title: L("最近截图"), action: nil, keyEquivalent: "")
        recent.image = symbol("clock.arrow.circlepath")
        recent.submenu = buildHistoryMenu()
        menu.addItem(recent)
        menu.addItem(ActionMenuItem("钉住剪贴板中的图片", image: symbol("pin")) { PinWindow.pinClipboard() })
        if !PinWindow.all.isEmpty {
            menu.addItem(ActionMenuItem(L("关闭所有钉图（%ld）", PinWindow.all.count)) { PinWindow.closeAll() })
        }
        menu.addItem(.separator())

        menu.addItem(ActionMenuItem("设置…", key: ",", modifiers: .command, image: symbol("gearshape")) { [weak self] in
            self?.openSettings()
        })
        menu.addItem(ActionMenuItem("打开截图保存文件夹", image: symbol("folder")) {
            let url = Settings.shared.saveDirectoryURL
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        })
        if !Permissions.hasScreenCapture {
            menu.addItem(ActionMenuItem("⚠️ 授权屏幕录制…") { Permissions.showGuide() })
        }
        menu.addItem(ActionMenuItem("重新启动") { Permissions.relaunch() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("退出 Screenshot Pro", key: "q", modifiers: .command) { NSApp.terminate(nil) })
    }

    private func buildHistoryMenu() -> NSMenu {
        let sub = NSMenu()
        let items = History.items(limit: 12)
        if items.isEmpty {
            let empty = NSMenuItem(title: L("暂无截图"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        for entry in items {
            let title = "\(formatter.string(from: entry.date))  ·  \(entry.pixelSize)"
            let thumb = entry.thumbnail()
            let pin = ActionMenuItem(title, image: thumb) {
                if let (img, scale) = History.load(entry) { PinWindow.pinCentered(img, scale: scale) }
            }
            pin.toolTip = L("单击钉到屏幕；按住 ⌥ 单击复制")
            sub.addItem(pin)
            let copy = ActionMenuItem(L("%@（复制）", title), image: thumb) {
                if let (img, scale) = History.load(entry) {
                    Exporter.copy(img, scale: scale)
                    Toast.show(L("已复制到剪贴板"))
                }
            }
            copy.isAlternate = true
            copy.keyEquivalentModifierMask = .option
            sub.addItem(copy)
        }
        sub.addItem(.separator())
        sub.addItem(ActionMenuItem("打开历史文件夹") { NSWorkspace.shared.open(History.directory) })
        sub.addItem(ActionMenuItem("清空历史") { History.clear() })
        return sub
    }

    private func item(_ title: String, _ shortcut: Shortcut, symbol name: String,
                      handler: @escaping () -> Void) -> NSMenuItem {
        let key = shortcut.keyName.count == 1 ? shortcut.keyName.lowercased() : ""
        return ActionMenuItem(title, key: key, modifiers: key.isEmpty ? [] : shortcut.cocoaModifiers,
                              image: symbol(name), handler: handler)
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    // MARK: - 设置窗口

    func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            window.title = L("Screenshot Pro 设置")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
