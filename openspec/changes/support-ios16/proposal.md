## Why

映匣当前最低要求 iOS / iPadOS 17，使保留 iPadOS 16 和 TrollStore 安装环境的设备无法使用。希望在持续合并上游更新的前提下，将最低版本降至 16.0，保留核心功能，并避免维护两套应用。

## What Changes

- 使用同一套源码与同一份 iOS IPA 支持 iOS / iPadOS 16.0 及以上系统；macOS、tvOS 的支持范围不变。
- 先独立验证 Java/JAR、QuickJS、Python、Node.js 和媒体原生依赖的旧系统兼容性；核查预编译二进制实际最低版本，按需重建，避免只修改版本声明。
- 优先采用成熟的 Observation 向下兼容方案，保留模型属性、方法和业务逻辑；先用最低目标为 iOS 16 的独立验证 target 确认机制，再迁移真实页面，并在全面迁移前完成一次最低目标诊断编译。
- 集中封装界面接口差异，iOS 17+ 使用原有能力，iOS 16 使用满足交互需求的替代实现；不要求视觉效果完全一致。
- 调整构建目标及缓存识别，补充 iOS 16 模拟器、用户 iPad 真机和新系统回归验证，明确音乐、直播、网盘登录与实际播放的代表性验收流程；最终使用本地 Release 归档并封装的同一份侧载 IPA 验收，形成持续合并上游的检查流程。
- 明确不依赖上游发布凭据、不启用 APPSTORE 的本地归档、IPA 封装及签名路径，先用最小测试入口验证 TrollStore 安装；不把 TestFlight 发布脚本作为前提。
- iOS 16 的更新入口明确要求经过验证的兼容构建，不把未经验证的上游 IPA 作为可直接安装的更新；新系统更新行为保持不变，不自建更新服务。
- 增加 iPad 全屏/紧凑分屏切换及一个 iOS 16 iPhone 模拟器的核心流程验收。
- 非目标：不升级或更换设备系统，不实现 TrollStore 安装工具，不重构无关业务，不迁移数据模型，不扩展第三方插件兼容范围。

## Capabilities

### New Capabilities

- `ios16-compatibility`: 定义单份 iOS 应用在 iOS / iPadOS 16 及以上的运行、状态刷新、插件执行、媒体播放、数据保留和兼容验收要求。

### Modified Capabilities

无。当前解析到的 OpenSpec 主规格目录为空，没有可复用的既有能力路径。

## Impact

- 实现仓库：`/Users/konvy-1054/www/ai/tvbox-silicon`。本变更规划已纳入该仓库的 `openspec/changes/support-ios16`，在仓库根目录运行 OpenSpec 命令及后续实现操作；主目录中的旧规划仅作迁移备份，不再作为本仓库的维护入口。
- Git：`origin` 指向 `zhiqiangwong/tvbox-silicon`，`upstream` 指向 `jo32/tvbox-silicon`；使用 `codex/support-ios16` 分支实施，按 AGENTS.md 同步上游，提交和推送遵循用户授权。
- 配置：`project.yml`、`Package.swift`、生成的 Xcode 工程及相关安装说明。
- 运行环境：`Scripts/build-apple-{jvm,libffi,interpreter,native-bindings,ffmpeg,python,python-wheels}.sh`、`Scripts/package-apple-runtime.sh`，以及 Node.js 获取/嵌入脚本。保留既有版本，除非核查证明其无法满足 iOS 16。
- 应用：`App/GlassKit.swift`、状态模型、环境注入/绑定、使用新系统接口的相关页面，以及 `App/Updates.swift` 的旧系统更新提示和操作入口；复用既有更新数据结构，仅作兼容所需修改。
- 交付：记录本地 Release 归档、IPA 封装及签名命令，复用现有构建和产物检查，保留 TestFlight 分发流程。
- 验证：复用现有 JVM spike、原生桥接测试、核心测试与构建检查；补充必要的 iOS 16 实际运行与真机记录。
- 前置条件：此前检查没有可用的完整 Xcode/iPhoneOS SDK 验证环境与 JVM 构建产物，随后命令出现 Xcode 许可尚未接受提示；实施前重新核实工具链、许可状态及可用的 iOS 16 模拟器与 Xcode/macOS 组合。用户设备报告的“16.6.6”尚未核实，验收以设备实际系统版本为准。
- 证据边界：此前仅完成部分源码核查，尚未证明 JVM、Python、Node.js 或整套应用已在 iOS 16 运行；此前 4～9 个开发日仅作粗估，先行验证后重新估算。
