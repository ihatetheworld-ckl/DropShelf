# DropShelf — macOS 原生悬浮文件暂存架

**DropShelf** 是一款使用 `Swift + AppKit + SwiftUI` 从零构建的原生 macOS 悬浮文件架工具，参考 Dropover 的文件暂存交互。

无需忍受未买断时的 3 秒倒计时弹窗，无需繁琐配置，**拖拽时晃动鼠标唤起**，支持全屏应用悬浮跟随、多架子并行管理、空格键 QuickLook 预览与一键打包 ZIP。

---

## ✨ 核心特性

- ⚡ **原生交互**：使用 AppKit 接收拖放，文件操作及图片编码在后台执行。响应时间取决于文件、设备和来源应用，尚无延迟基准测量。
- 🖱️ **多种丝滑唤起方式**：
  - **拖拽晃动唤起（Shake to Summon）**：按住文件/图片/文字来回晃动鼠标，架子立即在光标旁弹出（支持低/中/高三档灵敏度调节）。
  - **按住 `Option (⌥)` 拖拽唤起**：拖拽时按住 `⌥` 键，无需晃动直接弹出文件架。
  - **状态栏图标拖拽**：直接将文件拖到屏幕顶部菜单栏的 `DropShelf` 图标上即可新建架子。
  - **全局快捷键**：随时使用 `⇧ + ⌘ + D` 在鼠标位置新建空白架子，或用 `⌥ + ⇧ + Space` 一键折叠/展开所有架子。
- 🗂️ **常见内容类型支持**：
  - **本地文件与文件夹**：保存路径引用（`URL`），导入时不复制文件本体；图标、缩略图及元数据仍会消耗资源。
  - **网页图片 / 截图 / 文本片段 / 网址链接**：在应用专属缓存目录生成 `.png`、`.txt` 或 `.webloc` 文件，作为标准文件提供给支持文件拖放的应用；临时文件保留规则见下文。
- 🪟 **精致毛玻璃悬浮窗与多架子管理**：
  - 基于原生 `NSPanel`（`.nonactivatingPanel` + `.canJoinAllSpaces`），置顶悬浮且不抢占当前活动窗口焦点，支持跨桌面空间与全屏应用跟随。
  - 支持 **堆叠卡片视图（Stack View）** 与 **多选网格视图（Grid View）** 自由切换。
  - 支持将架子收起为极简的**迷你胶囊（Compact Pill）**，或点击图钉（Pin）固定在桌面上长期使用。
- 🛠️ **高频效率动作**：
  - **空格键快速预览（QuickLook）**：选中架子按 `Space` 直接呼出 macOS 原生快速预览面板。
  - **一键打包 ZIP**：点击底部拉链图标，调用系统 `ditto` 打包选中项目（未选择时为全部），仅替换本次打包的项目，保留未选中及打包期间新增的项目。
  - **右键菜单与快捷键**：支持 `⌘C` 复制文件、`⌘V` 从剪贴板粘贴、复制文件路径、在 Finder 中显示、批量移动到指定文件夹。

---

## 🚀 快速安装与构建

### 环境要求
- macOS 13.0 (Ventura) 或更高版本
- Xcode Command Line Tools (`xcode-select --install`)

### 方式一：直接下载安装包（推荐）

已发布版本可前往 [**GitHub Releases**](https://github.com/ihatetheworld-ckl/DropShelf/releases) 页面下载最新版本的安装包（Universal 通用架构，同时原生支持 Apple Silicon M 系列与 Intel 芯片）：
- **`DropShelf-v1.0.0-macOS-Universal.dmg`**：双击挂载后，将 `DropShelf.app` 拖入 `Applications` 文件夹即可。
- **`DropShelf-v1.0.0-macOS-Universal.zip`**：解压后直接将 `DropShelf.app` 移入 `/Applications` 目录。

> 💡 **首次打开提示**：由于应用采用开源本地签名（未购买 Apple 付费开发者证书公证），如果首次打开提示“无法验证开发者”，请在终端运行以下命令移除隔离属性即可正常打开：
> ```bash
> xattr -cr /Applications/DropShelf.app
> ```

### 方式二：从源码构建并本地试用

本地修复不会自动更新 GitHub 已发布的安装包。

```bash
# 1. 克隆仓库
git clone https://github.com/ihatetheworld-ckl/DropShelf.git
cd DropShelf

# 2. 运行一键构建脚本（自动编译 Universal 通用二进制、生成高清矢量图标并完成本地签名）
./scripts/build_app.sh

# 3. 直接试用本地构建（不替换 /Applications 中的版本）
open build/DropShelf.app

# 回归测试
swift test

# 可选：创建临时 APFS 镜像，包含真实跨卷测试；结束后自动卸载和清理
./scripts/test_cross_volume.sh
```

---

## ⌨️ 交互手势与快捷键一览

| 操作 / 快捷键 | 功能说明 |
| :--- | :--- |
| **拖拽文件 + 晃动鼠标** | 在当前光标旁立即唤起新的悬浮文件架 |
| **拖拽文件 + 按住 `⌥ Option`** | 无需晃动，在当前光标位置唤起文件架 |
| **`⇧ + ⌘ + D`** | 全局快捷键：在鼠标位置新建空白文件架 |
| **`⌥ + ⇧ + Space`** | 全局快捷键：一键将所有打开的文件架收起为迷你胶囊 / 重新展开 |
| **按住文件图标 / 底部蓝色按钮拖动** | 将文件（或所选文件）从架子拖出到目标文件夹或应用 |
| **按住顶部标题栏 / 空白背景拖动** | 自由移动架子窗口位置（双击标题栏可快速收起/展开） |
| **`Space`（空格键）** | 呼出 macOS 原生 QuickLook 预览架子内的文件 |
| **`⌘ + C` / `⌘ + V`** | 复制架子内文件到系统剪贴板 / 将剪贴板内容粘贴进架子 |
| **`Delete` / `Backspace`** | 从架子中移除当前选中的文件（不会删除本地源文件） |
| **`Esc` / `⌘ + W`** | 取消选中 / 关闭当前文件架 |

---

如果工程位于 File Provider 管理的目录，系统可能给 `.app` 附加 FinderInfo 而使签名校验失败。可以将构建目录放到普通本地目录：

```bash
DROPSHELF_BUILD_DIR="$HOME/Library/Developer/DropShelf/LocalBuild" ./scripts/build_app.sh
```

## 文件安全与缓存

- 移动前选择冲突策略，默认**保留目标并跳过同名项**；可选择自动重命名同时保留。不提供静默覆盖。同路径、符号链接别名及同一 inode 安全跳过。
- 同磁盘使用禁止覆盖的原子重命名。跨磁盘及应用生成的临时文件采用安全复制并保留源文件，完成提示会区分移动、复制、跳过和失败；跨磁盘源文件需在确认目标后自行处理。
- ZIP 的工作目录、输出目录按任务隔离。同名项目自动重命名后全部打包；复制或系统打包失败时保留原项目。任务期间可继续拖入，移除、清空及关闭在当前文件任务完成前禁用；进行中的任务会阻止退出应用，完成后可再次退出。
- 默认拖出为复制或链接，避免普通拖放改变原始文件位置；显式移动使用架子菜单。取消拖拽不移除项目；成功后是否从架子移除受偏好设置控制。
- 临时文件存储位于 `~/Library/Application Support/com.local.dropshelf/TemporaryFiles-v1/`。使用 Application Support 避免系统自动清除缓存而使外部引用失效。未导出的资源在最后一个架子或任务释放引用后删除；每个实例持有会话锁，启动时清理已退出实例留下的未导出资源和工作目录。
- **已经拖出、复制路径/文件、打开或预览的临时文件持续保留，包括应用重启后。** 外部应用无法可靠通知 DropShelf 何时用完文件，因此没有固定 30 秒删除或按文件年龄删除。可在偏好设置中打开缓存位置，确认所有引用不再需要后手动清理；导出较多时缓存会增长。
- 清理仅针对本版本创建并带所有权标记的目录，不删除用户原始文件，也不接管旧版 `/tmp/DropShelfItems`、`DropShelfArchives` 缓存。架子列表目前不跨重启恢复。原始文件在架子外被移动、改名或删除后，路径引用不会自动跟踪更新。
- 固定架子清空后保留；未固定架子在清空后按设置关闭。空白架子的等待计时只折叠窗口，不关闭窗口。

## 本地验证与手动验收

已增加文件安全、ZIP 解包内容、并发任务、缓存所有权、异步状态合并和批量折叠等回归测试。运行 `swift test`，再用 `./scripts/build_app.sh` 生成通用架构 `.app`。编译的最低部署目标为 macOS 13.0；交叉编译成功不代表已经在 Intel 或 macOS 13 真机运行。

以下端到端交互仍需按目标设备实际验收，均使用可丢弃的专用测试目录：

1. Finder 中拖入文件和文件夹；浏览器分别拖入图片、选中文字、链接，核对文件内容。
2. 外部拖拽时晃动或按 Option；拖到菜单栏图标；按 `⇧⌘D` 新建、`⌥⇧Space` 批量折叠/展开，分别检查全展开、全折叠和混合状态。
3. 单文件/多选拖到测试目录，核对文件数及内容；用 Escape 取消拖拽，确认项目保留。拖到另一架子，再关闭源架子，确认目标文件仍能读取。
4. 复制临时内容后关闭全部架子，超过 30 秒后在 Finder 粘贴，并在应用重启后再次确认；Quick Look 打开时清空/关闭源架子不得崩溃。
5. 固定/取消固定、清空、自动关闭、空白架子超时折叠；打包期间继续加入文件，核对未选中和新增项目保留。仅使用测试文件验证同路径、同名和失败结果。
6. 多屏边缘唤起、移动及折叠展开；切换桌面和全屏应用，核对可见性、焦点和窗口位置。

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
│   │   ├── FileOperationService.swift # 禁止覆盖的移动与隔离 ZIP 任务
│   │   ├── TemporaryFileStore.swift # 临时文件共享所有权、导出保留及恢复清理
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
│   ├── ShakeEvaluatorTests.swift # 晃动检测算法
│   ├── FileSafetyTests.swift     # 移动、冲突和 ZIP 内容
│   ├── TemporaryFileStoreTests.swift # 缓存生命周期及剪贴板
│   └── ShelfStateTests.swift     # 异步任务与窗口状态
└── scripts/
    └── build_app.sh              # 一键编译、生成 .icns 图标与打包签名脚本
```

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源，你可以完全自由地使用、修改和分发。
