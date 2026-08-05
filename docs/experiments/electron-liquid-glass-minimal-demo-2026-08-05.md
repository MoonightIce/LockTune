# `electron-liquid-glass` 折射实现与 LockTune 主窗口最小 Demo 方案

日期：2026-08-05  
上游快照：[`Meridius-Labs/electron-liquid-glass@a50d96f`](https://github.com/Meridius-Labs/electron-liquid-glass/tree/a50d96f981d5adea40c368639fccbb0a9b06ef17)

## 结论

`electron-liquid-glass` **没有实现自定义液态玻璃 shader**。它的 Node-API addon 只负责把 macOS 系统 `NSGlassEffectView` 插入 Electron 原生视图层级；折射、反射、背景取色和采样都由 AppKit/WindowServer 的系统材质完成。仓库只链接 AppKit，没有 Metal、Core Image、WebGL 或 shader 源文件。[`binding.gyp`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/binding.gyp#L1-L25)

因此，LockTune 不应移植 Electron addon，也不能从该仓库得到折射 kernel、位移场、法线图、采样半径或色散公式。最小 Demo 应复用 LockTune 现有 `GlassMaterialSurface` 的系统版本分支，在**主窗口内部一块有明确边界的区域**验证 macOS 26 公共 Liquid Glass；不要改变整个窗口透明度，也不要引入私有 selector。

## 上游实际渲染管线

```text
Electron BrowserWindow
  → getNativeWindowHandle() Buffer
  → Node-API / C++ binding
  → Objective-C++ 解引用为 Electron 根 NSView
  → NSGlassEffectView（系统存在时）
      或 NSVisualEffectView（回退）
  → 插到容器最底层
  → 透明 WebContents 在其上显示网页内容
```

1. JavaScript 把 `BrowserWindow.getNativeWindowHandle()` 交给 native addon，只公开 `cornerRadius`、`tintColor`、`opaque` 三个稳定参数。[`js/index.ts`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/js/index.ts#L9-L20)、[`src/liquidglass.cc`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/liquidglass.cc#L37-L75)
2. Objective-C++ 将 handle 解引用为 `NSView *`，直接使用根容器的全部 `bounds`。API 没有局部 frame/region 参数，所以仓库实现本质是**整窗口根容器效果**。[`src/glass_effect.mm`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/glass_effect.mm#L64-L96)
3. 它用 `NSClassFromString(@"NSGlassEffectView")` 动态创建系统玻璃；类不存在时回退到 `NSVisualEffectView`，设置 `.behindWindow`、`.underWindowBackground` 和 `.active`。[`src/glass_effect.mm`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/glass_effect.mm#L90-L121)
4. 玻璃 view 被插到容器最下方，Electron WebContents 保持在上方。因此 README 要求 `transparent: true`，并要求不要同时开启 Electron vibrancy，否则两种背景材质会叠加成模糊效果。[`src/glass_effect.mm`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/glass_effect.mm#L123-L145)、[`README.md`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/README.md#L60-L89)
5. 圆角通过 backing layer 的 `cornerRadius + masksToBounds` 实现，tint 动态调用 `setTintColor:`；这里仍然没有应用自算背景纹理或 shader pass。[`src/glass_effect.mm`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/glass_effect.mm#L151-L181)

Apple 将 `NSGlassEffectView` 定义为把 content view 嵌入动态玻璃效果的视图，并公开 `contentView`、`cornerRadius`、`style` 和 `tintColor`。[Apple `NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) Apple 也说明 Liquid Glass 会反射、折射并从附近内容取色；其 sampling region 大于玻璃自身。多个相邻玻璃需要共享采样时，应使用 `NSGlassEffectContainerView`，减少重复采样 pass。[WWDC25: Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/?time=1050)、[Apple `NSGlassEffectContainerView`](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)

### 这不是 CSS `backdrop-filter`

WebKit 的 `backdrop-filter` 是“读取元素背后的内容 → 应用 CSS filter → 再合成”的网页管线，会增加渲染 pass；它不是本仓库采用的系统 Liquid Glass。[WebKit: Introducing Backdrop Filters](https://webkit.org/blog/3632/introducing-backdrop-filters/) Chromium 的公开接口也说明 renderer 背景只有设为真正透明后，底层 native view 才能显示。[Chromium `RenderWidgetHostView`](https://chromium.googlesource.com/chromium/src/+/210f24b4c8a63318597b9a5b67e5a471457e5aae/content/public/browser/render_widget_host_view.h#122)

## 私有 SPI 边界

仓库会根据字符串优先构造 `set_<key>:`，再尝试公共风格的 `setKey:`，然后用 `objc_msgSend` 调用。[`src/glass_effect.mm`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/glass_effect.mm#L184-L222)

实际暴露的实验入口是：

- `variant` → `set_variant:`
- `scrimState` → `set_scrimState:`
- `subduedState` → `set_subduedState:`

绑定见 [`src/liquidglass.cc`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/src/liquidglass.cc#L82-L128)，README 明确标记这些入口“不要用于生产”。[`README.md`](https://github.com/Meridius-Labs/electron-liquid-glass/blob/a50d96f981d5adea40c368639fccbb0a9b06ef17/README.md#L133-L146)

当前 Apple 已公开 `NSGlassEffectView` 及基础属性，所以仓库 README 把整个类称为 private/reverse-engineered 已是历史表述；私有的是上面这些 undocumented setter。该提交中也**没有** `contentLensing` 或 `set_contentLensing:`，不能把 LockTune 先前实验中出现过的 selector 归因于这个仓库。

## 可移植到 LockTune 的部分

| 上游做法 | LockTune 结论 |
| --- | --- |
| 使用系统 `NSGlassEffectView`，不自写 shader | 可采用，但直接使用 SwiftUI/AppKit 公共 API，不引入 Electron addon |
| tint、圆角与内容分层 | 可采用；优先用公共 `tintColor`、`cornerRadius`、`style` 或 SwiftUI `.glassEffect` |
| 旧系统 `NSVisualEffectView` 回退 | 可采用；主窗口局部区域应使用 `.withinWindow`，不是上游的整窗口 `.behindWindow` |
| 透明 WebContents 盖在 glass sibling 上 | 不移植；这是 Electron 宿主限制 |
| 整个 `BrowserWindow` 必须透明、禁用 vibrancy | 不适用于 LockTune 的主窗口局部区域 |
| variant/scrim/subdued 私有 setter | 不移植，不进入生产或最小 Demo |
| 全局 view ID registry | 不移植；上游没有 remove/update，README 仍将其列为 roadmap，重复 add 会留下 registry 引用 |

Apple 对原生 AppKit 的推荐结构也不同于 Electron workaround：将要显示的内容设置为 `NSGlassEffectView.contentView`，让系统完整处理可读性和 Auto Layout；不要把内容作为盖在 glass 上的 sibling。[WWDC25 AppKit session](https://developer.apple.com/videos/play/wwdc2025/310/?time=1050)

## 交给 LockTune Debug 的最小 Demo

### 目标

只在 `WindowGroup` 的主窗口内增加一张约 `320 × 180` 的验证卡片。卡片下方必须有高对比的颜色、文字/封面和可滚动内容，才能肉眼和像素检查确认采样变化。不要动 `IslandWindowController` 的独立 panel 生命周期，也不要把整个 `NSWindow` 改成 transparent。

建议落点：主窗口 `ContentView` 的 detail 区域或 Debug-only overlay；不放 Settings 窗口，不放顶部 Island panel。

```text
主窗口 detail 内容
└─ 彩色且可滚动的测试背景
   └─ LiquidGlassDemoRegion（约 320 × 180）
      └─ macOS 26: NSGlassEffectView / 现有 GlassMaterialSurface
         └─ Demo 内容（标题、状态、一个按钮）
      └─ macOS 14–25: NSVisualEffectView(.withinWindow)
```

### 最小实现范围

1. **优先复用现有 `GlassMaterialSurface`**：传入圆角矩形 `shape` 和 `backdropSource: .withinWindow`。它已经在 macOS 26 使用公共 `.glassEffect`，旧系统使用 `NSVisualEffectView(.withinWindow)`；Demo 不应另建第二套材质状态。
2. 如果为了严格验证 AppKit `contentView` 语义而新增 representable，只做一个局部 `NSGlassEffectView` 包装器：macOS 26 设置公共 `cornerRadius`、`tintColor`、`style`，并把 `NSHostingView<DemoControls>` 赋给 `contentView`。不要用 ZStack sibling 模拟 Electron 层级。
3. 第一版只有一个 glass view，不需要 `NSGlassEffectContainerView`；只有未来同一区域出现多个相邻玻璃并需要融合时再引入容器。
4. 不调用 `set_variant:`、`set_scrimState:`、`set_subduedState:` 或 `set_contentLensing:`；不添加 Metal、ScreenCaptureKit、Core Image、WebView 或屏幕录制权限。
5. 不新增持久化参数。Demo 使用常量或复用现有 `glassTint`、`glassBackingLevel`、`glassRefraction`、`glassMotionEnabled`，但文案必须说明：旧系统回退不是 macOS 26 的同等折射。

### 验收清单

- [ ] macOS 26 Debug build 编译通过；macOS 14 deployment target 仍可编译。
- [ ] 效果只出现在主窗口指定卡片，未覆盖整个窗口、Settings 或 Island panel。
- [ ] 滚动或移动卡片下方背景时，玻璃外观实时变化；留下屏幕录制或前后截图。
- [ ] 窗口缩放后卡片 frame、圆角、clip 和内容布局仍一致。
- [ ] 浅色/深色外观下标题与按钮可读。
- [ ] 开启 Reduce Transparency 后不崩溃，内容仍可读；将降级外观记录为系统行为。
- [ ] 运行时/源码检查确认没有上述私有 selector，也没有屏幕捕获权限。
- [ ] 对比 `GlassMaterialSurface` 现有 Settings 预览，证明新增验收对象确实位于**主窗口**。

## 风险与停止条件

- **视觉误判**：背景过于单色时，真实系统玻璃也可能像普通透明层。验收背景必须同时包含色彩、明暗边界和运动。
- **版本差异**：LockTune 最低版本是 macOS 14；macOS 26 才有公共 Liquid Glass。旧系统只承诺 `NSVisualEffectView` 回退，不承诺折射一致。
- **错误复刻 Electron 约束**：若实现要求把主窗口改为透明、增加 `.behindWindow` 或与现有材质叠加，应停止并回到局部 `.withinWindow` 方案。
- **私有 SPI**：若达成效果必须调用 undocumented selector，最小 Demo 视为未通过，不应混入生产路径。
- **验收不足**：编译通过不等于视觉通过；必须检查运行进程、主窗口层级、区域 frame/alpha、以及实际像素或录屏。

最终建议：**把这个上游当作“系统玻璃宿主适配”的证据，而不是折射算法参考。LockTune 的最小 Demo 只需把现有公共材质正确放进主窗口局部区域，并完成动态背景与像素验收。**
