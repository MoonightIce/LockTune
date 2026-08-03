# macOS 透明玻璃浮层对照调研

日期：2026-08-03

## 结论

目前没有找到公开证据证明某个第三方 Mac 软件完整公开了与 Droppy 相同的“底层窗口实时采样 + 自定义折射”实现。多数产品只公开产品行为、视觉名称或系统材质使用；因此需要把“看起来像玻璃”和“实时系统材质”分开判断。

## 产品对照

| 产品 | 相似点 | 实时玻璃实现证据 | 可借鉴内容 |
|---|---|---|---|
| Boring Notch | 顶部刘海岛、音乐、日历、文件架、HUD、多屏相关能力 | 官方仓库和发布说明没有公开具体材质实现 | 最接近 LockTune 的顶部 Surface、状态机和功能组合 |
| DynamicLake | Dynamic Island、DynaDrop、Normal/Semi-Liquid Glass/Liquid Glass 模式 | “Liquid Glass”是产品功能名称，未公开渲染代码或屏幕采样证据 | 状态层级、玻璃强度档位和顶部交互 |
| NotchNook | 刘海入口、媒体、日历、文件暂存、摄像头相关能力 | 未公开实现 | 功能密度和刘海区域的内容编排 |
| MediaMate | 音量、亮度、Now Playing HUD，可放置在刘海附近 | 未公开实时采样或自定义折射实现 | HUD 尺寸、出现/消失动画、系统状态优先级 |
| BetterTouchTool | 可固定顶部/桌面浮层、置顶、绑定屏幕或窗口；支持模糊和 Tahoe Glass Effect | 官方文档确认相关视觉选项，但未证明其采样底层窗口像素 | 浮层生命周期、定位、hover 展开、自动隐藏和配置模型 |
| Alfred | 非激活启动器面板、主题透明度和窗口模糊 | 官方资料确认使用原生 macOS Visual Effect view，但未证明自定义折射 | AppKit 兼容材质和窗口行为 |
| Ice | 菜单栏下方独立栏、多显示器、圆角/颜色/阴影/边框 | 开源，但没有公开证据表明其做屏幕采样 | 多屏浮层管理和布局实现 |
| Textream | 开源的顶部 Dynamic Island 风格浮层 | 未公开玻璃材质实现 | 简化的顶部窗口和内容状态模型 |

## Apple 原生实现边界

Apple 提供的 `NSVisualEffectView` 是 macOS 上最稳妥的实时系统材质路径。其 `behindWindow` 混合模式允许视觉效果使用窗口后方内容，由系统负责模糊、半透明和 Vibrancy；这不是应用自行读取屏幕截图。[NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)

SwiftUI 的 Liquid Glass 是另一套系统材质 API，可对后方内容、颜色和光线产生动态反应；它不能简单等同于旧版 AppKit 的 Visual Effect，也不能仅凭“Liquid Glass”这个产品名称推断第三方软件采用了相同实现。[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)

如果应用要自行获得屏幕或窗口帧，再进行颜色反射、折射或 Shader 合成，需要 ScreenCaptureKit，并涉及屏幕录制权限、性能和隐私边界。[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)、[Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

## 对 LockTune 的建议

LockTune 应优先采用：

```text
透明 NSPanel / NSWindow
  → NSVisualEffectView(.behindWindow 或 .underWindowBackground)
  → SwiftUI 内容层
```

这条路径能让材质由 macOS 实时合成，不需要自己计算底层窗口颜色，也不需要 Screen Recording 权限。Boring Notch、DynamicLake 和 NotchNook 适合作为交互与布局参照；BetterTouchTool、Alfred 和 Ice 更适合作为浮层生命周期、多屏管理和 AppKit 材质兼容参照。

目前不建议为了追求“更强折射”直接引入屏幕采样。除非原生系统材质无法满足目标效果，否则 ScreenCaptureKit 会增加授权、遮挡、帧率、窗口切换和隐私处理成本。

## 来源

- [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
- [Boring Notch Releases](https://github.com/TheBoredTeam/boring.notch/releases)
- [DynamicLake Liquid Glass](https://www.dynamiclake.com/liquidglass)
- [NotchNook](https://notchmac.com/)
- [MediaMate](https://wouter01.github.io/MediaMate/)
- [BetterTouchTool Floating Menus](https://docs.folivora.ai/docs/floating-menus/overview/)
- [Alfred Appearance](https://www.alfredapp.com/help/appearance/)
- [Ice](https://github.com/jordanbaird/Ice)
- [Textream](https://github.com/f/textream)
- [Apple NSWindowLevel](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)

## GitHub 源码补充

这轮专门检查了 GitHub 上可读源码，新增几个更适合 LockTune 对照的项目：

| 项目 | 源码中已确认的内容 | 边界 |
|---|---|---|
| [ShatteredGlass](https://github.com/AlexStrNik/ShatteredGlass) | 研究 macOS 26 Liquid Glass 的 `CABackdropLayer`、SDF shape、`glassBackground`、折射、边缘高光和色彩矩阵；README 明确展示了多层 `CALayer` 结构 | 属于逆向/实验项目，部分效果仍在调参，不应直接作为生产依赖；不要复制私有 API 方案 |
| [NSWindowStyles](https://github.com/lukakerr/NSWindowStyles) | 明确展示 `NSVisualEffectView`、`.behindWindow`、透明窗口、无标题栏、圆角和透明浮层 | 重点是 AppKit 系统材质示例，不是 Droppy 顶部工作台 |
| [DynamicNotch](https://github.com/jackson-storm/DynamicNotch) | 开源的顶部 Notch/Dynamic Island 应用；SwiftUI + AppKit、非刘海显示器胶囊、物理弹簧动画、屏幕选择和 HUD | README 没有公开它具体使用哪种玻璃材质；其 Screen Recording 说明主要对应音频响应可视化，不等于玻璃背景采样 |
| [DynamicOverlay](https://github.com/gaetanzanella/DynamicOverlay) | SwiftUI 的磁性 Notch overlay、尺寸状态、拖动、滚动联动和动画 | 主要是 overlay 行为库，且不是 macOS 玻璃材质实现 |
| [Boring Notch](https://github.com/TheBoredTeam/boring.notch) | 开源顶部音乐/日历/文件架/HUD；README 还明确列出构建和依赖项目 | 公开仓库仍没有足够证据证明其使用实时玻璃或自定义折射 |

其中最值得直接阅读的是：

1. `NSWindowStyles`：验证 LockTune 当前 AppKit `NSVisualEffectView(.behindWindow)` 路线是否符合公开 macOS 做法。
2. `DynamicNotch`：对照顶部窗口、状态模型、物理动画和无刘海胶囊。
3. `ShatteredGlass`：只用于理解 macOS 26 Liquid Glass 的实验性图层/折射机制，不建议直接采用其私有类型。

## `lucasromerodb/liquid-glass-effect-macos` 实现分析

这个项目的名称容易造成误解：它不是 macOS 原生应用，而是一个 HTML/CSS/SVG 网页 Demo。README 明确写的是使用纯 CSS 和 SVG filters 重建 macOS Liquid Glass 视觉效果，仓库文件也只有 `index.html`、`styles.css` 和图片资源。[README](https://github.com/lucasromerodb/liquid-glass-effect-macos/blob/main/README.md)

其结构是四层叠加：

```text
.liquidGlass-wrapper
  ├─ .liquidGlass-effect   // backdrop-filter + SVG distortion
  ├─ .liquidGlass-tint     // 白色半透明染色层
  ├─ .liquidGlass-shine    // 内侧高光/边缘线
  └─ .liquidGlass-text     // 内容层
```

### 1. 背景实时模糊

`.liquidGlass-effect` 使用 `backdrop-filter: blur(3px)`。这会实时模糊元素后方的网页内容，但前提是浏览器仍在合成同一个网页上下文；它不是 macOS App 读取其他窗口内容。[styles.css](https://github.com/lucasromerodb/liquid-glass-effect-macos/blob/main/styles.css)

### 2. SVG 位移模拟折射

CSS 通过 `filter: url(#glass-distortion)` 绑定 SVG 滤镜。滤镜链为：

```text
feTurbulence(fractalNoise)
  → feComponentTransfer(调整通道)
  → feGaussianBlur(生成位移图)
  → feSpecularLighting(生成白色高光)
  → feDisplacementMap(扭曲 SourceGraphic)
```

其中 `feDisplacementMap scale="150"` 负责把背景/内容产生局部位移；`feSpecularLighting` 和 `liquidGlass-shine` 负责模拟边缘高光。[SVG filter 源码](https://github.com/lucasromerodb/liquid-glass-effect-macos/blob/main/index.html)

### 3. 半透明染色层

项目额外叠加了 `background: rgba(255, 255, 255, 0.25)`。所以它不是“完全透明玻璃”，而是：

```text
网页实时 backdrop blur
+ SVG 位移折射
+ 25% 白色染色层
+ 内阴影/高光
```

这也解释了它为什么看起来比 LockTune 当前系统材质更“白”、边缘更明显：视觉效果有一层固定白色 tint 和两条固定高光线。

### 与 LockTune 的关键差异

| 维度 | 该 GitHub 项目 | LockTune 顶部浮层 |
|---|---|---|
| 运行环境 | 浏览器 HTML/CSS/SVG | macOS NSPanel/AppKit/SwiftUI |
| 背景来源 | 同一网页中的 DOM/背景图 | 其他 macOS 窗口或桌面合成内容 |
| 模糊 | `backdrop-filter` | `NSVisualEffectView` 系统材质 |
| 折射 | SVG `feDisplacementMap` | 系统材质或 Liquid Glass；自定义折射需要额外图层/Shader |
| 颜色 | 固定 `rgba(255,255,255,0.25)` | 应交给系统材质实时决定，不应计算背景颜色 |
| 边缘 | 固定内阴影和白色高光 | 应避免固定边框，交由系统光学材质处理 |

因此，这个项目可以借鉴“材质分层”和“折射滤镜”的视觉思路，但不能直接移植到 LockTune。它不能解决独立 macOS 窗口跨应用实时采样的问题；LockTune 当前应继续优先使用系统的 `NSVisualEffectView(.behindWindow)`，而不是把网页 SVG 滤镜搬进 AppKit。

## `BarredEwe/LiquidGlass` 实现分析

这个仓库比前一个项目更接近真实的实时玻璃渲染，但它仍然不是 macOS 实现，而是一个面向 iOS 的 Swift/SwiftUI/UIKit + Metal 库。README 明确要求 iOS 14+，源码使用 `UIKit`、`UIScreen`、`UIView` 和 `MTKView`。[仓库 README](https://github.com/BarredEwe/LiquidGlass)

### 实际渲染链路

```text
UIView 层级
  → HierarchySnapshotCapturer
  → CGImage
  → MTLTexture
  → Metal / MPS 模糊
  → LiquidGlassShader.metal
  → SwiftUI/UIKit 玻璃视图
```

1. `HierarchySnapshotCapturer` 找到目标玻璃 View 所在的最上层 UIKit 父视图。
2. 临时隐藏玻璃 View 自身，使用 `targetView.layer.render(in:)` 将同一套 UIKit View hierarchy 绘制成 `CGImage`。
3. `BackgroundTextureProvider` 将图像转换为 `MTLTexture`，并缓存源纹理和模糊纹理。
4. `MetalShaderView` 使用 Metal fragment shader 对纹理做背景采样、模糊、折射、色调和可选色差/光晕处理。
5. 通过 `.continuous(interval:)`、`.once` 或 `.manual` 控制背景更新频率；默认约 20 FPS，也支持约 60 FPS 的更高频刷新。[BackgroundTextureProvider.swift](https://github.com/BarredEwe/LiquidGlass/blob/main/Sources/LiquidGlass/Shared/BackgroundTextureProvider.swift)、[HierarchySnapshotCapturer.swift](https://github.com/BarredEwe/LiquidGlass/blob/main/Sources/LiquidGlass/Shared/HierarchySnapshotCapturer.swift)

### 它确实有“实时折射”，但范围有限

它的实时性来自“周期性重新捕获 View hierarchy”，不是 macOS 系统自动合成。README 也明确写出限制：只能捕获同一个 View hierarchy，不能捕获其他窗口。[仓库 README](https://github.com/BarredEwe/LiquidGlass)

因此它可以做到：

- 同一个 iOS 页面中，背景渐变或内容变化时玻璃同步更新。
- Metal Shader 对背景纹理做局部 UV 扭曲，形成折射效果。
- 通过缩小捕获尺寸、缓存纹理、只在变化时刷新降低 GPU 开销。

但它做不到：

- 捕获另一个 macOS App 窗口。
- 捕获屏幕顶部状态栏下方的真实桌面内容。
- 在没有 Screen Recording 权限的情况下读取跨进程窗口内容。

### 对 LockTune 的结论

这个项目比 `liquid-glass-effect-macos` 更值得参考“折射实现”，但不能作为 LockTune 的直接 Swift Package 依赖：

- 平台不匹配：UIKit/iOS，不是 AppKit/macOS。
- 捕获范围不匹配：只能抓同一个 View hierarchy，无法抓顶部浮层后面的其他窗口。
- 如果把 LockTune 的主窗口内容复制进同一层级，可以移植它的 Metal 管线；但这仍然不能实现 Droppy 那种跨窗口实时背景。
- 如果要抓取外部 macOS 窗口，需要另行使用 ScreenCaptureKit，再把帧送入 Metal；这会引入屏幕录制权限、性能、窗口遮挡和隐私问题。

所以它的定位是：**适合参考“自定义 Metal 折射管线”，不适合直接解决 LockTune 的跨窗口实时玻璃问题。**

## `haider-nawaz/liquid-glass-skill` 参考价值

这个仓库是给 Claude Code 使用的 SwiftUI Liquid Glass 开发 Skill，不是玻璃渲染库。它整理了 macOS 26+ / iOS 26+ 的 `glassEffect`、`GlassEffectContainer`、`glassEffectID`、`glassEffectUnion`、`backgroundExtensionEffect` 和玻璃按钮等 API，以及迁移流程和常见问题。[项目 README](https://github.com/haider-nawaz/liquid-glass-skill)

对 LockTune 有参考价值的部分：

- 如何组织单一连续玻璃表面和多个玻璃元素的合并。
- 如何使用 `GlassEffectContainer` 处理形变和共享采样区域。
- SwiftUI 与 macOS 平台差异、可用性判断和旧系统回退。
- Liquid Glass 的内容层、导航层和玻璃层分层原则。

不能解决的部分：

- 不提供独立 `NSPanel` 的窗口级实时背景实现。
- 不提供跨 macOS App 的窗口采样、ScreenCaptureKit 或 Metal 折射管线。
- 不能证明 `.glassEffect()` 会自动让顶部浮层采样其他应用窗口。

当前 LockTune 的 `Package.swift` 和 Xcode 工程最低版本仍为 macOS 14，因此该 Skill 面向的 macOS 26 API 只能作为条件分支参考，不能直接替换现有材质实现。更合理的架构是：macOS 26+ 尝试原生 SwiftUI Liquid Glass，macOS 14–25 保留 `NSVisualEffectView` 回退；两者共享相同的 Surface 几何、状态和动画模型。

## `Neo-Isshin/TokenClock` 参考价值

TokenClock 是目前与 LockTune 目标最接近的公开 macOS 项目之一：它把“顶部常驻浮层、系统玻璃、壁纸感知和 token 状态”组合成一个原生 macOS 应用，而不是网页 Demo 或只处理同一 View hierarchy 的 iOS 渲染库。[TokenClock README](https://github.com/Neo-Isshin/TokenClock)

### 公开 README 已确认的实现边界

- `main` 分支面向 macOS 26+，使用原生 Liquid Glass；`normal` 分支面向 macOS 12–15 的兼容材质。
- 技术栈为 Swift 6、SwiftUI + AppKit，并明确提到双 `NSPanel` 架构、置顶窗口、壁纸感知折射、环境色调和自适应对比度。
- README 明确声明 macOS 26+ 的折射效果依赖逆向得到的私有 API `NSGlassEffectView`，并致谢 `electron-liquid-glass`。
- 项目许可证是 GPL-3.0；它适合做行为和边界研究，不能在未完成许可证兼容审查前复制源码或直接移植实现。

这组信息非常关键：它说明 TokenClock 所展示的效果不是简单的 `NSVisualEffectView` 灰色半透明背景，也不是应用自行计算桌面颜色；在 macOS 26+ 路径上，核心效果来自系统内部的玻璃效果视图。与此同时，它也说明该方案依赖私有 API，不能视为 LockTune 的通用、稳定或 App Store 可接受实现。

### 与 LockTune 的对照

| 维度 | TokenClock | LockTune 当前边界 | 可借鉴结论 |
|---|---|---|---|
| 系统版本 | `main` 为 macOS 26+，另有旧系统分支 | 当前最低 macOS 14 | 必须保留系统版本分支；不能把 `NSGlassEffectView` 当作 macOS 14 方案 |
| 窗口宿主 | SwiftUI + AppKit、双 `NSPanel` | 顶部 Surface 已有 AppKit/SwiftUI 宿主 | 可参考面板拆分、置顶和生命周期；具体 panel 角色需继续读源码确认 |
| 玻璃材质 | 私有 `NSGlassEffectView`，具备壁纸感知/折射声明 | 当前公共 AppKit 材质回退 | 公共 API 与私有实现应明确分层，不能把视觉近似称为同一效果 |
| 背景来源 | 系统/玻璃视图处理 | 目标是实时显示其他窗口后方内容 | 优先验证系统材质；不要先走 ScreenCaptureKit + 自算颜色 |
| 发布边界 | README 公开展示私有 API 路线 | LockTune 需要 GitHub/MAS 等不同分发边界 | 私有 API 只能放在明确隔离的实验/GitHub 构建，不能默认进入 MAS 目标 |
| 代码许可 | GPL-3.0 | LockTune 自有代码与发布许可 | 只借鉴公开行为、架构和测试目标；不复制 TokenClock 源码 |

### 对 LockTune 的实际建议

1. 保留 LockTune 现有 macOS 14–25 公共回退：透明 `NSPanel` + `NSVisualEffectView(.behindWindow/.underWindowBackground)`，由系统实时合成后方内容。
2. 如果需要验证 macOS 26 的原生效果，单独增加可用性分支和实验构建，优先使用 Apple 公共 Liquid Glass API；只有在明确接受私有 API、分发和系统升级风险时，才把 TokenClock 的 `NSGlassEffectView` 路线作为实验对照。
3. 借鉴 TokenClock 的产品结构：把紧凑顶部状态和可交互展开面板拆成独立 Surface 生命周期，并让玻璃层、内容层和状态模型分离。
4. 继续保持“材质由系统控制、应用不计算背景颜色”的原则。TokenClock 的公开行为支持这一方向，但它的私有 API 不能直接证明公共 `NSVisualEffectView` 在所有系统版本上会产生相同的折射效果。

因此，TokenClock 可以提升 LockTune 的参考基线，但不会改变当前实现结论：**macOS 14 兼容版本应继续走公共系统材质；macOS 26 的真实折射效果可以建立独立实验分支验证；TokenClock 的 GPL 源码和私有 API 不直接并入 LockTune。**

## 与 TokenClock 接近的其他项目

按“底层材质实现接近度”排序，而不是按界面外观排序：

### 1. `Meridius-Labs/electron-liquid-glass`：最接近

这是与 TokenClock 技术路径最接近的项目。它直接在 Electron 原生窗口中插入 `NSGlassEffectView`，不使用 CSS 模拟；支持圆角、tint、玻璃变体，并在旧系统回退到 `NSVisualEffectView`。TokenClock README 也明确致谢它。[electron-liquid-glass](https://github.com/Meridius-Labs/electron-liquid-glass)

区别是它是 Electron/Objective-C++ Node addon，主要解决“如何把原生玻璃挂到 Electron 窗口”，不是顶部灵动岛的窗口状态、动画和多显示器协调器。它的 README 也明确把 variant、scrim、subdued 等扩展方法标为实验性、不可用于生产。

### 2. `fsalinas26/qt-liquid-glass`：底层材质接近，应用框架不同

它通过 Objective-C runtime 在 Qt 窗口中创建 `NSGlassEffectView`，并在旧系统回退 `NSVisualEffectView`；还整理了多种材料、透明窗口和无边框窗口配置。[qt-liquid-glass](https://github.com/fsalinas26/qt-liquid-glass)

它比 `NSWindowStyles` 更接近 TokenClock 的真实玻璃效果，但基于 Qt/C++，不能直接作为 LockTune 的 Swift Package 依赖。可以参考它的系统版本探测、透明窗口准备和材质配置边界。

### 3. `AlexStrNik/ShatteredGlass`：折射内部机制最接近，但属于实验性逆向

它不是完整产品，而是对 macOS 26 Liquid Glass 图层的拆解：`CABackdropLayer`、SDF 图层、`glassBackground`、折射、模糊和边缘高光都在同一条 Core Animation 管线里。[ShatteredGlass](https://github.com/AlexStrNik/ShatteredGlass)

如果关心“为什么 TokenClock 的边缘没有普通灰色边框、为什么背景能产生实时折射”，它是很有价值的底层参考；但仓库只有一个提交，README 仍标注基础效果为 partial、filter tuning ongoing，不适合作为 LockTune 生产依赖。

### 4. Wails `liquid-glass` 示例：集成方式接近，效果控制较少

Wails 的官方示例在 macOS 26+ 使用 `NSGlassEffectView`，旧系统回退 `NSVisualEffectView`，并通过运行时检测保持兼容。[Wails Liquid Glass 示例](https://github.com/wailsapp/wails/tree/master/v3/examples/liquid-glass)

它适合作为“公共 API/旧系统回退/跨框架封装”的参考，不像 TokenClock 那样关注独立桌面浮层的玻璃表现，也没有公开 TokenClock 那种主题、折射和双 Panel 组合。

### 5. `NSWindowStyles`：旧系统公共材质最接近，但没有折射

它明确使用公开的 `NSVisualEffectView(.behindWindow)`，可以验证透明窗口、背景实时混合、无标题栏和圆角配置。[NSWindowStyles](https://github.com/lukakerr/NSWindowStyles)

它是 LockTune macOS 14–25 回退实现最适合的参考，但视觉上不会达到 TokenClock macOS 26 Liquid Glass 的折射效果。

### 6. `DynamicNotch`：顶部交互最接近，但玻璃实现未公开

它在产品结构上很接近 LockTune：SwiftUI + AppKit、实体刘海/无刘海胶囊、媒体和系统 HUD、多显示器、物理动画。[DynamicNotch](https://github.com/jackson-storm/DynamicNotch)

但 README 没有证明它采用 TokenClock 同级的 `NSGlassEffectView` 或折射管线。因此它适合参考 Surface 状态、动画和权限，不适合作为玻璃材质实现依据。

### 不接近的项目

- `lucasromerodb/liquid-glass-effect-macos`：HTML/CSS/SVG，只能在网页上下文内做 backdrop blur 和位移滤镜。
- `BarredEwe/LiquidGlass`：iOS 同一 View hierarchy 截图 + Metal，不能捕获其他 macOS 窗口。
- `haider-nawaz/liquid-glass-skill`：API 使用指南，不是渲染实现。

最终排序：

```text
electron-liquid-glass  ≈ TokenClock 的玻璃底层
qt-liquid-glass        ≈ TokenClock 的玻璃底层
ShatteredGlass         ≈ TokenClock 的折射内部研究
Wails 示例             ≈ TokenClock 的系统集成方式
NSWindowStyles         ≈ LockTune 的旧系统公共回退
DynamicNotch           ≈ TokenClock 的顶部 Surface 交互
```

对于 LockTune，最合理的组合不是寻找一个完整替代品，而是：`TokenClock` 参考产品效果，`electron-liquid-glass`/`qt-liquid-glass` 参考 `NSGlassEffectView` 集成，`ShatteredGlass` 参考折射图层，`DynamicNotch` 参考顶部状态与动画，`NSWindowStyles` 作为 macOS 14–25 回退基线。
