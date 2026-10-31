# DropShelf — 零延迟 macOS 原生悬浮文件暂存架

**DropShelf** 是一款使用 `Swift + AppKit + SwiftUI` 从零构建的轻量、极速、纯原生 macOS 悬浮文件架工具（Dropover 的开源免费替代方案）。

无需忍受未买断时的 3 秒倒计时弹窗，无需繁琐配置，**晃动鼠标 0 毫秒即时唤起**，支持全屏应用悬浮跟随、多架子并行管理、空格键 QuickLook 预览与一键打包 ZIP。

---

## ✨ 核心特性

- ⚡ **零延迟即时响应**：彻底告别任何等待读秒或订阅限制，唤起、拖入、拖出均为 0ms 原生响应。
- 🖱️ **多种丝滑唤起方式**：
  - **拖拽晃动唤起（Shake to Summon）**：按住文件/图片/文字来回晃动鼠标，架子立即在光标旁弹出（支持低/中/高三档灵敏度调节）。
  - **按住 `Option (⌥)` 拖拽唤起**：拖拽时按住 `⌥` 键，无需晃动直接弹出文件架。
  - **状态栏图标拖拽**：直接将文件拖到屏幕顶部菜单栏的 `DropShelf` 图标上即可新建架子。
  - **全局快捷键**：随时使用 `⇧ + ⌘ + D` 在鼠标位置新建空白架子，或用 `⌥ + ⇧ + Space` 一键折叠/展开所有架子。
- 🗂️ **全类型内容支持**：
  - **本地文件与文件夹**：仅保存路径引用（`URL`），0 磁盘额外占用，哪怕拖入几十 GB 的大文件也瞬间完成。
  - **网页图片 / 截图 / 文本片段 / 网址链接**：自动在系统临时缓存区落地为 `.png`、`.txt` 或 `.webloc` 文件，方便作为标准文件拖入任意第三方 App，并在使用后自动清理。
- 🪟 **精致毛玻璃悬浮窗与多架子管理**：
  - 基于原生 `NSPanel`（`.nonactivatingPanel` + `.canJoinAllSpaces`），置顶悬浮且不抢占当前活动窗口焦点，支持跨桌面空间与全屏应用跟随。
  - 支持 **堆叠卡片视图（Stack View）** 与 **多选网格视图（Grid View）** 自由切换。
  - 支持将架子收起为极简的**迷你胶囊（Compact Pill）**，或点击图钉（Pin）固定在桌面上长期使用。
- 🛠️ **高频效率动作**：
  - **空格键快速预览（QuickLook）**：选中架子按 `Space` 直接呼出 macOS 原生快速预览面板。
  - **一键打包 ZIP**：点击底部拉链图标，直接调用系统原生 `ditto` 将架子内所有文件压缩为一个 `.zip` 包并替换到架子中，随拖随发。
  - **右键菜单与快捷键**：支持 `⌘C` 复制文件、`⌘V` 从剪贴板粘贴、复制文件路径、在 Finder 中显示、批量移动到指定文件夹。

---

## 🚀 快速安装与构建

### 环境要求
- macOS 13.0 (Ventura) 或更高版本
- Xcode Command Line Tools (`xcode-select --install`)

### 一键编译并安装到 `/Applications`

```bash
# 1. 克隆仓库
git clone https://github.com/ihatetheworld-ckl/DropShelf.git
cd DropShelf

# 2. 运行一键构建脚本（自动编译 Release 二进制、生成高清矢量图标并完成本地签名）
./scripts/build_app.sh

# 3. 移入应用程序目录并启动
cp -R build/DropShelf.app /Applications/
open /Applications/DropShelf.app
```

---

## ⌨️ 交互手势与快捷键一览

| 操作 / 快捷键 | 功能说明 |
| :--- | :--- |
| **拖拽文件 + 晃动鼠标** | 在当前光标旁立即唤起新的悬浮文件架 |
| **拖拽文件 + 按住 `⌥ Option`** | 无需晃动，立即在当前光标位置唤起文件架 |
| **`⇧ + ⌘ + D`** | 全局快捷键：在鼠标位置新建空白文件架 |
| **`⌥ + ⇧ + Space`** | 全局快捷键：一键将所有打开的文件架收起为迷你胶囊 / 重新展开 |
| **按住文件图标 / 底部蓝色按钮拖动** | 将文件（或所选文件）从架子拖出到目标文件夹或应用 |
| **按住顶部标题栏 / 空白背景拖动** | 自由移动架子窗口位置（双击标题栏可快速收起/展开） |
| **`Space`（空格键）** | 呼出 macOS 原生 QuickLook 预览架子内的文件 |
| **`⌘ + C` / `⌘ + V`** | 复制架子内文件到系统剪贴板 / 将剪贴板内容粘贴进架子 |
| **`Delete` / `Backspace`** | 从架子中移除当前选中的文件（不会删除本地源文件） |
| **`Esc` / `⌘ + W`** | 取消选中 / 关闭当前文件架 |

---

## 📁 项目结构

```text
DropShelf/
├── Package.swift                 # Swift Package 清单
├── Resources/
│   └── Info.plist                # 应用 Bundle 配置 (LSUIElement 菜单栏应用)
├── Sources/DropShelf/
│   ├── App/
│   │   ├── main.swift            # 应用入口
│   │   └── AppDelegate.swift     # 菜单栏图标、拖拽接收与全局初始化
│   ├── Core/
│   │   ├── ShakeDetector.swift   # 鼠标晃动方向反转算法与 Option 拖拽监听
│   │   ├── HotKeyManager.swift   # Carbon 全局快捷键注册管理
│   │   ├── ShelfManager.swift    # 多文件架生命周期与空间调度
│   │   └── ShelfViewModel.swift  # 单个文件架状态、ZIP 打包与剪贴板动作
│   ├── Models/
│   │   ├── AppSettings.swift     # 偏好设置持久化模型
│   │   └── ShelfItem.swift       # 暂存项模型、QuickLook 缩略图与剪贴板提取器
│   └── UI/
│       ├── ShelfPanel.swift      # 置顶无边框 NSPanel 与 QLPreviewPanel 集成
│       ├── ShelfContentView.swift# SwiftUI 毛玻璃架子主界面（堆叠/网格/胶囊视图）
│       ├── DragOutContainerView.swift # AppKit 多文件原生拖出/拖入与窗口移动视图
│       └── SettingsView.swift    # 偏好设置面板
├── Tests/DropShelfTests/
│   └── ShakeEvaluatorTests.swift # 晃动检测算法单元测试
└── scripts/
    └── build_app.sh              # 一键编译、生成 .icns 图标与打包签名脚本
```

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源，你可以完全自由地使用、修改和分发。
