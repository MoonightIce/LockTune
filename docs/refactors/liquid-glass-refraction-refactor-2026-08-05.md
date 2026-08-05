# LockTune Liquid Glass 折射完整重构方案

状态：设计已验收，待 `LockTune Debug` 实施  
日期：2026-08-05  
目标系统：macOS 26+；macOS 14–25 保持可运行降级  
上游基线：

- `Meridius-Labs/electron-liquid-glass`：`a50d96f981d5adea40c368639fccbb0a9b06ef17`
- `Neo-Isshin/TokenClock`：`a56cc20bc83adfa587a86fe1c0012a0f4a8e8408`

## 1. 问题陈述

LockTune 现有实验实现把公开 Liquid Glass、`NSVisualEffectView`、自定义渐变和边缘高光混成一个材质概念。它可以呈现半透明胶囊，但不能证明画面使用了 `electron-liquid-glass` / TokenClock 所依赖的原生折射路径，也不能稳定复现 TokenClock 的 Dock 材质、最大 lensing 和非激活浮窗表现。

旧的“主窗口局部公共 API Demo”任务与本方案冲突，正式废止。最终落点是 LockTune 顶部独立 Island panel 本身，不是在主窗口日历区增加演示卡片。旧 `GlassEdgeMaterial`、边缘 ring mask、用 blur 数值模拟折射的逻辑均不保留。

“完整实现”在本文中的可验证定义是：

1. Island 的真实材质视图是 macOS 26 的 `NSGlassEffectView`。
2. 玻璃位于透明内容层下方，覆盖 Island 的完整可见表面；这沿用 electron 项目的原生 view-under-content 宿主关系。
3. 默认视觉参数是 TokenClock 的 Dock 配方：`variant = 2`，`contentLensing = 6`，并严格先设置 variant、再设置 lensing。
4. 玻璃下方有 TokenClock 式 `.menu` / `.behindWindow` / `.active` 的 `NSVisualEffectView` 底板，透明度独立可调。
5. Island 非 key、非 main、应用失焦时仍维持 active glass appearance。
6. 画面验收能证明背景几何发生折射位移，而不只是颜色、透明度或 blur 改变。

私有 SPI 可能被系统更新移除，因此无法承诺未来所有 macOS 版本永远保持同一结果。本方案保证的是：在验收系统上真实调用该路径；运行时能力缺失时明确记录并降级，绝不把公开材质回退误报为“完整折射”。

## 2. 上游事实与采用边界

### 2.1 electron-liquid-glass 提供的核心机制

- 从 Electron native window handle 得到 Cocoa 根 `NSView`。
- 创建 `NSGlassEffectView`，按容器 bounds 覆盖，并插到 WebContents 下方。
- 设置圆角、公开 `tintColor`；旧系统回退到 `NSVisualEffectView`。
- 通过 Objective-C runtime 探测并调用 `set_variant:`、`set_scrimState:`、`set_subduedState:`。
- 没有 Metal、Core Image、WebGL 或自定义 shader；折射由 AppKit / WindowServer 完成。

LockTune 不移植 Electron、Node-API、native handle buffer 或全局 view registry，只移植其 AppKit 宿主关系、系统玻璃视图和运行时 setter 机制。

### 2.2 TokenClock 提供的视觉配方

- 完整表面 `NSGlassEffectView`，而非边缘 mask。
- `variant = 2`，`contentLensing = 6`；variant 会重建内部层，因此顺序必须固定。
- `NSVisualEffectView(material: .menu, blendingMode: .behindWindow, state: .active)` 位于折射层下方。
- 动态 `GlassAurora` 位于最底层，为任何桌面背景提供可折射的亮暗和色彩结构。
- 非激活 `NSPanel` 通过五个 `_has…Appearance` 私有方法保持 active appearance。
- tint 优先探测下划线私有 setter，缺失时使用公开 `tintColor`。在 macOS 26.3 的本机探针中，variant 和 contentLensing 存在，`set_tintColor:` 不存在，因此公开 tint 回退是必需路径。

### 2.3 明确不复制的内容

- 不复制 Electron 的 JS API、Node addon、C++ registry 或透明 BrowserWindow 配置。
- 不复制 TokenClock 的时钟业务、主题模型、窗口拖拽和菜单代码。
- 不把 Aurora、自定义 tint 或毛玻璃底板宣传成系统折射算法。
- 不新增屏幕录制、ScreenCaptureKit、摄像头或网络权限。
- 不声称此实现兼容 Mac App Store；私有 SPI 构建只适合实验或直接分发决策。

## 3. 目标架构

### 3.1 模块边界

新增一个只属于 `IslandPresentation` 的深模块 `LiquidGlassSurface`，对调用方只暴露以下概念：

- `LiquidGlassConfiguration`：tint、backing alpha、lensing、是否动态 Aurora、可访问性降级。
- `LiquidGlassCapabilities`：系统版本、glass class、variant、lensing、underscored tint、active-window override 是否可用。
- `LiquidGlassRuntimeMode`：完整私有折射、公开玻璃降级、降低透明度不透明降级。
- `LiquidGlassSurfaceHost`：拥有 AppKit view 生命周期和内容宿主；业务层不直接接触 selector。

`AppSession` 继续拥有用户设置；`IslandCoordinator` 只决定内容和几何，不知道 AppKit SPI。`IslandWindowController` 只创建 panel、安装 host、传入配置和内容。

### 3.2 视图层级

Island panel 的 `contentView` 改为一个单一的 AppKit 宿主，内部从下到上固定为：

```text
IslandPanel (transparent, nonactivating)
└─ LiquidGlassSurfaceHost
   ├─ AuroraHostingView
   ├─ NSVisualEffectView (.menu / .behindWindow / .active)
   ├─ NSGlassEffectView (variant 2 / lensing 6 / tint / full surface)
   └─ NSHostingView<IslandContent> (transparent content only)
```

四层共享同一个 bounds、连续圆角和 clip geometry。内容层不能再自行绘制材质背景；它只负责音乐、会议、idle 文案和交互。

采用显式 AppKit 宿主而不是多个 SwiftUI `background`/`ZStack` representable，目的是让 z-order、resize、view 生命周期和玻璃对桌面的 sampling 关系可检查、可测试，并与 Electron 的 native-view-under-content 机制一致。

### 3.3 SPI 适配器

所有 runtime 调用集中到一个文件/类型，不允许 selector 字符串散落在窗口、设置页或 SwiftUI view 中。

规则：

1. 仅在 macOS 26+ 创建 `NSGlassEffectView`。
2. 每个 selector 调用前执行 `responds(to:)`，再读取 IMP；不直接使用未声明方法。
3. 整数 setter 使用与当前架构匹配的 Objective-C calling convention。
4. 配置顺序固定为 variant、contentLensing、scrim、subdued、tint、corner geometry。
5. 默认值固定：variant 2、lensing 6、scrim 0、subdued 0。
6. underscored tint 缺失时使用公开 `view.tintColor`；设置为 nil 时必须清除旧 tint。
7. 运行时输出一条不含用户数据的 capability 诊断，并在设置页显示“完整折射 / 已降级”，方便验收。
8. selector 缺失不崩溃；模式降级为公开 `NSGlassEffectView`，并明确标记“不满足完整折射验收”。

### 3.4 非激活面板

active appearance override 只安装到 `IslandPanel` 子类，不修改 `NSWindow` 全局实现。安装一次，记录五个 selector 的存在性：

- `_hasActiveAppearance`
- `_hasActiveAppearanceIgnoringKeyFocus`
- `_hasActiveControls`
- `_hasKeyAppearance`
- `_hasMainAppearance`

每个 override 返回 true。若系统缺少任一 selector，保留可运行状态并报告 capability mismatch；验收时切到其他应用，玻璃必须继续保持折射和明度，不能变成 dimmed 普通透明层。

### 3.5 参数与设置迁移

- `glass.tint`：保留，范围 0…0.30；应用到公开 tint，极端黑白颜色将 alpha 上限压到 0.5。
- 旧 `glass.blur`：只用于一次性迁移到底板档位，迁移完成后不再参与渲染。
- `glass.backing`：保留五档 0/25/50/75/100，映射为 `NSVisualEffectView.alphaValue` 0…1。
- `glass.refraction`：迁移为离散 lensing 0…6；旧 0…160 值按四舍五入映射。新安装默认 6，产品预设“TokenClock”固定为 6。
- `glass.motion`：只控制 Aurora 动画；Reduce Motion 时强制静止。
- 新增本机恢复开关 `glass.privateRefractionEnabled`，默认 true。关闭时进入公开 API 降级，供系统兼容和故障恢复，不作为“完整效果”验收路径。

设置页删除“边缘折射”语言，改为“折射强度 0–6”；显示当前 runtime mode 和 SPI 风险说明。默认预览与 Island 使用同一个 AppKit host，禁止维护第二套预览材质实现。

### 3.6 降级策略

- macOS 26+ 且能力完整：四层完整路径。
- macOS 26+ 但 variant/lensing 缺失，或恢复开关关闭：公开 `NSGlassEffectView`，保留 tint、corner radius、backing 和内容层；状态显示“公开玻璃降级”。
- macOS 14–25：`NSVisualEffectView` 局部材质降级，不创建不存在的 class。
- Reduce Transparency：关闭折射与 Aurora，使用高对比度不透明/近不透明表面，保证内容可读。
- Reduce Motion：停止 Aurora，保留静态折射。

任何降级都不得记录为“完整液态玻璃折射通过”。

## 4. 重构提交序列

每个提交都必须可以构建，且不得使用 `git add .`。当前工作区已有未提交的 Island/Glass 改动，实施任务必须先记录路径级 diff，不得 reset、checkout 或覆盖无关用户改动。

### Commit 1 — 固化上游和风险契约

- 更新第三方声明，记录两个固定提交及 MIT 文本。
- 更新架构文档：私有 SPI 是 `IslandPresentation` 的显式实验例外，不改变音乐、日历、隐私和权限边界。
- 增加“完整 / 降级”术语，禁止 UI 和发布文案混淆两者。
- 只改文档与 notice；构建行为不变。

### Commit 2 — 引入纯配置和迁移模型

- 新增配置、capability、runtime mode 值类型。
- 把旧 0…160 折射值迁移到 0…6，默认 6，clamp 异常值。
- 保留旧 key 的兼容读取，写入新规范值。
- 增加纯值单元测试，业务 UI 暂不切换。

### Commit 3 — 封装 runtime SPI

- 新增单一 Objective-C runtime 适配器。
- 实现 selector 探测、variant→lensing 顺序、scrim/subdued normal、公开 tint 回退和 nil 清理。
- 实现 capability 结果与一次性诊断。
- 用可注入 fake runtime 验证外部行为：缺 selector 不崩溃、模式正确降级、配置顺序稳定。

### Commit 4 — 实现 AppKit 四层宿主

- 新增 `LiquidGlassSurfaceHost`，拥有 Aurora、backing、glass 和透明内容 host。
- 统一 frame、autoresizing、corner radius、continuous curve 和 clipping。
- 保证 update 原位更新，不因 SwiftUI state 变化重复泄漏 native view。
- 先用独立 Debug fixture 接入，不替换 Island。

### Commit 5 — 接入 IslandPanel active appearance

- 把五个 active appearance override 限定到 `IslandPanel`。
- 输出 capability 结果，不修改全局 `NSWindow`。
- 加入前后台/切换应用的窗口行为测试或可重复 GUI 脚本。
- Island 视觉尚未切换，避免一次提交同时改宿主和业务。

### Commit 6 — 将 Island 内容与材质分离

- 提取透明 `IslandContent`，保留现有音乐、会议、idle 和几何行为。
- 删除内容内部材质、伪边缘和重复 clip。
- 用快照/可访问性测试确认内容语义与控件行为不变。

### Commit 7 — 切换 Island 到完整宿主

- `IslandWindowController` 安装四层 host。
- 默认启用 variant 2、lensing 6、scrim 0、subdued 0。
- 绑定 tint、backing、motion、Reduce Motion/Transparency。
- 删除旧 `GlassMaterialSurface` / `GlassEdgeMaterial` 渲染路径；不保留双实现。

### Commit 8 — 统一设置页预览和状态

- 预览复用同一 host/configuration。
- 折射控件改为 0…6，提供 TokenClock 最大折射预设。
- 显示 capability/runtime mode、SPI 风险和 App Store 不兼容说明。
- 增加恢复开关，并验证设置持久化和旧值迁移。

### Commit 9 — 增加专用视觉验收 fixture

- Debug-only fixture 在 Island 后方绘制高对比条纹、棋盘和色块，可在不改变真实产品 UI 的情况下检测空间位移。
- 支持固定 Aurora、tint 0、backing 0、lensing 0/6 两组可重复状态。
- fixture 不进入 Release，不申请捕获权限，不持久化用户内容。

### Commit 10 — 删除遗留并完成验收

- 删除过时边缘折射参数、旧主窗口 Demo 和失效文案。
- 运行全量构建、测试、源码扫描、runtime probe 和 GUI/pixel 矩阵。
- 只在所有硬门槛通过后标记“完整折射验收通过”；否则保留明确失败项。

## 5. 测试与验收决策

### 5.1 自动化测试

- 配置映射：旧值迁移、0…6 clamp、默认 6、backing 五档和 tint clamp。
- capability 决策：完整、公开降级、旧系统降级、Reduce Transparency。
- SPI dispatch：缺失 selector 不调用；存在时 variant 必须先于 lensing；nil tint 清理。
- host 生命周期：重复 update 不增加子视图；resize 后四层 bounds 和 corner geometry 一致。
- Island 外部行为：仲裁、显示器选择、锁屏隐藏、播放/会议优先级和可访问性不回归。

测试只验证可观察行为。私有 selector 的真实存在与实际像素效果属于运行时验收，不用纯单元测试伪造通过。

### 5.2 构建硬门槛

- `scripts/build-app.sh Debug` 成功。
- arm64 和 x86_64 均编译，产物是 universal binary。
- 完整 `swift test --disable-sandbox` 通过；需要真实媒体授权的跳过项单独列出。
- `git diff --check` 通过。
- canonical bundle 路径必须是当前 checkout 的 `.build/XcodeDerivedData/Build/Products/Debug/LockTune Debug.app`。

### 5.3 runtime 硬门槛

在验收机 macOS 26 上记录：

- `NSGlassEffectView` 可创建。
- `set_variant:` = available。
- `set_contentLensing:` = available。
- variant 2 和 lensing 6 均成功 dispatch。
- tint 使用 underscored setter或公开属性的实际分支被记录。
- 五个 active appearance override 的安装结果被记录。
- 实际进程来自 canonical bundle，不是旧安装副本。

variant 或 contentLensing 任一缺失，即判定“完整折射失败”，即使 UI 看起来像玻璃。

### 5.4 像素硬门槛

使用 Debug fixture，固定窗口位置、尺寸、appearance、tint 0、backing 0、Aurora 静止，采集：

1. 无 glass 基准。
2. variant 2 / lensing 0。
3. variant 2 / lensing 6。
4. 应用失焦后的 lensing 6。

验收要求：

- 差异只发生在 Island surface 内；外部参考背景保持稳定。
- lensing 6 相对 lensing 0 能看到高对比线条的空间位移/弯曲，不只亮度或 blur 改变。
- 圆角边界无矩形漏光，四层无 frame 偏移。
- 失焦前后折射结构保持，不能降为 dimmed 材质。
- 由验收者并排确认与 TokenClock 固定提交的默认材质在“清透度、边缘折射、底板为 0 时的背景可见性”三个维度一致；不要求不同窗口形状逐像素相同。

保留四张原始截图、裁剪图和差异图。没有这些证据不能用设置页预览替代，也不能只凭 selector 日志宣布通过。

### 5.5 UI 矩阵

- idle / music / meeting 三种内容。
- notch-attached / floating-capsule 两种几何。
- 浅色 / 深色。
- backing 0 / 100。
- tint 0 / 0.30。
- Reduce Motion / Reduce Transparency。
- 主窗口打开/关闭、设置页打开/关闭、切换到其他应用。
- 多显示器重定位、Space 切换和全屏辅助行为。

每项检查内容清晰度、点击命中、圆角、shadow、z-order 和 panel 位置；不得因材质重构改变 `IslandCoordinator` 仲裁语义。

## 6. 发布、许可与回退

- 两个上游固定提交的 MIT notice 必须随 LockTune 分发保留。
- 私有 SPI 可能导致 App Store 审核失败或系统升级失效。采用此方案意味着 LockTune 的这一构建不再满足“生产行为只用公开 API”的旧架构原则；必须在架构文档中记录该例外。
- runtime 能力缺失时自动降级，设置页和诊断必须如实显示。
- 紧急回退只需关闭 `glass.privateRefractionEnabled`；音乐、日历、Island 内容和窗口生命周期不受影响。
- 若后续决定恢复 App Store 兼容，删除 SPI adapter 和 active appearance override，保留公开 glass/backing/Aurora 层即可。

## 7. 不在本次范围

- 不在主窗口日历区保留 Liquid Glass Demo。
- 不更改音乐播放、Google Calendar、OAuth、索引或持久化架构。
- 不移植 Electron/Node 或引入新的第三方二进制依赖。
- 不实现自定义 shader，也不把系统折射逆向成自有算法。
- 不改 Island 的业务仲裁、会议优先级或锁屏隐私规则。
- 不提交、清理或覆盖当前工作区中与本方案无关的用户改动。

## 8. 设计验收结论

本方案覆盖了上游来源、真实渲染层级、私有 SPI 入口、非激活窗口、参数迁移、旧系统和辅助功能降级、许可、逐提交迁移、自动化测试以及可区分“折射”和“普通透明/模糊”的像素验收。

实施任务只有同时满足构建、测试、runtime 和像素四组硬门槛，才可报告“完全实现”。任一门槛缺失时，应报告具体阻塞与当前降级模式，不得用截图观感或公开 API 回退代替验收。
