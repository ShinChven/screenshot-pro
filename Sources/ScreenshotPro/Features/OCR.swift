import AppKit
import Vision

enum OCRService {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func run(on image: CGImage) {
        Toast.show(L("正在识别文字…"), duration: 5)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try recognize(image) }
            DispatchQueue.main.async {
                switch result {
                case .success(let text) where text.isEmpty:
                    Toast.show(L("没有识别到文字"))
                case .success(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    let count = text.split(separator: "\n").count
                    Toast.show(L("已复制识别结果（%ld 行）", count))
                    OCRResultWindow.show(text)
                case .failure(let error):
                    Toast.show(L("识别失败：%@", error.localizedDescription))
                }
            }
        }
    }
}

/// 显示识别结果，可编辑后再复制
final class OCRResultWindow: NSWindow {
    private static var current: OCRResultWindow?
    private let textView: NSTextView

    static func show(_ text: String) {
        current?.orderOut(nil)
        let w = OCRResultWindow(text: text)
        current = w
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    private init(text: String) {
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 340),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        title = L("识别结果（已复制到剪贴板）")
        isReleasedWhenClosed = false
        level = .floating
        minSize = CGSize(width: 300, height: 200)

        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let copy = NSButton(title: L("复制全部"), target: self, action: #selector(copyAll))
        copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r"
        copy.keyEquivalentModifierMask = .command
        let close = NSButton(title: L("关闭"), target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded

        let buttons = NSStackView(views: [NSView(), close, copy])
        buttons.orientation = .horizontal
        let root = NSStackView(views: [scroll, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
        ])
    }

    @objc private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        Toast.show(L("已复制"))
    }

    @objc private func closeWindow() { orderOut(nil) }
}
