import Foundation

/// 本地化：键为简体中文原文，翻译在 Resources/Localization/<lang>.lproj/Localizable.strings
/// （由 scripts/i18n.py 生成）。找不到翻译时显示原文。
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 带参数的本地化字符串，键中用 %@ / %ld 占位（数字不加千位分隔符，如 1280 × 720）
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
