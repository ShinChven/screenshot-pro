import AppKit
import ServiceManagement
import SwiftUI

/// 设置页的临时状态（命令行工具链没有 SwiftUI 宏插件，不能用 @State）
final class LoginItemModel: ObservableObject {
    @Published var error: String?

    var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                error = nil
            } catch {
                self.error = L("设置失败：%@（建议先把应用放到「应用程序」文件夹）", error.localizedDescription)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var s = Settings.shared
    @ObservedObject private var login = LoginItemModel()
    var height: CGFloat = 680

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机自动启动", isOn: $login.enabled)
                if let loginError = login.error {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("快捷键") {
                HStack { Text("截图"); Spacer(); ShortcutField(shortcut: $s.captureShortcut).frame(width: 140, height: 24) }
                HStack { Text("长截图"); Spacer(); ShortcutField(shortcut: $s.scrollShortcut).frame(width: 140, height: 24) }
                HStack { Text("文字识别"); Spacer(); ShortcutField(shortcut: $s.ocrShortcut).frame(width: 140, height: 24) }
                Text("点击后按下新的组合键（至少包含 ⌘ ⌥ ⌃ 之一），按 Esc 取消。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("输出") {
                Picker("完成截图后（↩ / 双击）", selection: $s.defaultAction) {
                    ForEach(DefaultAction.allCases) { Text($0.title).tag($0) }
                }
                Picker("图片格式", selection: $s.format) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("按 Retina 原始分辨率导出（关闭则导出 1x）", isOn: $s.exportRetina)
                LabeledContent("保存位置") {
                    HStack {
                        Text((s.saveDirectory as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("选择…", action: chooseFolder)
                    }
                }
            }

            Section("截图") {
                Toggle("独立窗口截图包含阴影", isOn: $s.windowShadow)
                Toggle("显示放大镜与取色", isOn: $s.showMagnifier)
                Toggle("截图中包含鼠标指针", isOn: $s.showCursor)
                Toggle("播放快门声", isOn: $s.playSound)
                    .onChange(of: s.playSound) { _, on in if on { ShutterSound.play() } }
            }

            Section("选区") {
                TipRow("框选区域", .text("拖拽"))
                TipRow("选中窗口", .text("单击"))
                TipRow("截取独立窗口（带阴影）", .key("⌥"), .text("+ 单击"))
                TipRow("多选窗口并合成", .key("⌘"), .text("+ 单击，再按"), .key("↩"))
                TipRow("复制颜色 HEX / RGB", .key("C"), .text("/"), .key("⇧C"))
                TipRow("微调位置", .key("←"), .key("→"), .key("↑"), .key("↓"), .text("加"), .key("⇧"), .text("每次 10pt"))
            }

            Section("标注工具") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: Tool.allCases.count, by: 3)), id: \.self) { start in
                        GridRow {
                            ForEach(Tool.allCases[start..<min(start + 3, Tool.allCases.count)], id: \.self) { tool in
                                HStack(spacing: 8) {
                                    KeyCap(tool.key.uppercased())
                                    Text(tool.title)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                TipRow("画正方形 / 锁定 45°", .text("按住"), .key("⇧"))
                TipRow("编辑已有文字", .text("双击文字"))
            }

            Section("完成与编辑") {
                TipRow("完成（执行默认动作）", .key("↩"), .text("或在选区内双击"))
                TipRow("复制 / 保存", .key("⌘C"), .text("/"), .key("⌘S"))
                TipRow("撤销 / 重做", .key("⌘Z"), .text("/"), .key("⇧⌘Z"))
                TipRow("删除选中标注", .key("⌫"))
                TipRow("重新选区 / 退出", .text("右键"), .text("/"), .key("Esc"))
            }

            Section("钉图") {
                TipRow("缩放", .text("滚轮"), .text("/"), .key("⌘0"), .text("原始大小"))
                TipRow("透明度", .key("1"), .text("–"), .key("9"), .text("/"), .key("0"))
                TipRow("关闭", .text("双击"), .text("/"), .key("Esc"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: height)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = s.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            s.saveDirectory = url.path
        }
    }
}

/// 键帽样式的按键标签
struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 20)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
    }
}

/// 左边说明，右边按键组合
struct TipRow: View {
    enum Part: Hashable {
        case key(String)
        case text(String)
    }

    let title: String
    let parts: [Part]

    init(_ title: String, _ parts: Part...) {
        self.title = title
        self.parts = parts
    }

    var body: some View {
        LabeledContent(L(title)) {
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .key(let k): KeyCap(k)
                    case .text(let t): Text(L(t)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// SwiftUI 包装的快捷键录制控件
struct ShortcutField: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let v = ShortcutRecorderView()
        v.shortcut = shortcut
        v.onChange = { shortcut = $0 }
        return v
    }

    func updateNSView(_ v: ShortcutRecorderView, context: Context) {
        v.shortcut = shortcut
        v.onChange = { shortcut = $0 }
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?

    private var recording = false {
        didSet {
            needsDisplay = true
            if recording {
                HotKeyCenter.shared.unregisterAll()   // 录制时暂停全局快捷键，避免被拦截
            } else if oldValue {
                NotificationCenter.default.post(name: Settings.shortcutsChanged, object: nil)
            }
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { // Esc
            window?.makeFirstResponder(nil)
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }
        let s = Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: Shortcut.carbonModifiers(from: flags))
        shortcut = s
        onChange?(s)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()
        let text = recording ? L("请按下快捷键…") : (shortcut?.display ?? L("未设置"))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                withAttributes: attrs)
    }
}
