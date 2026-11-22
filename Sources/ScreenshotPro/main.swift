import AppKit

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--l10n-sample") {
    print(Bundle.main.preferredLocalizations.first ?? "-", "|", L("截图"), "|", L("已选 %ld 个窗口 · 继续 ⌘单击添加 · ↩ 合成截图 · Esc 取消", 3),
          "|", L("已复制到剪贴板（%ld × %ld）", 1280, 720), "|", Tool.mosaic.title, "|", DefaultAction.copy.title)
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-settings"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    exit(SelfTest.renderSettings(to: CommandLine.arguments[i + 1]) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
