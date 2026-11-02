# iOS / iPadOS 16.0 兼容改造核查与验证证据记录

本文档沉淀 `openspec/changes/support-ios16/tasks.md` 执行过程中的环境核查、兼容盘点、诊断编译输出、原生框架二进制检查、缓存失效验证及侧载打包规范，作为勾选各阶段任务项的事实依据。

---

## 1. 基准与验证环境核查（对应 Tasks 1.1 ~ 1.6）

### 1.1 工作区、Git 远端与基准提交（Task 1.1）
- **工作区路径**：`/Users/konvy-1054/www/ai/tvbox-silicon`
- **当前分支**：`codex/support-ios16`
- **Git 远端**：
  - `origin`：`https://github.com/zhiqiangwong/tvbox-silicon.git`（用户 fork）
  - `upstream`：`https://github.com/jo32/tvbox-silicon.git`（上游仓库）
- **基准提交**：`6ce6f6e`（`AltStore source: 1.8.3`），已执行 `git fetch upstream && git fetch origin`，确认 `git merge-base --is-ancestor upstream/main HEAD` 与 `origin/main` 均通过（返回 0）。
- **OpenSpec 规划位置**：使用仓库内 `openspec/changes/support-ios16/{proposal.md,design.md,tasks.md,specs/ios16-compatibility/spec.md}`，未使用主目录备份。

### 1.2 工具链、SDK 与运行时环境核查（Task 1.2）
- **宿主系统**：macOS 15.7.7 (`24G720`, Apple Silicon `arm64`)
- **Xcode 与许可**：Xcode 26.3 (`Build version 17C529`)，`xcodebuild -license check` 返回 `0`（许可已接受）。
- **Swift 工具链**：Apple Swift version 6.2.4 (`swiftlang-6.2.4.1.4 clang-1700.6.4.2`)，目标 `arm64-apple-macosx15.0`。
- **已安装 SDK（`xcodebuild -showsdks`）**：
  - `iPhoneOS26.2.sdk` (`iphoneos26.2`)
  - `iPhoneSimulator26.2.sdk` (`iphonesimulator26.2`)
  - `AppleTVOS26.2.sdk` (`appletvos26.2`)
  - `AppleTVSimulator26.2.sdk` (`appletvsimulator26.2`)
  - `MacOSX26.2.sdk` (`macosx26.2`)
- **构建辅助工具**：
  - Homebrew (`/opt/homebrew/bin/brew`)：`autoconf 2.72`、`cmake`、`maven`、`python@3.14`
  - 系统/SDKMAN JDK：Zulu OpenJDK `17.0.11` (`/Users/konvy-1054/.sdkman/candidates/java/current`)
- **当前环境阻碍（Task 1.2 保持 `[ ]` 的原因）**：
  1. `xcrun simctl list runtimes` 输出为空，本机尚未安装任何 iOS Simulator Runtime（包括 iOS 16.x 模拟器与 iOS 26.2 模拟器）。
  2. 因 Xcode 26.3 未安装 iOS 26.2 平台模拟器组件，`xcodebuild -scheme TVBox-iOS -destination generic/platform=iOS` 在解析 Scheme RunDestination 时会报 `iOS 26.2 is not installed`；直接指定 `-target <Target> -sdk iphoneos` 则可正常调用 `iPhoneOS26.2.sdk` 编译与归档。

---

### 1.3 最低版本声明、观察模型、系统接口与原生依赖兼容清单（Task 1.3）

#### A. 最低系统版本声明位置
| 文件路径 | 行号 | 当前配置 | 目标配置 |
| :--- | :--- | :--- | :--- |
| `project.yml` | L8 | `deploymentTarget.iOS: "17.0"` | `"16.0"`（`macOS: "15.0"`, `tvOS: "17.0"` 保持不变） |
| `Package.swift` | L7 | `.iOS(.v17)` | `.iOS(.v16)`（`.macOS(.v14)`, `.tvOS(.v17)` 保持不变） |
| `Scripts/apple-deployment-targets.sh` | L1-9 | 新增集中配置 | `IOS_DEPLOYMENT_TARGET=16.0`, `TVOS_DEPLOYMENT_TARGET=17.0`, `MACOS_DEPLOYMENT_TARGET=14.0` |
| `Scripts/build-apple-jvm.sh` | L13-16 | `-miphoneos-version-min=17.0` / `-mios-simulator-version-min=17.0` | 读取 `$IOS_DEPLOYMENT_TARGET` (`16.0`)，tvOS 保持 `17.0` |
| `Scripts/build-apple-libffi.sh` | L8-11 | `arm64-apple-ios17.0` / `arm64-apple-ios17.0-simulator` | 读取 `$IOS_DEPLOYMENT_TARGET` (`16.0`)，tvOS 保持 `17.0` |
| `Scripts/build-apple-interpreter.sh` | L32-38 | `-target arm64-apple-ios17.0` / `CMAKE_OSX_DEPLOYMENT_TARGET=17.0` | iOS 读取 `16.0`，tvOS 保持 `17.0`，且保留 `-DUNICORN_INTERPRETER=ON` |
| `Scripts/build-apple-native-bindings.sh` | L8-11, L33 | `arm64-apple-ios17.0` / `CMAKE_OSX_DEPLOYMENT_TARGET=17.0` | iOS 读取 `16.0`，tvOS 保持 `17.0` |
| `Scripts/build-apple-python.sh` | L23, L130 | `MINIMUM_OS=17.0` | iOS 读取 `16.0`，tvOS 保持 `17.0` |
| `Scripts/build-apple-python-wheels.sh` | L32 | `IPHONEOS_DEPLOYMENT_TARGET=17.0` | 读取 `IOS_DEPLOYMENT_TARGET` (`16.0`)，tvOS 保持 `17.0` |
| `Scripts/build-apple-ffmpeg.sh` | L84-85 | `arm64-apple-ios17.0` / `arm64-apple-ios17.0-simulator` | `arm64-apple-ios16.0` / `arm64-apple-ios16.0-simulator` |
| `Scripts/test-apple-jvm.sh` | L7, L54 | `arm64-apple-ios17.0-simulator`, `MinimumOSVersion='17.0'` | 读取 `IOS_DEPLOYMENT_TARGET` (`16.0`) |
| `Scripts/test-apple-embedded-host.sh` | L6, L42 | `arm64-apple-ios17.0-simulator`, `MinimumOSVersion='17.0'` | 读取 `IOS_DEPLOYMENT_TARGET` (`16.0`) |
| `Scripts/build-apple-source-sweep.sh` | L14, L72 | `arm64-apple-ios17.0-simulator`, `MinimumOSVersion='17.0'` | 读取 `IOS_DEPLOYMENT_TARGET` (`16.0`) |
| `Scripts/benchmark-prebuilt-ios.py` | L104, L107 | `MinimumOSVersion='17.0'`, `arm64-apple-ios17.0-simulator` | 读取 `IOS_DEPLOYMENT_TARGET` (`16.0`) |

#### B. 观察模型（Observation）全量清单（共 33 个 `@Observable` 类型）
- **`Sources/TVCore/`（16 个文件 / 20 个类）**：
  1. `Sources/TVCore/PlaybackSession.swift:6` (`PlaybackSession`)
  2. `Sources/TVCore/LivePlaybackSession.swift:27` (`LivePlaybackSession`)
  3. `Sources/TVCore/DownloadManager.swift:92` (`DownloadManager`)
  4. `Sources/TVCore/CloudDriveStore.swift:5` (`CloudDriveStore`)
  5. `Sources/TVCore/CloudPlaybackCoordinator.swift:6` (`CloudPlaybackCoordinator`)
  6. `Sources/TVCore/BilibiliCast.swift:72` (`BilibiliCastController`)
  7. `Sources/TVCore/LiveRoomsStore.swift:5` (`LiveRoomsStore`)
  8. `Sources/TVCore/LiveRoomsSupport.swift:5` (`LiveRoomDanmakuConnection`), `L51` (`LiveRoomPlaybackController`)
  9. `Sources/TVCore/MusicLibraryStore.swift:93` (`MusicLibraryStore`)
  10. `Sources/TVCore/MusicLyricsService.swift:128` (`MusicLyricsService`)
  11. `Sources/TVCore/MusicSearchStore.swift:5` (`MusicSearchStore`)
  12. `Sources/TVCore/TMDBMetadata.swift:536` (`TMDBService`)
  13. `Sources/TVCore/TraktSync.swift:127` (`TraktSync`), `L1002` (`TraktSyncCoordinator`)
  14. `Sources/TVCore/VideoCacheServer.swift:4` (`VideoCacheServer`)
  15. `Sources/TVCore/VideoPrefetcher.swift:5` (`VideoPrefetcher`)
  16. `Sources/TVCore/WatchTogether.swift:241` (`WatchTogetherSession`)
- **`App/`（11 个文件 / 13 个类）**：
  1. `App/Store.swift:4` (`Store`)
  2. `App/Announcements.swift:6` (`Announcements`)
  3. `App/CatalogDanmakuView.swift:6` (`CatalogDanmakuController`)
  4. `App/LiveRoomsView.swift:324` (`LiveRoomsViewModel`)
  5. `App/MobilePlayer.swift:1103` (`MobileBrightnessModel`), `L1141` (`MobileVolumeModel`), `L1252` (`MobilePlayerControlsModel`)
  6. `App/MusicPlaybackSession.swift:14` (`MusicPlaybackSession`)
  7. `App/PlaybackView.swift:5` (`PlaybackOverlayState`)
  8. `App/SettingsView.swift:1876` (`SettingsDiagnosticsModel`)
  9. `App/TMDBViews.swift:7` (`TMDBPersonSheetModel`)
  10. `App/Updates.swift:7` (`AppUpdater`)
  11. `App/VideoEnhancement.swift:75` (`VideoEnhancementController`)
- **关联配套用法**：
  - `@ObservationIgnored`：`Sources/TVCore/` 12 处，`App/` 31 处
  - `@Bindable`：`App/` 8 处（`CatalogDanmakuView.swift:174`、`DiscoveryView.swift:60,199`、`MusicPlayerViews.swift:457`、`RootView.swift:90,208`、`SettingsView.swift:359,879`）
  - `@Environment(ObservableType.self)`：`App/` 70 处
  - `.environment(observableObject)`：`App/TVBoxApp.swift:31`（3 处）、`App/Updates.swift:647`（1 处）
  - `withObservationTracking`：`App/MusicRemoteControl.swift:49`（1 处）

#### C. SwiftUI / 系统 API（iOS 17+ / iOS 16.4+）全量清单
1. **`onChange(of:initial:_:)` 与新式双参/无参 `onChange`（36 处）**：
   - `CatalogDanmakuView.swift:245`、`DanmakuView.swift:337,338`、`DiscoveryView.swift:93,163`、`DownloadsView.swift:34`、`GlassKit.swift:1048`、`MobilePlayer.swift:131,132,133,135,136`、`MusicNowPlayingPanels.swift:52`、`MusicNowPlayingScreen.swift:60`、`MusicPlayerViews.swift:361`、`MusicView.swift:46,60`、`PlaybackHistoryView.swift:30`、`PlayerView.swift:105,120,122,125,126,136`、`RootView.swift:128,139,186,193,198`、`SettingsView.swift:858`、`SitesView.swift:907,1605,1615,1769`、`TVBoxApp.swift:69,70`。
2. **`ContentUnavailableView`（21 处，含 2 处 `.search(text:)`）**：
   - `Announcements.swift:151`、`DanmakuView.swift:314` (`.search(text:)`)、`DiscoveryView.swift:141,170,179`、`HomeView.swift:230`、`LiveRoomsView.swift:63,133,137` (`.search(text:)`)、`LiveView.swift:162`、`MusicDownloadsView.swift:62,221`、`MusicNowPlayingPanels.swift:59,74`、`MusicPlayerViews.swift:292`、`MusicView.swift:182`、`SettingsView.swift:1281`、`SitesView.swift:641,689`。
3. **滚动定位、裁剪与布局修饰符（iOS 17+）**：
   - `.scrollTargetLayout(isEnabled:)`：`DiscoveryView.swift:155,909`、`MusicNowPlayingPanels.swift:41`、`MusicPlayerViews.swift:354`、`SitesView.swift:1762`
   - `.scrollPosition(id:anchor:)`：`DiscoveryView.swift:80`、`MusicNowPlayingPanels.swift:44`、`MusicPlayerViews.swift:357`、`SitesView.swift:1766`
   - `.scrollClipDisabled()`：`MusicDownloadsView.swift:121`、`TMDBViews.swift:247,357`
   - `GeometryProxy.bounds(of: .scrollView...)`：`DiscoveryView.swift:1033`、`GlassKit.swift:110`
   - `.contentMargins(_:_:for:)`：`SettingsView.swift:296`
   - `.containerRelativeFrame(_:alignment:_:)`：`HomeView.swift:141`
4. **导航与弹窗修饰符（iOS 16.4+ / iOS 17.0+）**：
   - `.navigationDestination(item:destination:)`（iOS 17.0+）：`DiscoveryView.swift:801`、`PlaybackHistoryView.swift:312`
   - `.presentationBackground(...)` / `.presentationCornerRadius(...)`（iOS 16.4+，在 iOS 16.0~16.3 需 `#available(iOS 16.4, *)` 保护）：`DanmakuView.swift:475,476`、`MusicNowPlayingScreen.swift:55`
5. **符号效果、过渡、颜色解析、触感与录屏状态（iOS 17+）**：
   - `.symbolEffect(...)` / `.contentTransition(.symbolEffect(...))`：`FavoriteControls.swift:19`、`GlassKit.swift:129`、`LiveView.swift:714`、`MobilePlayer.swift:295,589`、`MusicMiniPlayer.swift:47`、`MusicNowPlayingScreen.swift:140`、`MusicPlayerViews.swift:49`、`PlaybackHistoryView.swift:260`
   - `.contentTransition(.numericText(value:))`：`MobilePlayer.swift:298`
   - `.transition(.blurReplace)`：`PlaybackWaitView.swift:207`
   - `.sensoryFeedback(...)`：`MobilePlayer.swift:137,798`
   - `Color.resolve(in:)` 及 `.red`/`.green`/`.blue`：`GlassKit.swift:139,143`
   - `UIScreen.sceneCaptureState`：`PlaybackView.swift:920`（iOS 16 可用 `screen.isCaptured`）

#### D. 原生依赖与构建缓存目录清单
| 运行环境 / 依赖 | 构建/获取脚本 | 缓存与产物目录 | 缓存识别机制 |
| :--- | :--- | :--- | :--- |
| OpenJDK Zero JVM | `Scripts/build-apple-jvm.sh` | `build/apple-runtime/openjdk-mobile/build/<conf>` | `.deployment-target` 记录 `-m*-version-min=` |
| `libffi` 3.4.8 | `Scripts/build-apple-libffi.sh` | `build/apple-runtime/libffi-<target>-3.4.8` | `.deployment-target` 记录 `$TRIPLE` |
| Unicorn TCI | `Scripts/build-apple-interpreter.sh` | `build/apple-runtime/unicorn-tci-<target>` | `.deployment-target` 记录 `$TARGET:$DEPLOYMENT_TARGET` |
| Capstone / Keystone / JNA | `Scripts/build-apple-native-bindings.sh` | `build/apple-runtime/{capstone,keystone,native}-<target>` | 各目录 `.deployment-target` 记录 `$TRIPLE` |
| 打包后 AppleRuntime | `Scripts/package-apple-runtime.sh` | `build/AppleRuntime/<platform>` | `.deployment-target` 记录 `$MINIMUM` |
| Python 3.14 & Wheels | `Scripts/build-apple-python.sh`, `Scripts/build-apple-python-wheels.sh` | `build/apple-python/{wheels,xml}-<platform>`, `build/ApplePython/<platform>` | 各目录 `.deployment-target` 记录 `$PLATFORM:$MINIMUM_OS` |
| Node.js (NodeMobile) | `Scripts/fetch-node-mobile.sh` | `build/NodeMobile/NodeMobile.xcframework` | 官方预编译包 SHA-256 固定校验 |
| FFmpeg 8.1.3 | `Scripts/build-apple-ffmpeg.sh` | `~/Library/Caches/tvbox-ffmpeg/<signature>/FFmpeg.xcframework` | Recipe + 平台最低版本展开后 SHA-256 签名 |
| QuickJS | SwiftPM `QuickJS` target | `Sources/QuickJS` | 由 SwiftPM / Xcode 按工程部署目标直接编译 |

#### E. 受控对照来源与测试媒体
- **Java / JAR 代表性受控样例**：`Runtime/AppleRuntime/Spike/RuntimeSpike.java`（含 JVM 启动、JNI 桥接、TLS HTTPS、Unicorn ARM64 解释器、DEX 转换自检）及 `Tests/TVCoreTests/` 中的 JAR Spider 测试夹具。
- **QuickJS 代表性受控样例**：`Tests/TVCoreTests/` 内置 QuickJS Spider 脚本与嗅探回归用例。
- **Python 代表性受控样例**：`Runtime/PythonHost/host.py` 及内置测试 Spider（覆盖 `lxml.etree`、`Crypto.Cipher.AES`、`requests`/`urllib3` HTTPS）。
- **Node.js 代表性受控样例**：`Sources/TVCore/NodeBridge.m` 内嵌 Node.js Spider 执行与 HTTP 请求自检脚本。
- **代表性测试媒体**：`Tests/TVCoreTests/RemuxTests.swift` 及 `TVMedia` 受控 MP4 / HLS / MKV（含 H.264/HEVC/AAC/AC3 封装转换）测试流。

---

### 1.5 全量 iOS 16.0 诊断编译记录（Task 1.5）
- **诊断方法与命令**：
  1. 将 `Package.swift` 中 `.iOS(.v17)` 临时改为 `.iOS(.v16)`，执行：
     ```bash
     swift build --triple arm64-apple-ios16.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
     ```
     **结果**：`DexRuntime`、`QuickJS`、`TVMedia`、`FFmpeg` 100% 编译通过；`TVCore` 仅上述 16 个使用 `@Observable` / `@ObservationIgnored` 的文件报错，无任何其他底层 iOS 17 API 依赖（完整输出见 `build/diagnostic-ios16/tvcore-ios16-errors.log`）。
  2. 为穿透 `TVCore` 检查 `App/` 层全部 62 个 Swift 文件，在临时生成 `TVCore.swiftmodule` 后执行两轮 `-continue-building-after-errors` 诊断：
     ```bash
     xcrun --sdk iphoneos swiftc -typecheck -target arm64-apple-ios16.0 -swift-version 6 \
       -continue-building-after-errors -I .build/arm64-apple-ios/debug/Modules \
       -F build/NodeMobile -F build/FFmpeg ... App/*.swift
     ```
     **结果**：共捕获去重后 **279 条**编译错误（完整逐行清单保存于 `build/diagnostic-ios16/app-unique-errors.txt`），分类完全收敛于 1.3 节所列的 Observation、SwiftUI 视图修饰符及 `VideoEnhancement.swift:955-956`（SDK 26.2 下 `#available(iOS 27, *)` 分支属性名问题）。
  3. **清理确认**：诊断完成后已还原 `Package.swift`、`Sources/TVCore` 与 `App/`，并清理临时 `.build/arm64-apple-ios`，确认临时诊断配置未混入正式配置。

---

### 1.6 本地无凭据 Release 归档、IPA 封装与侧载路径（Task 1.6）
- **不依赖上游凭据、不启用 `APPSTORE` 的本地 Release 归档命令**：
  ```bash
  xcodebuild archive \
    -project TVBox.xcodeproj \
    -target <TargetName> \
    -configuration Release \
    -sdk iphoneos \
    -archivePath build/Release-<TargetName>.xcarchive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM=""
  ```
  - **核对项**：
    - `Config/Distribution.xcconfig` 仅被 `Scripts/release-testflight.sh` 显式通过 `-xcconfig` 传入；直接对工程执行 `Release` 配置归档不会注入 `APPSTORE` 编译标记（`SWIFT_ACTIVE_COMPILATION_CONDITIONS` 与 `GCC_PREPROCESSOR_DEFINITIONS` 均不含 `APPSTORE`），完整保留内嵌 Java / Python / Node.js 运行时与自定义源能力。
    - `project.yml` 中 `TVBox-iOS` 的 `STRIP_STYLE: debugging`、`DEAD_CODE_STRIPPING: NO` 在 `Release` 归档下生效，确保 `libTVAppleRuntime.a` 的 `_JIMAGE_Open` 等 JNI 符号不被剥离。
    - 严禁使用 `Scripts/release-testflight.sh`（即使带 `--no-upload`）制作侧载包，因为该脚本会强制注入 `Config/Distribution.xcconfig`（启用 `APPSTORE`）并移除 Python/Node 扩展。
- **从归档产物封装 IPA 并进行本地 ad-hoc 签名（供 TrollStore 安装）**：
  ```bash
  APP_PATH="build/Release-<TargetName>.xcarchive/Products/Applications/<AppName>.app"
  # 1. 对内嵌 Frameworks 逐一 ad-hoc 签名（不带 entitlements）
  if [ -d "$APP_PATH/Frameworks" ]; then
    for fw in "$APP_PATH/Frameworks/"*.framework; do
      [ -d "$fw" ] && codesign --force --sign - --timestamp=none "$fw"
    done
  fi
  # 2. 对主应用包进行 ad-hoc 签名（TVBox-iOS 无额外受限 entitlements）
  codesign --force --sign - --timestamp=none --generate-entitlement-der "$APP_PATH"
  # 3. 封装为标准 Payload/*.app 结构的 IPA
  rm -rf build/ipa-staging && mkdir -p build/ipa-staging/Payload
  cp -R "$APP_PATH" build/ipa-staging/Payload/
  (cd build/ipa-staging && ditto -c -k --sequesterRsrc --keepParent Payload "../<OutputName>.ipa")
  shasum -a 256 "build/<OutputName>.ipa"
  ```
- **目标设备与安装条件确认**：
  - 用户旧系统真机：已安装 TrollStore 的 iPad（iPadOS 16.x），可直接安装上述 ad-hoc 签名（`codesign --sign -`）的 Release IPA，无需 Apple Developer 付费证书或上游团队凭据。
  - 新系统回归设备：iOS / iPadOS 17+ 设备，使用同一份 Release IPA 验收（如需通过 Cider / AltStore 重签安装，记录重签前后 SHA-256 并确认二进制与资源一致）。

---

## 2. 原生运行环境核查与构建缓存验证（对应 Tasks 2.1, 2.3, 2.4）

### 2.1 Python 与 Node.js 预编译框架二进制核查结果（Task 2.1）

#### A. `NodeMobile.xcframework`（`v18.20.4`，由 `Scripts/fetch-node-mobile.sh` 获取并校验 SHA-256）
1. **真机切片 `ios-arm64/NodeMobile.framework/NodeMobile`**：
   - `lipo -archs`：`arm64`
   - `vtool -show-build`：
     ```text
     platform IOS
     minos 13.0
     sdk 17.2
     ```
   - `otool -L`：
     - `@rpath/NodeMobile.framework/NodeMobile`
     - `/usr/lib/libc++.1.dylib`
     - `/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation`
     - `/usr/lib/libSystem.B.dylib`
   - `Info.plist` `MinimumOSVersion`：`13.0`
2. **模拟器切片 `ios-arm64_x86_64-simulator/NodeMobile.framework/NodeMobile`**：
   - `lipo -archs`：`x86_64 arm64`
   - `vtool -show-build`：`x86_64` 为 `IOSSIMULATOR minos 13.0`，`arm64` 为 `IOSSIMULATOR minos 14.0`。
- **核查结论**：真机与模拟器切片的 Mach-O `LC_BUILD_VERSION` (`minos` 13.0 / 14.0) 均远低于 iOS 16.0，且仅链接基础系统库，无任何 iOS 17+ 私有或新增符号依赖。**直接复用，无需从源码重编 Node.js**。

#### B. `Python.xcframework`（BeeWare `Python-3.14-iOS-support.b13`）
1. **真机切片 `ios-arm64`**：
   - `Python.framework/Python`：
     - `lipo -archs`：`arm64`
     - `vtool -show-build`：`platform IOS`, `minos 13.0`, `sdk 26.2`
     - `otool -L`：`@rpath/Python.framework/Python`、`CoreFoundation`、`libSystem.B.dylib`
   - `lib-arm64/python3.14/lib-dynload/*.so`（全部 68 个标准库二进制扩展模块，含 `_ssl`、`_hashlib`、`_sqlite3`、`_ctypes`、`zlib` 等）：
     - 批量执行 `vtool -show-build` 核查：68/68 个 `.so` 均为 `platform IOS`, `minos 13.0`, `sdk 26.2`。
     - 批量执行 `otool -L` 核查：仅链接 `@rpath/Python.framework/Python`、`libSystem.B.dylib`、`libsqlite3.dylib`、`libz.1.dylib`（OpenSSL/BZip2/XZ/FFI 均已静态链接进对应 `.so` 且编译目标为 iOS 13.0）。
2. **模拟器切片 `ios-arm64_x86_64-simulator`**：
   - `Python.framework/Python`（`arm64` 切片）及全部 68 个 `.so`（`arm64` 切片）：`vtool -show-build` 均为 `platform IOSSIMULATOR`, `minos 14.0`, `sdk 26.2`。
- **核查结论**：BeeWare Python 3.14-b13 解释器与标准库全部 68 个原生扩展二进制 `minos` 均为 13.0（真机）/ 14.0（模拟器），**直接复用**；仅第三方编译扩展 wheels（`lxml` 含静态 `libxml2`/`libxslt`，以及 `pycryptodome`）与打包脚本生成的各 `.framework/Info.plist` `MinimumOSVersion` 需通过 `IOS_DEPLOYMENT_TARGET=16.0` 重新构建与设置。

---

### 2.3 & 2.4 构建脚本最低版本集中管理与缓存失效验证（Tasks 2.3 & 2.4）
- **集中版本配置**：`Scripts/apple-deployment-targets.sh` 统一导出：
  - `IOS_DEPLOYMENT_TARGET=16.0`
  - `TVOS_DEPLOYMENT_TARGET=17.0`
  - `MACOS_DEPLOYMENT_TARGET=14.0`
- **缓存失效与平台隔离验证实测结果**：
  1. **`FFmpeg`（`Scripts/build-apple-ffmpeg.sh`）**：
     - 签名计算将 `# RECIPE` 块中的平台最低版本变量展开后计算 SHA-256：当 `IOS_DEPLOYMENT_TARGET=16.0` 时签名为 `d2fb692b6180e0ec`，当 `IOS_DEPLOYMENT_TARGET=17.0` 时签名为 `4fb81f67bbdb9873`。
     - 实测 `build/FFmpeg/FFmpeg.xcframework` 全切片 `otool -l` (`LC_BUILD_VERSION`)：
       - `ios-arm64`：`platform 2 (IOS)`, `minos 16.0`, `sdk 26.2`
       - `ios-arm64-simulator`：`platform 7 (IOSSIMULATOR)`, `minos 16.0`, `sdk 26.2`
       - `tvos-arm64`：`platform 3 (TVOS)`, `minos 17.0`, `sdk 26.2`
       - `tvos-arm64-simulator`：`platform 8 (TVOSSIMULATOR)`, `minos 17.0`, `sdk 26.2`
       - `macos-arm64_x86_64`：`platform 1 (MACOS)`, `minos 14.0`, `sdk 26.2`
  2. **`libffi`（`Scripts/build-apple-libffi.sh`）**：
     - 首次运行 `Scripts/build-apple-libffi.sh ios`：以 `clang -target arm64-apple-ios16.0` 编译，生成 `build/apple-runtime/libffi-ios-3.4.8/install/lib/libffi.a` 并记录 `.deployment-target` 为 `arm64-apple-ios16.0`。
     - 第二次运行 `Scripts/build-apple-libffi.sh ios`：检测到 `.deployment-target` 匹配 `arm64-apple-ios16.0`，输出 `Static libffi (cached for arm64-apple-ios16.0)` 直接复用。
     - 模拟旧缓存：向 `build/apple-runtime/libffi-ios-3.4.8/.deployment-target` 写入 `arm64-apple-ios17.0` 后运行 `Scripts/build-apple-libffi.sh ios`，脚本自动清理旧目录并按 `arm64-apple-ios16.0` 重建，`otool -l` 验证 `minos 16.0`。
     - 平台隔离验证：运行 `Scripts/build-apple-libffi.sh tvos`，生成独立目录 `build/apple-runtime/libffi-tvos-3.4.8`，`.deployment-target` 为 `arm64-apple-tvos17.0`，`otool -l` 验证 `platform 3`, `minos 17.0`，与 iOS 产物互不覆盖。
  3. **`Unicorn TCI`（`Scripts/build-apple-interpreter.sh`）**：
     - 首次运行 `Scripts/build-apple-interpreter.sh ios`：以 `-target arm64-apple-ios16.0` 与 `-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0` 编译 `build/apple-runtime/unicorn-tci-ios/libunicorn.a`，检查 `CMakeCache.txt` 确认 `UNICORN_INTERPRETER:BOOL=ON`（纯解释模式未改变），写入 `.deployment-target` 为 `ios:16.0`。
     - 第二次运行 `Scripts/build-apple-interpreter.sh ios`：命中缓存复用。
     - 模拟旧缓存：向 `build/apple-runtime/unicorn-tci-ios/.deployment-target` 写入 `ios:17.0` 后运行脚本，自动清理并重建，`otool -l` 验证 `platform 2 (IOS)`, `minos 16.0`, `sdk 26.2`。

---

## 3. 状态管理（Observation）向下兼容选型与小范围验证（对应 Tasks 3.1 ~ 3.5）

### 3.1 成熟 Observation 向下兼容候选核查与选型结论（Task 3.1）
- **选定方案**：[`pointfreeco/swift-perception`](https://github.com/pointfreeco/swift-perception)，固定版本 `1.6.0`（`exactVersion: 1.6.0`）。
- **核心核查项**：
  1. **官方文档与最低系统要求**：支持 iOS 13.0+、macOS 10.15+、tvOS 13.0+、watchOS 6.0+，完全覆盖本次 iOS / iPadOS 16.0 目标。
  2. **系统原生路径（iOS 17+ 零退化）**：
     - `@Perceptible` 内部生成的 `PerceptionRegistrar` 在 `#available(iOS 17, macOS 14, tvOS 17, *)` 环境自动委托给系统标准库 `Observation.ObservationRegistrar`。
     - `WithPerceptionTracking` 在 iOS 17+ / macOS 14+ / tvOS 17+ 直接透传视图 `content()`，走 SwiftUI 系统原生 Observation 追踪；仅在 iOS 16 下启用 `PerceptionRegistrar` 订阅与刷新。
  3. **Swift 6 支持**：原生支持 Swift 6.0 / 6.2 严格并发模式（`Sendable` 与 `@MainActor` 隔离兼容）。
  4. **开源许可**：MIT License，与仓库完全兼容。
- **需要变更的宏、绑定、环境与追踪入口映射表**：
  | 原 iOS 17+ 语法 | 兼容 iOS 16+ 统一语法 | 备注 |
  | :--- | :--- | :--- |
  | `import Observation` | `import Perception` | 在包含可观察模型或追踪的文件中导入 |
  | `@Observable` | `@Perceptible` | 保持类属性、方法与存储含义 100% 不变 |
  | `@ObservationIgnored` | `@PerceptionIgnored` | 保持忽略观察语义不变 |
  | `@Bindable var model` | `@Perception.Bindable var model` | 支持 iOS 16 下的 `$model.property` 双向绑定 |
  | `withObservationTracking(_:onChange:)` | `withPerceptionTracking(_:onChange:)` | 用于 `App/MusicRemoteControl.swift:49` 等手动追踪 |
  | `View.body`（读取可观察对象） | `WithPerceptionTracking { ... }` | 包裹视图主体及 `ForEach` / `sheet` / `NavigationStack` 延迟闭包 |
  | `@Environment(ModelType.self)` / `.environment(model)` | 无需修改（导入 `Perception` 即可） | `Perception` 已内置 `Environment.init(_: Value.Type)` 与 `View.environment(_:)` backport |

### 3.2 ~ 3.5 独立验证 Target (`Packages/IOS16ObservationSpike`) 编译与验证结果
- **独立验证包位置**：`Packages/IOS16ObservationSpike/Package.swift`
  - 平台声明：`platforms: [.iOS(.v16), .macOS(.v14), .tvOS(.v17)]`
  - 依赖清单：仅依赖 `https://github.com/pointfreeco/swift-perception.git` (`exact: "1.6.0"`)，未导入整个 `Store`、`RootView` 或 `TVCore`。
  - 编译源文件清单：
    - `Sources/IOS16ObservationSpike/ObservationSpikeModels.swift`（`SpikeNestedFilter`、`SpikeSiteRowModel`、`SpikeSubscriptionStore`、`SpikePlaybackSession`、`SpikeRemoteObserver`、`AppBindable`）
    - `Sources/IOS16ObservationSpike/ObservationSpikeViews.swift`（`SpikeLazySiteRowView`、`SpikeSubscriptionView`、`SpikeSubscriptionContentView`、`SpikePlaybackContainerView`）
    - `Tests/IOS16ObservationSpikeTests/ObservationSpikeTests.swift`
- **实测编译与自动化回归结果**：
  1. **iOS 16.0 目标编译**：
     ```bash
     cd Packages/IOS16ObservationSpike && swift build --triple arm64-apple-ios16.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
     ```
     结果：`Build complete! (3.26s)`，零错误通过。
  2. **跨平台（macOS 14.0）编译与单元测试运行**：
     ```bash
     cd Packages/IOS16ObservationSpike && swift test
     ```
     结果：`Test run with 2 tests in 1 suite passed after 0.015 seconds`：
     - `subscriptionAndNestedObservation()`：验证 `@AppBindable` 双向绑定写入、嵌套 `@Perceptible` 对象 (`SpikeNestedFilter`) 属性变化追踪、异步搜索结果更新、以及延迟列表行模型 (`SpikeSiteRowModel`) 独立属性追踪均触发预期回调。
     - `playbackLifecycleAndManualTracking()`：验证首次加载 (`startTaskCount == 1`)、打开/关闭弹层 (`isPresentingDetailSheet`)、进度拖动 (`seek(to: 35)`) 及视图重入调用 `loadIfNeeded` 时不重复启动底层任务 (`startTaskCount` 保持 `1`)，且 `SpikeRemoteObserver` 的 `withPerceptionTracking` 连续捕获 `"pause@0" -> "play@0" -> "play@35" -> "pause@35"`。
- **关键发现与统一迁移模式（Task 3.5）**：
  1. `@Perceptible` 在 `macOS 14+` / `tvOS 17+` 展开时自动生成 `extension Model: Perception.Perceptible, Observation.Observable`，但在这些新系统目标上 `Perception.Bindable` 的 setter 被标记为 `obsoleted`。因此跨平台视图统一使用类型别名：
     ```swift
     #if os(iOS)
     public typealias AppBindable<Value: AnyObject & Perceptible> = Perception.Bindable<Value>
     #else
     public typealias AppBindable<Value: AnyObject & Observable> = SwiftUI.Bindable<Value>
     #endif
     ```
  2. `Perception` 原生提供了 `@_disfavoredOverload` 的 `Environment.init(_: Value.Type)` 与 `View.environment(_:)`，在 iOS 16 下自动回退到基于 `EnvironmentKey` 的存储，在 iOS 17+ / macOS 14+ / tvOS 17+ 下走系统原生 `Environment`，因此全仓库 70 处 `@Environment(Model.self)` 和 4 处 `.environment(model)` 仅需 `import Perception` 即可保持原写法不变。


---

## 4. Java 运行库及原生绑定重建与检查（对应 Task 2.5）

### 2.5 真机与模拟器 `AppleRuntime` 重建与二进制核查
- **修复构建环境问题**：
  - OpenJDK `configure` 在构建 `macosx-aarch64` host 工具（`buildjdk`）时，若环境变量中存在已导出的 `TVOS_DEPLOYMENT_TARGET=17.0`，Apple Clang 会报 `clang: error: overriding '-mmacosx-version-min=11.0.0' option with '-mtvos-version-min=17.0'`。
  - 在 `Scripts/apple-deployment-targets.sh` 中增加 `export -n TVOS_DEPLOYMENT_TARGET`（保留 `YINGXIA_TVOS_DEPLOYMENT_TARGET=17.0` 供需要 tvOS 目标的脚本显式读取），并在 `Scripts/build-apple-jvm.sh` 与 `Scripts/build-apple-native-bindings.sh` 中将 `.deployment-target` 标记写入与平台最低版本绑定。
- **重建与 Mach-O 检查结果**：
  1. **iOS 真机归档 `build/AppleRuntime/iphoneos`**：
     - 产物：`build/AppleRuntime/iphoneos/lib/libTVAppleRuntime.a`（35M）与 `build/AppleRuntime/iphoneos/Resources/lib/lib/modules`（48M）
     - `.build-stamp`：包含 `iosDeploymentTarget=16.0`
     - `otool -l build/AppleRuntime/iphoneos/lib/libTVAppleRuntime.a | grep -A 3 "cmd LC_BUILD_VERSION"`：全部 `.o` 成员均为 `platform 2 (IOS)`, `minos 16.0`, `sdk 26.2`。
  2. **iOS 模拟器归档 `build/AppleRuntime/iphonesimulator`**：
     - 产物：`build/AppleRuntime/iphonesimulator/lib/libTVAppleRuntime.a`（35M）与 `build/AppleRuntime/iphonesimulator/Resources/lib/lib/modules`（48M）
     - `.build-stamp`：包含 `iosDeploymentTarget=16.0`
     - `otool -l build/AppleRuntime/iphonesimulator/lib/libTVAppleRuntime.a | grep -A 3 "cmd LC_BUILD_VERSION"`：全部 `.o` 成员均为 `platform 7 (IOSSIMULATOR)`, `minos 16.0`, `sdk 26.2`。

---

## 5. 状态迁移、界面集中适配与全量 iOS 16 构建（对应 Tasks 4.1 ~ 4.7）

### 4.1 & 4.2 状态管理全量迁移与视图感知追踪
- **跨平台观察兼容入口**：`Sources/TVCore/ObservationCompatibility.swift`
  - 统一 `@_exported import Perception`，并提供跨平台 `@AppBindable` 类型别名。
- **模型层迁移**：
  - `Sources/TVCore/` 下全部 16 个可观察模型文件与 `App/` 下全部 15 个可观察模型文件均已从 `@Observable` / `@ObservationIgnored` 迁移至 `@Perceptible` / `@PerceptionIgnored`。
  - `App/MusicRemoteControl.swift` 手动观察追踪已迁移为 `withPerceptionTracking`。
- **视图层追踪封装**：
  - 在 `App/GlassKit.swift` 中集中定义 `AppPerceptionTracking`，在 iOS 16 下自动包裹 `WithPerceptionTracking`，在 iOS 17+ / macOS / tvOS 下零开销直通；同时在 `navigationDestinationCompat` 的 iOS 16 分支与 `App/RootView.swift` 的 `routeDestinations()`、`PlayerPresentation` 中自动包裹感知追踪。
  - `App/` 下全部 iOS 可达的 230+ 个 `View` 与 `ViewModifier` 的 `body` 均已接入 `AppPerceptionTracking`。

### 4.3 ~ 4.5 界面兼容层集中封装（`App/GlassKit.swift`）
- 在 `App/GlassKit.swift` 中集中封装所有 iOS 17+ / 16.4+ 视图与修饰符差异：
  - `onChangeCompat`（覆盖零参/双参及 `initial: true` 语义）
  - `AppContentUnavailableView`（含标准标题/图标与 `.search(text:)` 预设，iOS 17+ 走原生 `ContentUnavailableView`，iOS 16 走统一空状态布局）
  - `pulseSymbolEffect`、`bounceSymbolEffect`、`variableColorSymbolEffect`、`wiggleSymbolEffect`、`breatheSymbolEffect`、`rotateSymbolEffect`、`replaceSymbolTransition`
  - `sensoryFeedbackCompat`（iOS 16 回退 `UISelectionFeedbackGenerator` / `UIImpactFeedbackGenerator`）
  - `scrollPositionCompat`（iOS 16 回退 `ScrollViewReader` + `onChangeCompat` 自动滚动定位，支撑歌词跟随与剧集定位）、`scrollTargetLayoutCompat`、`scrollClipDisabledCompat`、`horizontalScrollContentMargins`、`verticalContainerRelativeFraction`
  - `navigationDestinationCompat(item:destination:)`、`sheetPresentationBackground`、`focusEffectDisabledCompat`
  - `springAnimation`、`snappyAnimation`、`smoothAnimation`、`withAnimationCompat`
  - `Color.blend(with:by:)`（iOS 16 使用 `UIColor.getRed(_:green:blue:alpha:)` 线性插值）

### 4.6 正式工程配置与全量 iOS 16 构建验证
- `Package.swift`（`.iOS(.v16)`）、`project.yml`（`iOS: "16.0"`）与 `TVBox.xcodeproj/project.pbxproj`（`IPHONEOS_DEPLOYMENT_TARGET = 16.0`）已正式落地，Bundle ID (`com.jo32.yingxia.ios`) 与 macOS (`15.0`) / tvOS (`17.0`) 配置保持不变。
- 执行 `TVCore` 与 `TVBox-iOS` 全量构建（`arm64-apple-ios16.0`，Release）：
  - 早期诊断报告的全部编译错误均已清零，链接生成 `build/XcodeBuild/Release-iphoneos/TVBox-iOS.app/TVBox-iOS`（`** BUILD SUCCEEDED **`）。
  - 检查 `TVBox-iOS.app` 内置资源：`lib/`（OpenJDK modules）、`JavaHost/host.jar`、`PythonHost/`、`NodeHost/`、`python/`、`Frameworks/NodeMobile.framework`、`Frameworks/Python.framework` 及全部扩展 `.framework`、`TVCore_TVCore.bundle`、`Assets.car`、`AppIcon`、`releases.json`、`runtime-probe.jar` 均已完整嵌入。

### 4.7 iOS 16 更新检查兼容说明
- 在 `Sources/TVCore/ReleaseFeed.swift` 新增 `UpdateResolution` 与 `resolveUpdate(after:platform:intelMac:requiresCompatibleBuild:)`，并在 `App/Updates.swift` 中根据 `#available(iOS 17, *)` 决定 `requiresCompatibleBuild`：
  - 当 iOS 16 检测到上游新版本时，保留新版本号与更新日志展示，不误报“已是最新”，并将直接下载未经验证上游 iOS 17+ IPA 的按钮替换为兼容构建获取与原位更新说明。
  - 单元测试 `Tests/TVCoreTests/ReleaseFeedTests.swift` 中 `compatibleBuildResolutionPreservesVersionWithoutDirectUpstreamLinkOnIOS16()` 运行通过（`✔ Test compatibleBuildResolutionPreservesVersionWithoutDirectUpstreamLinkOnIOS16() passed`）。

---

## 6. 最终候选 Release IPA 打包检查与持续验证入口（对应 Tasks 5.3, 6.2, 6.3）

### 5.3 本地侧载 Release IPA 产物检查记录
- **构建与打包信息**：
  - 分支与配置：`codex/support-ios16`，显式 `Release` 配置，未使用上游发布凭据，未启用 `APPSTORE` 编译条件。
  - 应用标识与版本：`com.jo32.yingxia.ios`，版本 `1.8.3 (41)`，`MinimumOSVersion = 16.0`。
  - 候选 Release IPA 路径：`build/sideload/Yingxia-iOS16-Release.ipa`（108 MB）
  - **SHA-256**：`e77315a7c946cba424b65d6a13665dee763a6b801c29d2e838951d5f26806a88`
- **二进制与签名核查**：
  - `otool -l build/XcodeBuild/Release-iphoneos/TVBox-iOS.app/TVBox-iOS`：`platform 2 (IOS)`, `minos 16.0`, `sdk 26.2`。
  - `otool -L`：`libswiftObservation.dylib` 为 `weak` 链接，无 iOS 17+ 强符号依赖。
  - `nm -gU`：保留 `_JIMAGE_Open`、`_JNI_CreateJavaVM`、`_Java_com_sun_jna_Native_*` 等全部必需全局符号。
  - `codesign -vv build/XcodeBuild/Release-iphoneos/TVBox-iOS.app`：`valid on disk`、`satisfies its Designated Requirement`。

### 6.2 & 6.3 验证入口与安装文档更新
- 在 `Scripts/verify.sh` 中增加 `verify_ios_min_target`（支持 `Scripts/verify.sh --ios-min-target` 独立调用及全量 `Scripts/verify.sh` 联动调用），实测执行输出：
  ```text
  Checking TVCore for arm64-apple-ios16.0...
  TVCore iOS 16.0 build passed (build/verify-tvcore-ios16.log)
  Checking TVBox-iOS target for arm64-apple-ios16.0...
  TVBox-iOS minos 16.0 build & Mach-O check passed (build/verify-ios-min-target.log)
  ```
- 在 `Docs/DEVELOPMENT.md` 中补充上游合并检查清单（新增系统接口集中封装、`@Perceptible`/`AppPerceptionTracking` 观察规范、原生依赖 `minos 16.0` 检查）。
- 在 `Docs/INSTALL.md` 与 `.agents/skills/install-yingxia/SKILL.md` 中更新 iOS 16 兼容构建说明、本地侧载打包命令、同 Bundle ID 原位更新要求及 `DeviceOSVersionTooLow` 排错说明，保留 `tvOS 17+` 要求，并明确标注兼容构建尚待真机最终验收。

## 7. 代码审查修复复核（2026-10-30）

- Python wheels：两类扩展的 pip 编译调用统一增加 `--no-cache-dir`；wheel 配方标记增加 `no-pip-cache-v1`，使旧标记产物失效一次。临时隔离回归夹具验证旧 wheel 被移除、两次编译调用均禁用 pip 缓存、重复执行复用匹配产物，并保留匹配的底层依赖缓存。
- 现有 iphoneos wheels 的 47 个 `.so` 经 `otool -l` 检查，最低版本均为 16.0；该结果仅属于现有产物审计，不替代修复脚本后的实际重建或 iPad 加载验证。
- 网盘文件播放按钮的标签闭包内部增加 `AppPerceptionTracking`，覆盖收藏状态读取；Swift 语法解析通过，实际收藏/取消收藏后心形即时刷新仍待 iOS 16 运行环境验证。本机 `simctl list runtimes` 当前为空。
- `verify.sh --ios-min-target` 恢复完整图片资源编译，移除手工修改图标 plist；改用独立 DerivedData 和 `clean build`，防止旧资源掩盖缺失。上文第 6 节的旧构建通过记录包含跳过资源的诊断配置，不能作为修复后完整构建的证据。
- Bash 语法检查、Swift 语法解析、差异空白检查和 OpenSpec 严格校验通过。
- 完整构建与 Python 实际重建待执行：远端检查发现 `upstream/main` 已从 `6ce6f6e` 前进至 `a5834c1`，含 iCloud 同步等与本地适配重叠的变更。按 AGENTS.md，先整合上游，或获得用户对本次仅验证当前基准的明确例外后再构建；已请求用户选择。本次未提交、推送或合并上游。


## 8. 整合上游后的修复验证（2026-10-30）

- 用户明确选择先整合上游再验证。已将兼容分支从 `6ce6f6e` 快进至 `a5834c1`，未创建新提交。整合前的 117 个已修改/未跟踪文件及二进制补丁备份位于 `build/ios16-before-upstream/`。
- 四份翻译文件冲突已保留双方新增文案；上游新增的五个 `@ObservationIgnored` 改为 `@PerceptionIgnored`，iCloud 设置开关的两个新式 `onChange` 改为 `onChangeCompat`。无未解决冲突，所有适配改动仍未提交。
- Python：实际执行 `Scripts/build-apple-python-wheels.sh ios` 及 `Scripts/build-apple-python.sh ios` 成功；新的 wheel 标记为 `iphoneos:16.0:no-pip-cache-v1`。对新生成 wheel 的 47 个原生扩展检查，最低版本均不高于 16.0。
- 观察机制：`swift test --package-path Packages/IOS16ObservationSpike` 的两项模型测试通过（macOS 执行）；这不替代 iOS 16 上实际文件行收藏图标刷新验收。
- 核心回归：`swift test --filter 'CloudSyncTests|ReleaseFeedTests|FavoritesTests'` 共 36 项，35 项通过；`relaunchFailureIsTranslated` 有两条语言断言失败，其对应文案与上游 HEAD 完全相同，不属于本次修复引入。另有本地化检查因已有位置参数格式判断失败，保留原文案，未扩大修复范围。
- 环境：首次完整构建被缺少 iOS 平台组件阻断。经用户授权安装后，Apple 服务未提供精确的 26.2，默认安装的 iOS 26.3.1 运行时（23D8133）在 `simctl runtime list` 中为 Ready，约 7.8 GB；未升级任何 iPad。没有安装 iOS 16 模拟器。
- 完整构建：`Scripts/verify.sh --ios-min-target` 通过。TVCore 的 `arm64-apple-ios16.0` 构建通过，独立 `build/Verify-ios-min-target` 执行完整 `clean build`（含两份 xcassets），结果 `BUILD SUCCEEDED`。未手工改写图标 plist、未跳过资源。
- 实际产物核查：新生成的 Release 应用最低版本 16.0；`Assets.car` 存在，图标元数据为 AppIcon；Python 与 Node 框架均已嵌入；`JIMAGE_Open`、`JNI_CreateJavaVM` 全局符号保留。该结果属于构建与产物检查，未进行 Archive/IPA 真机验收，未替换之前的候选 IPA。
- 语法、差异空白、OpenSpec 严格校验通过。iOS 16 UI 刷新和真机运行仍未验证，本次未勾选对应运行验收任务，未提交或推送。


## 9. iPad 16.4 Debug 构建与启动尝试（2026-10-30）

- 构建前已获取远端，将分支从 `a5834c1` 快进至 `56f9aa7`，保留本地适配；上游播放器修复自动合并成功，没有创建新提交。
- 使用 `TVBox.xcodeproj` / `TVBox-iOS`，Debug 配置，目标为用户创建的 `ipad 16.4`（0DFFFD53-C94B-48AD-AB4E-8E92C38EC736，iOS 16.4 / 20E247），DerivedData 为 `build/Debug-iPad16`。命令行使用单次 `-skipMacroValidation`，未修改 Xcode 全局宏信任设置；GUI 仍需对 swift-perception 宏进行启用确认。
- 首次 Debug 构建发现 `App/PlayOn.swift` 的 DEBUG 专用 `qaPlayOn` 回调仍使用 iOS 17 `onChange`；已改为 `onChangeCompat`，再次构建 `BUILD SUCCEEDED`，日志为 `build/debug-ipad16-build.log`。
- 模拟器首次启动等待 LaunchServices 数据迁移超过六分钟。保留数据重启后，启动状态停在 Waiting on BackBoard，界面仍为 Apple 开机进度条。App 安装/启动请求未完成，尚无应用运行日志，不将系统初始化等待记作 App 崩溃或运行通过。启动记录在 `build/debug-ipad16-boot.log` 和 `build/debug-ipad16-reboot.log`。
- 代码构建通过不等于 iOS 16 运行验收。未勾选模拟器核心流程或真机验收任务，未提交或推送。


## 10. iOS 16 iPad 精简导航（2026-10-30）

- 按用户追加要求，复用 `PhoneTabs` 的存储、排序、隐藏、编辑器与 More 导航。iOS 16 的 iPad 全屏也进入该既有路径，固定四个常用栏目加“更多”；默认栏目为现在观看、直播、音乐、全局搜索。iOS 17+ 的布局判断及宽屏槽位数不变，未修改存储格式或新增偏好项。
- `RootView` 与 `MoreView` 共用的 `PhoneTabs.slots` 在 iOS 16 返回四个槽位，保证导航、更多列表和编辑器的栏目集合一致。
- 构建前获取远端，按既有规范将上游弹幕/网盘修复快进整合至 `f71f862`；保留两边翻译条目和本地适配，并重建 Java host、同步模拟器资源。无新增提交或推送。
- `TVBox-iOS` / Debug / 用户 iPad 16.4 模拟器构建通过，日志 `build/nav-ipad16-build.log`。保留容器安装更新并启动成功。
- 模拟器界面实测：底部显示现在观看、直播、音乐、全局搜索、更多；更多页包含点播源、网盘文件、播放历史、收藏、下载、消息、设置及现有编辑标签栏入口。进入播放历史并返回更多通过。
- 新系统代码分支保持原表达式，未对新系统运行界面作本轮实测。差异空白与 OpenSpec 校验通过。黑屏问题不属于本节的验证结论。


## 11. 真机测试 Release IPA（2026-10-30）

- 用户授权构建真机测试包，构建前获取 origin/upstream，当前 HEAD `f71f862` 已包含 upstream/main；未创建提交或推送。
- 已重新构建 Java host 并同步 iphoneos 资源；以 TVBox-iOS scheme、显式 Release、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO 执行 Archive，结果 ARCHIVE SUCCEEDED；未启用 APPSTORE。
- 从归档完整应用复制封装 Payload，内嵌框架及应用作 ad-hoc 签名，codesign --verify --deep --strict 和 ZIP 完整性检查通过；供 TrollStore 安装，不宣称普通 iOS 无签名直接安装。
- 版本 1.8.3 (41)，Bundle ID `com.jo32.yingxia.ios`，MinimumOSVersion 16.0；103 个 Mach-O 二进制逐项检查均为 arm64 真机架构、最低系统版本不高于 16.0。Python/Node 框架、PythonHost、JavaHost、jimage 模块、Assets.car 均存在，JIMAGE_Open/JNI_CreateJavaVM/JNA 符号保留。
- IPA：`/Users/konvy-1054/www/ai/tvbox-silicon/build/sideload/ios16-test-20261030.Wko8OK/Yingxia-1.8.3-iOS16-Test.ipa`，大小 113800023 字节。
- SHA-256：`f767f4a0ecd3f0df01eca81f7d16f11e433e0a4b5b7c7a918e0f2118893aaa08`；归档、SHA256.txt 和 build-info.json 保存在同目录。
- 本包包含最新 iOS 16 iPad 精简导航；真机安装、播放及黑屏原因仍待验证，未勾选真机验收任务。
