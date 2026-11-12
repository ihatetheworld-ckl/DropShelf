# DropShelf

用 Swift、AppKit 和 SwiftUI 构建的 macOS 悬浮文件暂存架，参考 Dropover 的暂存交互。把文件、图片或文字放到架子里，再带到另一个窗口。

[下载 v1.0.4](https://github.com/ihatetheworld-ckl/DropShelf/releases/tag/v1.0.4) · [更新记录](CHANGELOG.md) · [测试与验收](docs/TESTING.md) · [MIT License](LICENSE)

## 下载与安装

应用最低部署目标为 **macOS 13.0**。安装包包含 **Apple Silicon（arm64）和 Intel（x86_64）** 两种架构。普通使用无需安装 Xcode。

| 附件 | 用途 |
| --- | --- |
| [DropShelf-v1.0.4-macOS-Universal.dmg](https://github.com/ihatetheworld-ckl/DropShelf/releases/download/v1.0.4/DropShelf-v1.0.4-macOS-Universal.dmg) | 挂载后把应用拖到 Applications |
| [DropShelf-v1.0.4-macOS-Universal.zip](https://github.com/ihatetheworld-ckl/DropShelf/releases/download/v1.0.4/DropShelf-v1.0.4-macOS-Universal.zip) | 解压后直接试用或手动安装 |
| [SHA256SUMS.txt](https://github.com/ihatetheworld-ckl/DropShelf/releases/download/v1.0.4/SHA256SUMS.txt) | 核对安装包与构建记录的 SHA-256 |
| [release-manifest.json](https://github.com/ihatetheworld-ckl/DropShelf/releases/download/v1.0.4/release-manifest.json) | 记录源码提交、版本、架构和文件摘要 |

1. 下载 DMG 或 ZIP。升级前先处理旧架子中的内容并退出旧版本，避免两个实例抢占快捷键。
2. 打开 `DropShelf.app`。应用运行后显示在菜单栏，默认不显示 Dock 图标。
3. 点击菜单栏图标，选择“新建空白文件架”，即可开始使用。

发行包采用 **ad-hoc 本地签名，未经过 Apple 公证**。macOS 可能阻止首次打开；请核对来源和校验和后，按照系统安全提示允许打开。项目不提供 Apple Developer ID 签名保证。

核对某个下载文件：

```bash
shasum -a 256 DropShelf-v1.0.4-macOS-Universal.dmg
```

将输出与 `SHA256SUMS.txt` 中同名文件的记录比较。下载全部附件后，也可在附件所在目录运行 `shasum -a 256 -c SHA256SUMS.txt`。

## 使用方式

文件架提供以下入口。拖放能否被接收，仍取决于来源和目标应用提供的数据类型；实际交互的验证范围见[测试与验收](docs/TESTING.md)。

晃动和 Option 唤起需要先实际拖起文件等内容。程序会核对本次手势的新拖拽数据，防止上次拖拽残留的数据让空白三指移动、窗口移动或选择操作误唤起；同一次拖拽最多唤起一次。

| 操作 | 行为 |
| --- | --- |
| 拖拽内容时来回晃动鼠标 | 在光标附近唤起架子，灵敏度可调整 |
| 拖拽时按住 `⌥ Option` | 唤起架子 |
| 拖到菜单栏图标 | 创建装有该内容的架子 |
| `⇧⌘D` | 在光标附近新建或复用空白架子 |
| `⌥⇧Space` | 有展开架子时全部折叠；全部折叠时全部展开 |
| 拖动文件图标或底部蓝色按钮 | 拖出所选项目；未选择时拖出全部 |
| `⌘` 点击网格项目 | 增减选择；普通点击切换单项选择 |
| `Space` | Quick Look 预览 |
| `⌘C` / `⌘V` / `⌘A` | 复制文件 / 从剪贴板导入 / 全选 |
| `Delete` | 从架子移除所选项目 |
| `Esc` | 取消选择；无选择且架子为空时关闭 |
| `⌘W` | 关闭当前架子 |

标题栏和空白处可移动窗口；双击标题栏可折叠或展开。图钉用于保留清空后的架子。堆叠视图、网格视图和折叠胶囊适用于不同数量的暂存项。

菜单还提供打包 ZIP、复制路径、在 Finder 显示、移动到指定文件夹等动作。偏好设置可调整拖出时始终复制、拖出后移除、清空后自动关闭、空白架子超时折叠、音效和登录时启动。

新建或复用架子时请求触觉提示，默认开启，可在偏好设置中独立关闭。需要支持 Force Touch 的触控板；实际反馈由系统根据当前输入设备、触觉设置及手指接触情况决定。使用 Apple 的公开 `NSHapticFeedbackManager` 接口，不要求额外辅助功能权限。

默认使用通用双次短提示（两次请求间隔约 240 毫秒），可在偏好设置切回单次，并点击“试震”比较。Apple 的公开触控板接口没有力度参数；双次用于改变提示节奏，不代表物理振幅增加，也不保证系统实际执行两次。切换开关或样式、再次触发或试震时，会取消之前未完成的第二次请求。未设置过样式时默认双次；升级会保留已有触觉开关和已选择的单次/双次样式。

## 文件会怎样处理

### 原始文件

拖入本地文件或文件夹时，架子保存路径引用，不复制文件本体。移除项目、清空或关闭架子不会删除这些原始文件。

v1.0.4 的拖出策略按 [Dropover 的复制/移动交互](https://dropoverapp.com/tips)调整，交由 Finder 执行文件操作：

| 拖到 Finder 文件夹 | 请求的行为 |
| --- | --- |
| 普通拖出原始文件或文件夹 | 同盘默认移动、跨盘默认复制 |
| 按住 `⌥ Option` | 强制复制 |
| 按住 `⌘ Command` | 强制移动，包括跨盘 |
| 开启“拖出时始终复制，保留原始文件” | 只允许复制，忽略复制/移动修饰键 |
| 应用生成的图片、文本、链接、ZIP，或含它们的混合批次 | 始终复制，保护其他架子和剪贴板仍持有的临时文件 |

拖出不提供替身/链接操作；未开启始终复制时，`⌥⌘` 创建替身的组合不受支持。其他接收应用如何导入文件由该应用决定。取消拖拽保留项目；复制被接收后按“拖出后移除”设置更新架子。本应用不会在拖拽结束时自行删除源文件。目标报告移动时，只移除已不在原路径的引用，仍在原位置的项目保留以便重试；即使关闭自动移除，已失效的源路径也会从架子移除。

Finder 负责原生拖放的进度、同名冲突和取消。AppKit 的结束回调不提供逐项完成结果，目标也可能异步处理：仍在原处的移动项会保守保留；复制的后续失败可能需要从原路径重新导入。需要本应用逐项结果报告时，使用下述菜单操作。Finder 端到端验收范围见[测试文档](docs/TESTING.md)。

“移动到指定文件夹”默认保留已有目标并跳过同名项目，也可选择重命名后同时保留。同路径、符号链接别名及同一 inode 会安全跳过。同磁盘使用禁止覆盖的原子重命名；**跨磁盘和应用生成的临时文件采用复制，并保留源文件**。结果会区分移动、复制、跳过与失败。

### ZIP

选中项目时只打包所选项，否则打包全部。不同目录的同名项目会重命名后一起打包。每次任务使用独立工作目录和输出路径，完成时保留未选中及期间新增的项目；复制或打包失败时保留原项目。

文件操作与图片编码在后台执行。ZIP 或文件移动任务进行期间可继续导入，移除、清空和关闭暂时禁用；退出应用也会被阻止，待任务结束后可再次退出。

### 图片、文字、链接与缓存

图片、文字和网址会生成 `.png`、`.txt`、`.webloc` 文件，ZIP 也存放在应用专属目录：

```text
~/Library/Application Support/com.local.dropshelf/TemporaryFiles-v1/
```

- 未交给外部使用的临时文件，在最后一个架子或任务释放引用后清理。
- **准备拖出、复制文件或路径、打开、预览后的临时文件持续保留，包括重启以后。** 外部应用没有可靠的“使用完成”通知，因此不按固定等待时间删除。
- 启动时清理已退出实例留下的未导出资源和任务目录；会话锁保护仍在运行的实例。
- 可在偏好设置中打开存储位置。确认剪贴板、其他架子及外部应用不再需要后，再手动清理。长期使用会增加磁盘占用。
- 自动清理仅针对本版本拥有并标记的目录，不接管旧版临时目录。

## 当前限制与验证范围

- 架子列表不跨应用重启恢复；原始文件在外部改名、移动或删除后，引用不会自动跟踪。
- 长时间文件任务暂不支持取消。
- 窗口按跨桌面和全屏辅助窗口配置；多屏、全屏应用及特定浏览器的拖放兼容性仍需实机验收。
- v1.0.4 本地在 Apple Silicon、macOS 27.2 上通过了 71 项回归测试，覆盖拖出操作与取消回调、部分移动保留、拖拽会话与残留数据、触觉开关与延迟取消、真实跨卷复制、ZIP 解包内容、缓存生命周期及 AppKit 窗口/Quick Look。触觉请求测试使用注入回调；本机用户已试用确认通用双次 240 毫秒的手感和节奏合适，未测量硬件振幅。物理三指完整手势链路和其他设备仍需验收，详见[测试与验收](docs/TESTING.md)。
- Intel 与 macOS 13 的部署目标经过构建检查；未进行这两种环境的真机验收。CI 结果也不能替代 Finder、浏览器和外部应用的完整手势测试。

项目没有“0 毫秒”或“零延迟”的测量结论。响应速度取决于文件、设备与应用的数据提供方式。

## 从源码构建

需要 macOS、Xcode 或包含 Swift 5.9 及以上版本和 macOS SDK 的 Command Line Tools。发行校验还需要 Python 3.9 及以上版本，使用标准库，无额外 Python 依赖。

```bash
git clone https://github.com/ihatetheworld-ckl/DropShelf.git
cd DropShelf
swift test
./scripts/build_app.sh
open build/DropShelf.app
```

构建脚本生成 arm64、x86_64 二进制，合并为 Universal 2，生成图标并进行本地签名。不会安装到 `/Applications`；同目录的旧构建会保留为带时间戳的备份。

若工程处于 File Provider 管理的目录，系统可能附加影响签名的 FinderInfo 元数据。可把构建输出放到普通本地目录：

```bash
DROPSHELF_BUILD_DIR="$HOME/Library/Developer/DropShelf/LocalBuild" ./scripts/build_app.sh
```

## 测试与打包

```bash
# 包含专用 APFS 磁盘镜像的真实跨卷测试，结束后自动卸载
./scripts/test_cross_volume.sh

# 先提交改动，再按 Info.plist 中的版本构建、打包并验证
./scripts/package_release.sh

# 独立复核已有安装包
python3 scripts/verify_release.py build/releases/v1.0.4 --version 1.0.4
```

打包脚本只在临时工作目录签名和制作镜像，校验通过后输出至 `build/releases/v版本号/`。版本必须与 `Info.plist` 一致，已有发行目录不会被覆盖。可用 `DROPSHELF_RELEASE_DIR` 指定输出父目录。

[GitHub Actions](https://github.com/ihatetheworld-ckl/DropShelf/actions/workflows/ci.yml) 对主分支及 PR 运行回归测试，构建 Universal ZIP/DMG，并检查解压/挂载后的版本、签名、架构、最低系统目标、内容一致性和 SHA-256。流程仅上传 CI 构建附件，不自动发布 Release。

## 源码导览

| 位置 | 职责 |
| --- | --- |
| `App/` | 应用入口、菜单栏、全局初始化 |
| `Core/ShelfManager.swift` | 多架子窗口管理 |
| `Core/ShelfViewModel.swift` | 选择、任务状态、剪贴板与用户动作 |
| `Core/FileOperationService.swift` | 禁止覆盖的移动、安全复制和 ZIP |
| `Core/TemporaryFileStore.swift` | 临时文件所有权、外部保留和孤立资源清理 |
| `Core/ShakeDetector.swift`、`HotKeyManager.swift` | 手势检测与快捷键 |
| `Models/`、`UI/` | 暂存项、偏好设置、AppKit/SwiftUI 界面 |
| `Tests/DropShelfTests/` | 回归测试 |

应用源码均位于 `Sources/DropShelf/`。问题反馈请附系统版本、芯片架构、来源/目标应用及使用测试文件的复现步骤。

## 许可证

[MIT](LICENSE)。
