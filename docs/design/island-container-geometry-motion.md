# LockTune 顶部容器几何与动效规范

状态：已确认，交付 `LockTune Debug` 实现  
首次确认：2026-08-05  
维护方式：本文件是顶部容器 UI 的唯一最终规范；后续设计经用户确认后直接更新本文，只保留当前有效方案。

## 1. 范围与关联文档

本文只定义：

- 有刘海与无刘海显示器的顶部容器几何；
- collapsed、hovered、expanded 三态尺寸；
- 顶部锚点、反向肩部、底部圆角和单路径裁剪；
- 展开、收拢、悬浮预览和辅助功能动效；
- 主窗口近期 UI 调整及最终视觉验收。

液态玻璃材质、SPI、四层 AppKit 宿主和降级策略继续以
[`docs/refactors/liquid-glass-refraction-refactor-2026-08-05.md`](../refactors/liquid-glass-refraction-refactor-2026-08-05.md)
为准。本文的几何 Path 必须同时作用于该文定义的 Aurora、backing、glass 和透明内容四层，不允许维护第二套裁剪轮廓。

交互效果稿：

- `/Users/admin/.codex/visualizations/2026/08/05/019fcfd3-6cb0-75c0-9db9-c489a06298e0/locktune-island-container-motion-study.html`

效果稿中的浏览器百分比只用于视觉观察；本文列出的 macOS point、屏幕几何公式和验收规则才是生产实现依据。

## 2. 术语和状态模型

`IslandPresentation` 继续表示内容类型：`idle`、`music`、`meeting`。容器展开状态必须是独立维度，不能再用内容类型隐式代替：

- `collapsed`：正式收拢态；刘海屏沿硬件刘海左右延伸等高图标翼，无刘海屏显示独立胶囊。
- `hovered`：仅从 collapsed 进入的轻量预览态。
- `expanded`：点击进入的完整内容态。

状态规则：

1. 顶部中心锚点始终不动，宽度向左右、高度向下生长。
2. collapsed 上悬浮进入 hovered；移出后回到 collapsed。
3. 点击 collapsed/hovered 进入 expanded；点击容器空白区域或按 Escape 收拢。
4. expanded 内部的播放、Meet、音量、输出设备和菜单控件不得触发收拢。
5. hover 只提供预览反馈，不能替代点击展开。
6. `IslandCoordinator` 仍是内容仲裁唯一权威；展开状态不得改变会议、音乐的优先级。

## 3. 两类显示器的共同尺寸

collapsed 高度由统一的 `collapsedReferenceHeight` 决定：

```text
notchAttached: collapsedReferenceHeight = 当前目标屏幕的 hardwareNotchHeight
floatingCapsule: 优先复用当前会话内建刘海屏的 hardwareNotchHeight；没有可用刘海几何时回退 32 pt
```

因此同一会话中两类显示器的收拢高度一致，并以真实硬件刘海高度为准。当前验收机器实测参考值为 32 pt，不再使用 42 pt 固定高度。

| 状态 | 主体高度 | 说明 |
| --- | ---: | --- |
| collapsed | `collapsedReferenceHeight`（典型 32 pt） | 与硬件刘海等高；无刘海屏使用同一参考值 |
| hovered | 47 pt | 两种显示器完全一致 |
| expanded | 132 pt | 两种显示器完全一致 |

高度只指可见容器主体，不包含无刘海屏顶部 gap、阴影或屏幕外路径部分。抗锯齿边缘允许验收截图出现 1 px 偏差。

## 4. 无刘海显示器：独立悬浮胶囊

### 4.1 顶部位置

顶部 gap 使用当前显示器菜单栏/状态栏可用高度的三分之一：

```text
topGap = clamp(menuBarHeight / 3, 6 pt, 10 pt)
```

典型值为 8 pt。collapsed、hovered、expanded 三态都保留相同 gap；hover 和展开不得向上跳到 `top = 0`。

### 4.2 轮廓与尺寸

无刘海容器是完整悬浮形状，四角均为连续凸圆角：

| 状态 | 目标宽度 | 圆角 |
| --- | ---: | ---: |
| collapsed | 196 pt | `collapsedReferenceHeight / 2`（典型 16 pt） |
| hovered | 208 pt | 23.5 pt（高度一半） |
| expanded | 内容优选 420 pt；不超过屏幕安全宽度减 32 pt | 32 pt |

hover 主要向左右和下方生长。顶部 gap、中心 X 和内容基准线不能漂移。

## 5. 有刘海显示器：屏幕外圆心的反向肩部

### 5.1 锚点和宽度

- 容器固定 `top = 0`，包裹真实硬件刘海。
- 硬件刘海宽度必须来自当前 `NSScreen` 的 `safeAreaInsets`、`auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea` 几何，不写死 180 pt。
- collapsed 不在刘海下方形成独立主体，而是在真实硬件刘海左右各延伸一个黑色图标翼；整个可见轮廓高度严格等于 `hardwareNotchHeight`。
- collapsed 每侧图标翼目标宽度为 40 pt，总宽为 `hardwareNotchWidth + 2 × 40 pt`；当前 185 pt 刘海的参考总宽为 265 pt。
- 两翼与硬件刘海使用同一纯黑视觉底色并连成一个剪影，不得出现色差、透明接缝或从刘海底部向下多出的玻璃面。
- 每翼展示一个基础图标，图形尺寸 16–18 pt；左侧表示当前内容/来源，右侧表示状态或展开入口。图标及其命中区域必须完全位于硬件刘海矩形之外，collapsed 不展示文字。
- hovered 主体宽度比 collapsed 增加 10 pt，肩部为 11 pt；总宽为 `hardwareNotchWidth + 10 pt + 2 × 11 pt`。
- expanded 内容优选宽度：music 420 pt、meeting 440 pt、idle 420 pt；最终宽度不超过屏幕安全宽度减 32 pt，且不得小于硬件刘海宽度加两侧肩部。
- expanded 是一整块连续的深色液态玻璃表面；硬件刘海左右不得出现独立的浅灰色玻璃面、灰色矩形垫层或通过 padding 暴露的 backing。左右区域只能是与主体完全相同的材质、色调、mask 和动画进度。

### 5.2 最终采用的顶部曲线

顶部左、右不是普通圆角矩形的 top corner。最终采用“反向肩部”：

- 圆弧圆心位于容器主体外侧；
- 路径顶部延伸到屏幕可视区域之外，由屏幕顶边裁切；
- 可见曲线从屏幕顶边进入，并在较短距离内平滑收回主体垂直侧壁；
- 收拢、hover、展开始终使用同一条拓扑一致的 Path。

参数：

| 状态 | 反向肩部半径 | 底部圆角 |
| --- | ---: | ---: |
| collapsed | 10 pt | 10 pt（不得超过高度一半） |
| hovered | 11 pt | 23 pt |
| expanded | 12 pt | 26 pt |

圆弧到主体垂直侧边的过渡保持短促、克制。

### 5.3 单路径约束

生产实现必须使用一个参数化 `Shape`/`CGPath` 生成整个外轮廓：

1. 路径在 `y < 0` 的屏幕外区域开始。
2. 经过右侧屏幕外圆心的反向肩部。
3. 进入右侧主体垂直边。
4. 经过右下、底边、左下圆角。
5. 进入左侧主体垂直边。
6. 经过左侧反向肩部并回到屏幕外。

以下对象必须共享完全相同的 path 和动画进度：

- Aurora；
- `NSVisualEffectView` backing；
- `NSGlassEffectView`；
- SwiftUI 内容裁剪；
- 边缘描边与高光；
- 阴影轮廓；
- `contentShape`/鼠标命中区域。

外轮廓、透明材质、抗锯齿、描边、阴影与动画必须由上述单一路径统一生成。

## 6. 窗口贴顶定位契约

### 6.1 单一屏幕几何来源

窗口控制器必须为当前目标屏幕生成一份不可分叉的 `IslandDisplayGeometry`（或等价值对象），至少包含：

- display ID；
- `screen.frame`；
- `screen.visibleFrame`；
- `safeAreaInsets`；
- `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`；
- 硬件刘海宽度和高度；
- `notchAttached` / `floatingCapsule` attachment。

窗口 frame、容器宽度、顶部 gap、Path、内容避让和安全宽度都使用同一份快照。SwiftUI 内容层不得再次通过 `NSScreen.main` 独立选择屏幕。

### 6.2 有刘海屏

- 目标窗口顶边固定为 `screen.frame.maxY`，不是 `screen.visibleFrame.maxY`。
- `IslandPanel` 必须允许进入菜单栏/安全区；在 notch-attached 模式覆盖或等价处理 `constrainFrameRect(_:to:)`，避免 AppKit 把窗口推到可见工作区下方。
- panel 使用顶部 HUD 所需的 floating/nonactivating 行为和高于菜单栏的窗口层级，同时保持非 key、非 main。
- 设置目标 frame 后必须读取实际 `panel.frame`，不能把“已调用 setFrame”当作定位成功。
- 如果 AppKit 调整了目标 frame，控制器应使用同一目标屏幕重新应用明确的 top-left/origin 定位，并记录最终误差；不得形成无限重试。

运行时硬门槛：

```text
abs(panel.frame.maxY - screen.frame.maxY) <= 0.5 pt
abs(surfaceGlobalFrame.maxY - screen.frame.maxY) <= 0.5 pt
panelDisplayID == targetDisplayID
```

任一条件失败，都属于“Island 位于刘海下方”，不能报告几何通过。

内容避让使用目标屏幕真实 `safeAreaInsets.top`/刘海高度；不得再用 `containerHeight × 0.42` 估算。内容避让只影响内部内容，不能向下移动玻璃表面或外轮廓。

collapsed 的特殊布局规则：玻璃/黑色表面的全局高度必须等于硬件刘海高度，表面底边为 `screen.frame.maxY - hardwareNotchHeight`；两侧图标翼占用刘海矩形外侧，中心区域由物理刘海遮挡。不得通过隐藏全部紧凑内容来规避刘海，必须渲染 wing-only compact layout。

### 6.3 无刘海屏

无刘海屏继续使用第 4 节的顶部 gap。窗口实际顶边要求：

```text
abs(panel.frame.maxY - (screen.visibleFrame.maxY - topGap)) <= 0.5 pt
```

### 6.4 窗口位置验收

- 测试原点屏、负坐标屏、竖向排列屏和用户指定屏。
- 纯值测试覆盖目标 panel frame 计算。
- AppKit 窗口测试覆盖 `constrainFrameRect` 后的实际 frame。
- Debug 诊断同时输出 requested frame、applied frame、surface global frame、display ID、window layer、alpha 和 on-screen 状态，不记录用户内容。
- 有刘海验收截图必须包含硬件刘海、屏幕顶边以及左右至少 60 px 环境背景；窗口自身裁剪图不能证明贴顶。
- collapsed、hovered、expanded 三态分别验证顶边误差；不能只验证 collapsed。

## 7. 动画规范

| 过程 | 目标时长 | 曲线/弹性 | 内容时序 |
| --- | ---: | --- | --- |
| collapsed → hovered | 0.22 s | 轻量 ease-out，等价于 `cubic-bezier(.2,.8,.2,1)` | 不展示完整内容 |
| collapsed/hovered → expanded | 0.38 s | 低回弹 spring，bounce 约 0.10–0.12；目标感觉等价于 `cubic-bezier(.16,1,.30,1)` | 轮廓先动，内容延迟 0.10 s 淡入 |
| expanded → collapsed | 0.28–0.30 s | 更克制的收束曲线，目标感觉等价于 `cubic-bezier(.40,0,.20,1)` | 内容先淡出，再收轮廓 |

实现要求：

- 宽度、高度、肩部半径、底部圆角、材质 mask 和阴影使用同一动画事务。
- 不允许在状态边界切换两套 Shape 或两棵视图树。
- hover 不能通过整体 `scaleEffect` 伪装；应插值真实几何，否则路径、内容命中和玻璃采样不同步。
- `Reduce Motion`：时长为 0，直接到最终几何；最终形状和普通模式一致。
- `Reduce Transparency`：使用不透明/近不透明降级，但仍沿用同一个几何 Path。

## 8. 主窗口近期 UI 方案

### 8.1 音乐库中栏

- “音乐库 / 你的声音收藏 / 播放全部”固定在工具栏下方顶部，不参与列表滚动。
- 空音乐库时，提示文案和“添加文件夹”操作在 header 以下的剩余区域水平、垂直居中。
- 有音乐时，List 填满 header 以下剩余空间并独立滚动。
- 本项不改变“播放全部”的既有视觉样式。

### 8.2 底部播放控制

- 播放/暂停移除黑色圆形底和白色前景。
- 播放态只显示三角形；播放中只显示双竖线。
- 随机、上一首、播放/暂停、下一首、循环采用一致的简洁纯图标语言、协调的视觉重量和约 34 pt 命中区域。
- 保留状态色、disabled、help、accessibility 和原有播放行为。

## 9. 实现边界

- `IslandPresentation` 仍是内容类型；新增或等价建模的 expansion state 只控制容器状态。
- `IslandCoordinator` 继续决定内容与目标几何，不接触 AppKit SPI。
- `IslandWindowController`/专用 Shape 负责把目标几何转换成单一路径和窗口 frame。
- `LiquidGlassSurfaceHost` 四层共享 path；不得在 SwiftUI 内容内绘制第二套材质背景。
- collapsed 的黑色左右翼属于同一 surface path 的组成部分；expanded 不得额外叠加左右浅灰 backing/view。
- 不改变会议优先级、播放仲裁、锁屏隐藏、隐私、权限或持久化边界。
- 不 push、不创建 PR、不更新 Linear，除非用户单独授权。

## 10. 验收清单

### 10.1 自动化

- 几何纯值测试覆盖两种 attachment × 三种 expansion state。
- 验证 notch-attached collapsed 高度等于目标屏幕 `hardwareNotchHeight`，floating collapsed 高度等于同一会话解析出的 `collapsedReferenceHeight`；hovered/expanded 分别为 47/132 pt。
- 验证无刘海 top gap 的 clamp。
- 验证有刘海 collapsed 总宽为 `hardwareNotchWidth + 80 pt`，左右翼各 40 pt，图标 bounds 完全落在硬件刘海外。
- 验证 path 的左右对称、中心 X 不漂移、bounds 内无 NaN/自交。
- 验证 Reduce Motion 返回零时长。
- 验证 requested/applied panel frame 在原点屏、负坐标屏和竖向排列屏均满足顶部锚点误差门槛。
- 验证窗口控制器和 SwiftUI 内容使用同一个 display ID/屏幕几何快照。

### 10.2 构建和测试

- `scripts/build-app.sh Debug`
- `swift test --disable-sandbox`
- 确认 canonical bundle 为 universal `arm64 + x86_64`。

### 10.3 GUI/像素

分别在有刘海和无刘海显示器采集 collapsed、hovered、expanded：

- 两类显示器的 collapsed 高度均等于本次会话的 `collapsedReferenceHeight`；刘海屏误差不超过 0.5 pt。
- 无刘海三态始终保留顶部 gap。
- 有刘海三态的 panel 与 surface 全局顶边都和 `screen.frame.maxY` 相差不超过 0.5 pt。
- 有刘海左右肩部圆心位于主体外侧，圆弧短且自然地进入垂直边。
- collapsed 左右各有 40 pt 黑色图标翼并与物理刘海连成单一剪影；刘海底边以下不得出现额外主体、玻璃或阴影（抗锯齿最多允许 1 px）。
- expanded 左右区域与主体使用同一深色液态玻璃材质；不得出现浅灰侧翼、独立灰色矩形、padding 漏底或材质分界。
- 肩部、主体、玻璃、描边和阴影没有拼接线、双重透明或矩形漏光。
- 展开/收拢逐帧无 shape 跳变，顶部中心不漂移。
- 内容控件点击不触发收拢。
- Reduce Motion 最终几何一致。
- 前后台切换后玻璃和轮廓仍保持。
- 有刘海截图必须包含屏幕顶边、真实硬件刘海和左右环境背景；不得使用窗口裁剪截图代替。

Liquid Glass 的空间折射仍必须按关联重构文档执行 lensing 0/6 像素差异硬门槛；几何通过不能替代折射通过。
