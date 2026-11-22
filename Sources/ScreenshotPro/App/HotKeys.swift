import AppKit
import Carbon.HIToolbox

/// 用 Carbon RegisterEventHotKey 注册全局快捷键（不需要辅助功能权限）
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    fileprivate var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// 注册一组快捷键，返回注册失败的快捷键
    @discardableResult
    func register(_ items: [(Shortcut, () -> Void)]) -> [Shortcut] {
        unregisterAll()
        installHandlerIfNeeded()
        var failed: [Shortcut] = []
        for (index, item) in items.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5350_5254), id: id) // 'SPRT'
            let status = RegisterEventHotKey(item.0.keyCode, item.0.carbonModifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = item.1
            } else {
                failed.append(item.0)
            }
        }
        return failed
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
