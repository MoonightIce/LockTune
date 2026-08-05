# TokenClock Liquid Glass 实现与许可审计（2026-08-04）

## 审计边界

- 对象：`Neo-Isshin/TokenClock` 当前 `main`。
- 固定提交：[`a56cc20bc83adfa587a86fe1c0012a0f4a8e8408`](https://github.com/Neo-Isshin/TokenClock/commit/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408)（于 2026-08-04 通过 `refs/heads/main` 核对）。
- 证据仅来自 TokenClock 固定提交的源码/历史和 Apple Developer Documentation。
- 本文是工程与许可风险审计，不是法律意见。

## 结论摘要

1. TokenClock 的高折射效果不是“直接使用一个公开 `NSGlassEffectView`”：它用完整圆形玻璃覆盖表盘，不是仅边缘 mask。`NSGlassEffectView` 类、`tintColor`、`style` 和 `cornerRadius` 现在是 Apple 公开 API，但 TokenClock 额外通过 Objective-C runtime 调用私有 selector `set_variant:` 和 `set_contentLensing:`，并替换 `NSWindow` 的多个下划线私有方法。这些私有 SPI 是其效果和风险的重要来源。
2. 它的主体分层确实是“底部动态主题柔光 → 公开 `NSVisualEffectView` 毛玻璃底板 → `NSGlassEffectView` 折射层 → 表盘内容”。官网图片的差异不只来自原生材质，还来自 `GlassAurora` 人造流动渐变、高光与主题配色。
3. “可调毛玻璃底板”为公开 API 实现：`.menu` 材质的 `NSVisualEffectView`，`.behindWindow`，用 `alphaValue` 调整 0/25/50/75/100% 五档。但 100% 表示“视图不再额外降低 alpha”，不等于材质在 API 语义上变成不透明实心色；README 的“实心底板”是产品化描述。
4. 不建议把 TokenClock 当作 Swift Package 依赖：它的 `Package.swift` 只定义可执行 target，没有可导入的 library product。复制源码在当前 MIT 许可文本下原则上可行，但不应直接复制私有 SPI 路径到 LockTune 的生产版。
5. 许可信息有明显文档漂移：当前根 [`LICENSE`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/LICENSE#L1-L20) 是 MIT，程序内 About 也是 MIT，且有明确的 [GPL-3.0 → MIT 重授权提交 `92f5eda`](https://github.com/Neo-Isshin/TokenClock/commit/92f5eda67bf45f08a1d1b1edf6fe0480990c91a4)；但当前中文 README 的 badge 和许可章节又写成 GPL v3。若要实际复制较多源码，应先向上游确认这是 README 回退错误，并在 LockTune 保留 MIT 版权与许可声明。

## README 声明与实现对照

README 在 [302–314 行](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/README.zh-CN.md#L302-L314) 声明：`main` 仅支持 macOS 26+，使用原生 Liquid Glass，有 glass tint，并在折射玻璃下放置五档毛玻璃底板。`Package.swift` 也确实将平台限制为 [`.macOS(.v26)`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Package.swift#L4-L16)。

| README 声明 | 源码事实 | 审计判断 |
|---|---|---|
| 原生 Liquid Glass | [`LiquidGlassDial`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/LiquidGlassDial.swift#L38-L73) 确实创建 `NSGlassEffectView` | 类本身是公开 API；它的定制参数却使用私有 SPI |
| 随壁纸折射 | `set_variant:` + `set_contentLensing:` 以 runtime dispatch 调用，并将 lensing 固定为 6 | 不是 Apple 公开契约，不能当作稳定能力 |
| 氛围着色 | 自定义颜色经 `glassTintHex` 传给 `NSGlassEffectView`；内建主题色主要由 [`GlassAurora`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/ClockContentView.swift#L191-L272) 的流动渐变提供 | README 把“原生 tint”与“主题柔光”合并成了一个产品概念 |
| 纯净玻璃 | 自定义 tint 为 `nil` 时不设 tint；另有公开 `.glassEffect(.clear.interactive())` 回退 | 公开 API 可实现稳定的 clear/regular 玻璃，但不应许诺与私有 lensing 完全相同 |
| 可调毛玻璃底板 | [`VibrancyBacking`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/VibrancyBacking.swift#L11-L34) 使用 `NSVisualEffectView` + `alphaValue` | 公开 API；五档菜单也确实按 0/25/50/75/100 写入 |

### 一个不宜原样复制的 tint 细节

[`applyTint`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/LiquidGlassDial.swift#L77-L103) 在 `tint == nil` 时直接返回，不会把已有 `tintColor` 清空；而“恢复默认”会将 `glassTintHex` 设为 `nil`。如果视图没有因其他 ID 变化而重建，旧 tint 可能残留。这是另一个“参考分层、不照搬代码”的理由。

## API 公开性

### 公开 API

- Apple 将 [`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) 定义为“将 content view 嵌入动态玻璃效果的视图”，并公开 `contentView`、`cornerRadius`、`style` 和 `tintColor`。
- [`NSGlassEffectView.tintColor`](https://developer.apple.com/documentation/appkit/nsglasseffectview/tintcolor) 是公开属性，用于将背景和玻璃效果着色。
- SwiftUI 的 [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) 是公开 Liquid Glass 入口；[`Glass`](https://developer.apple.com/documentation/swiftui/glass) 公开 `.regular`、`.clear`、`.tint(_:)` 和 `.interactive(_:)`。
- [`NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview) 是公开的透明/模糊/活力材质视图；Apple 明确说明 `.behindWindow` 会取窗口后方内容作为背景。

### TokenClock 使用的私有 SPI

- [`set_variant:` 与 `set_contentLensing:`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/LiquidGlassDial.swift#L18-L66)：不在 Apple 公开 `NSGlassEffectView` 属性列表中，通过 selector 字符串、`class_getMethodImplementation` 和 `unsafeBitCast` 调用。
- `set_tintColor:`：下划线版是私有 SPI；`setTintColor:` 则是公开 Swift/Objective-C `tintColor` 属性的 setter 形式。TokenClock 先探测前者，再回退后者。
- [`_hasActiveAppearance` 等五个 NSWindow 方法`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/FloatingPanel.swift#L90-L124)：通过 `class_replaceMethod` 强制无边框非激活面板一直报告 active。

因此，README [370 行](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/README.zh-CN.md#L366-L370) 把 `NSGlassEffectView` 整体称为“私有 API”已不够准确；当前准确说法应是：**类本身和基础着色属性公开，TokenClock 的 variant/lensing/窗口激活增强仍是私有 SPI。**

## 实际分层

[`ClockContentView`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/ClockContentView.swift#L12-L20) 先在底部放置 `GlassAurora`，再放表盘内容。[`DialGlassModifier`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/Views/ClockContentView.swift#L134-L187) 对表盘内容连续施加两层 background：

```text
最上：表盘文字 / 刻度 / 指针 / 交互区
       LiquidGlassDial — NSGlassEffectView + 私有 variant/lensing + tint
       VibrancyBacking — NSVisualEffectView(.menu, behindWindow) + alpha
最下：GlassAurora — 主题色流动渐变、高光、模糊
```

五档底板从菜单 [0/25/50/75/100](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/AppDelegate.swift#L267-L277) 映射为 `Double(tag) / 100.0`，通过 `@Published glassBackingAlpha` 持久化，再在 `updateNSView` 中原位更新 `alphaValue`。

还有一个例外：`glacier` 主题明确跳过原生 glass effect，改用 15% 半透明主题色、自定义描边和增强 `GlassAurora`。因此“所有表盘都是同一原生 Liquid Glass 材质”也不符合实际分支。

## 作为依赖或复制的可行性

| 方式 | 可行性 | 建议 |
|---|---|---|
| 直接加为 SwiftPM 依赖 | 不可直接使用；仓库没有 library product | 不采用 |
| 复制 `VibrancyBacking` 分层思路 | 技术上可行，只涉及公开 AppKit API | 优先按 Apple 文档独立实现；若复制源码，保留 MIT 声明 |
| 复制公开 `NSGlassEffectView` / SwiftUI `.glassEffect` 用法 | 可行，macOS 26+ | 适合 LockTune 生产路径，使用 `style`/`tintColor`/`cornerRadius` 等公开属性 |
| 复制 `set_variant:` / `set_contentLensing:` | 能编译不代表稳定或可分发 | 不进生产版；如仅研究，需独立实验开关、系统版本门禁和失效回退 |
| 复制 `_hasActiveAppearance` method replacement | 私有且入侵 `NSWindow` 行为 | 不采用；应用公开窗口生命周期/材质状态处理非激活面板 |

## MIT / GPL-3.0 影响

### 已核对的事实

- 当前固定提交的根 `LICENSE` 是 [MIT](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/LICENSE#L1-L20)。
- [`L10n.swift`](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/Sources/TokenClock/L10n.swift#L112-L120) 的 About 文案也是“许可证：MIT”。
- 历史提交 [`92f5eda67bf45f08a1d1b1edf6fe0480990c91a4`](https://github.com/Neo-Isshin/TokenClock/commit/92f5eda67bf45f08a1d1b1edf6fe0480990c91a4) 的提交信息为 `chore: relicense from GPL-3.0 to MIT`，同时把 `LICENSE`、README badge/许可章节和 About 文案改为 MIT。
- 当前 [`README.zh-CN.md` 的 badge](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/README.zh-CN.md#L13-L18) 与 [许可章节](https://github.com/Neo-Isshin/TokenClock/blob/a56cc20bc83adfa587a86fe1c0012a0f4a8e8408/README.zh-CN.md#L358-L363) 却又写成 GPL v3，与根许可文本和重授权提交冲突。

### 对 LockTune 的实际意义

- 若以当前 `a56cc20` 的 MIT 许可为准，MIT 与 LockTune 当前 MIT 路径兼容；复制或改作的实质源码需在分发中保留 TokenClock 的版权和 MIT 许可文本，不会因 MIT 自动要求 LockTune 整体开源。
- 若使用的是 TokenClock 早期只以 GPL-3.0 发布的特定快照，且没有后续 MIT 重授权覆盖，则复制并分发其派生代码可触发 GPL-3.0 的 copyleft 义务。
- 由于当前仓库同时存在 MIT 许可文本和 GPL README 声明，计划直接复制前最稳妥的闭环是：请上游修正 README 或书面确认 `a56cc20` 下的源码统一以 MIT 许可。

## 给 LockTune 的可执行边界

1. 可直接采用 Apple 公开 API 完成 macOS 26 路径：`NSGlassEffectView` 或 SwiftUI `.glassEffect(.clear/.regular.tint(...), in: shape)`。
2. 可采用 TokenClock 验证过的产品分层思路：主题着色和玻璃强度分离，并在 Liquid Glass 下层提供独立的公开 `NSVisualEffectView` 底板透明度档位。
3. 官网或设置页若宣传“原生 Liquid Glass”，应把公开系统材质、应用自己的流动柔光、以及可调毛玻璃底板分开描述，不要将私有 lensing 当作 Apple 公开能力。
4. 不将 `set_variant:`、`set_contentLensing:`、`_hasActiveAppearance` 等 runtime SPI 并入 LockTune 生产/发布构建。如产品决策要对比它们，只在明确标记的本地实验构建中运行。
5. 在得到上游许可一致性确认前，不复制 TokenClock 大段源码；当前可先基于 Apple 文档独立实现相同的公开 API 分层。
