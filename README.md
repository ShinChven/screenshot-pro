# Screenshot Pro

A native macOS menu-bar screenshot tool: region / window / scrolling capture, annotations, mosaic, pin to screen, OCR. Swift + AppKit + ScreenCaptureKit, macOS 14+. UI in 10 languages.

参考 Xnip 的使用习惯做的 macOS 原生截图工具，常驻菜单栏。Swift + AppKit + ScreenCaptureKit，要求 macOS 14 及以上。与 Xnip 无关联。

## 安装 / 更新

需要 macOS 14+ 和 Command Line Tools（`xcode-select --install`），不用装 Xcode。

```bash
git clone https://github.com/ShinChven/screenshot-pro.git
cd screenshot-pro
./scripts/setup-signing.sh   # 可选，只需一次：创建本机签名证书
./scripts/install.sh
```

`install.sh` 会编译、打包、安装到 `/Applications/Screenshot Pro.app` 并启动。

首次使用要在「系统设置 → 隐私与安全性 → 屏幕与系统录音」里打开 **Screenshot Pro**，然后从菜单栏图标选「重新启动」。

> 第一次编译前建议执行 `./scripts/setup-signing.sh`：它在登录钥匙串里创建一个本机自用的签名证书，之后 `build.sh` 会自动用它签名，重新编译后屏幕录制权限不会失效。
> 没有这个证书时用的是 ad-hoc 签名，每次重新编译都要重新授权。如果截图只能截到壁纸，或者一直提示没有权限，执行
> `tccutil reset ScreenCapture com.local.screenshotpro`，再重新打开应用并授权。

## 功能

| 功能 | 操作 |
|---|---|
| 截图 | `⇧⌘2`（可在设置里修改） |
| 长截图（滚动） | `⌥⌘2`，或截图工具栏里的滚动按钮。选好区域后自己滚动内容，点「完成」 |
| 文字识别 OCR | `⇧⌘1`，选区后自动识别并复制，支持中英日文 |
| 延时截图 | 菜单栏 → 延时 3 秒截图 |
| 区域截图 | 拖拽框选；拖动边缘或角调整大小，拖动选区内部移动位置，方向键微调（⇧ 每次 10pt） |
| 窗口截图 | 鼠标悬停时自动高亮窗口，单击选中 |
| 独立窗口截图 | `⌥` + 单击，不受遮挡影响，可带阴影 |
| 多窗口截图 | `⌘` + 单击依次多选，按 `↩` 合成一张 |
| 放大镜 / 取色 | 选区前显示像素放大和颜色值；`C` 复制 HEX，`⇧C` 复制 RGB |
| 马赛克 | 默认是方形：画好后可拖动、拖控制点调整大小；样式栏可切换为涂抹模式 |
| 标注 | `R` 矩形 · `O` 椭圆 · `A` 箭头 · `L` 直线 · `P` 画笔 · `H` 荧光笔 · `T` 文字 · `M` 马赛克 · `N` 序号 |
| 编辑标注 | 任何工具下点中已有标注即可拖动；选中后矩形 / 椭圆 / 马赛克显示 8 个控制点调整大小，箭头 / 直线可拖两端；刚画完的标注自动选中；`⌫` 删除；选中后点颜色或粗细直接修改；双击文字重新编辑；按住 `⇧` 画正方形或锁定 45° |
| 序号 | 点一下放一个，自动递增；删除中间的序号后，后面的会自动重新编号 |
| 撤销 / 重做 | `⌘Z` / `⇧⌘Z` |
| 完成 | `↩` 或在选区内双击（默认复制到剪贴板，可在设置里改为保存，或复制并保存） |
| 复制 / 保存 | `⌘C` / `⌘S` |
| 钉图 | 工具栏图钉按钮。滚轮缩放，`1`–`9`/`0` 调整透明度，右键打开菜单，双击或 `Esc` 关闭 |
| 历史 | 菜单栏 → 最近截图，单击钉到屏幕，按住 `⌥` 单击复制 |
| 快门声 | 完成截图、钉图时播放系统截图音效，可在设置里关闭 |
| 取消 | `Esc`；右键退回到重新选区 |

## 多语言

跟随系统语言，支持 English、简体中文、繁體中文、日本語、한국어、Français、Deutsch、Español、Português (BR)、Русский，其他语言显示英文。

- 代码里的界面文字以简体中文为键：`L("中文")`、`L("已保存：%@", name)`；SwiftUI 字面量会自动本地化
- 翻译表在 `scripts/i18n.py`，`./scripts/build.sh` 会自动生成 `Resources/Localization/*.lproj`
- `python3 scripts/i18n.py --check`：检查是否有漏翻、字符串插值或占位符不一致
- 指定语言试运行：`"build/Screenshot Pro.app/Contents/MacOS/ScreenshotPro" -AppleLanguages "(ja)"`

## 开发

```bash
swift build                                       # 调试编译
.build/debug/ScreenshotPro --selftest              # 离线自检（长截图拼接、标注渲染、标注拖拽交互），不需要屏幕录制权限
./scripts/build.sh                                 # 打包到 build/Screenshot Pro.app
```

目录结构：

- `App/`：入口、菜单栏、全局快捷键（Carbon）、权限、设置
- `Capture/`：截屏（ScreenCaptureKit）、遮罩窗口、选区和窗口识别、放大镜、工具栏
- `Annotation/`：标注的数据模型和绘制
- `Features/`：钉图、长截图（采集 + 拼接算法）、OCR（Vision）
- `Output/`：复制和保存、历史记录

## License

[MIT](LICENSE)
