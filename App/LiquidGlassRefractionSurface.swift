import AppKit
import LockTuneDomain
import ObjectiveC
import SwiftUI

// This file is the only IslandPresentation boundary that knows about the
// undocumented NSGlassEffectView setters. The view-under-content arrangement
// follows the MIT-licensed electron-liquid-glass and TokenClock experiments;
// see THIRD_PARTY_NOTICES.md for the fixed upstream revisions.

enum LiquidGlassBackdropSource: Equatable {
    case behindWindow
    case withinWindow
}

struct LiquidGlassCapabilities: Equatable, Sendable {
    var systemSupportsGlass = false
    var variantSelectorAvailable = false
    var contentLensingSelectorAvailable = false
    var scrimSelectorAvailable = false
    var subduedSelectorAvailable = false
    var underscoredTintSelectorAvailable = false
    var activeAppearanceOverrideAvailable = false
    var runtimeMode: LiquidGlassRuntimeMode = .notEvaluated

    var hasCompleteRefraction: Bool {
        systemSupportsGlass && variantSelectorAvailable && contentLensingSelectorAvailable
    }
}

struct LiquidGlassActiveAppearanceCapabilities: Equatable, Sendable {
    let selectorsPresent: [String: Bool]
    let selectorsInstalled: [String: Bool]

    var allSelectorsPresent: Bool { selectorsPresent.values.allSatisfy { $0 } }
    var allSelectorsInstalled: Bool { selectorsInstalled.values.allSatisfy { $0 } }
}

@MainActor
enum LiquidGlassRuntimeAdapter {
    private static var didReportCapabilities = false

    @available(macOS 26.0, *)
    static func configure(
        _ view: NSGlassEffectView,
        configuration: LiquidGlassConfiguration
    ) -> LiquidGlassCapabilities {
        var capabilities = LiquidGlassCapabilities(systemSupportsGlass: true)

        // TokenClock applies variant first because it reconstructs internal
        // layers; contentLensing must target that reconstructed material.
        if configuration.privateRefractionEnabled {
            capabilities.variantSelectorAvailable = setIntegerSPI(
                view,
                selectorName: "set_variant:",
                value: configuration.variant
            )
            capabilities.contentLensingSelectorAvailable = setIntegerSPI(
                view,
                selectorName: "set_contentLensing:",
                value: configuration.lensing
            )
            capabilities.scrimSelectorAvailable = setIntegerSPI(
                view,
                selectorName: "set_scrimState:",
                value: configuration.scrim
            )
            capabilities.subduedSelectorAvailable = setIntegerSPI(
                view,
                selectorName: "set_subduedState:",
                value: configuration.subdued
            )
        }

        let tint = tintColor(for: configuration.tintOpacity)
        capabilities.underscoredTintSelectorAvailable = configuration.tintOpacity > 0
            ? setObjectSPI(view, selectorName: "set_tintColor:", value: tint)
            : clearTint(on: view)
        if !capabilities.underscoredTintSelectorAvailable {
            // Public tint is the supported fallback. Assigning nil here is
            // also the required cleanup path when a tint is removed later.
            view.tintColor = configuration.tintOpacity > 0 ? tint : nil
        }

        capabilities.runtimeMode = configuration.privateRefractionEnabled
            && capabilities.variantSelectorAvailable
            && capabilities.contentLensingSelectorAvailable
            ? .completePrivateRefraction
            : .publicGlassFallback

        report(capabilities)
        return capabilities
    }

    @available(macOS 26.0, *)
    static func clearTint(on view: NSGlassEffectView) -> Bool {
        let cleared = setObjectSPI(view, selectorName: "set_tintColor:", value: nil)
        if !cleared {
            view.tintColor = nil
        }
        return cleared
    }

    @available(macOS 26.0, *)
    private static func tintColor(for opacity: Double) -> NSColor {
        let color = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .controlAccentColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        let cappedAlpha = (luminance > 0.9 || luminance < 0.1)
            ? min(CGFloat(opacity), 0.5)
            : CGFloat(opacity)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: cappedAlpha)
    }

    @available(macOS 26.0, *)
    private static func setIntegerSPI(
        _ object: AnyObject,
        selectorName: String,
        value: Int
    ) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: object), selector)
        else { return false }

        typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(implementation, to: Setter.self)(object, selector, value)
        return true
    }

    @available(macOS 26.0, *)
    private static func setObjectSPI(
        _ object: AnyObject,
        selectorName: String,
        value: AnyObject?
    ) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: object), selector)
        else { return false }

        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(implementation, to: Setter.self)(object, selector, value)
        return true
    }

    private static func report(_ capabilities: LiquidGlassCapabilities) {
        guard !didReportCapabilities else { return }
        didReportCapabilities = true
        NSLog(
            "LOCKTUNE_GLASS_SPI glass=%@ variant=%@ lensing=%@ scrim=%@ subdued=%@ tint=%@ mode=%@",
            capabilities.systemSupportsGlass ? "YES" : "NO",
            capabilities.variantSelectorAvailable ? "YES" : "NO",
            capabilities.contentLensingSelectorAvailable ? "YES" : "NO",
            capabilities.scrimSelectorAvailable ? "YES" : "NO",
            capabilities.subduedSelectorAvailable ? "YES" : "NO",
            capabilities.underscoredTintSelectorAvailable ? "UNDERSCORED" : "PUBLIC",
            capabilities.runtimeMode.rawValue
        )
    }
}

@MainActor
final class LiquidGlassAuroraView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Keep the Aurora layer in the native host, but leave it fully clear.
        // All color and backdrop sampling comes from the system glass path.
    }
}

/// The single contour used by the Island's SwiftUI surface and every native
/// material layer. SwiftUI owns the canonical (y-down) path; AppKit receives
/// the vertically flipped equivalent for its layer mask.
struct LiquidGlassSurfacePath: Equatable {
    /// Droppy's shoulder drops about 1.3x further than it insets, which reads as
    /// a longer, calmer bend than a symmetric quarter-round would.
    static let shoulderDropRatio: CGFloat = 1.3
    /// Control-point ratio that makes a cubic approximate a quarter-arc.
    static let arcKappa: CGFloat = 0.5522847498

    let attachment: IslandAttachment
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// How far each side of the body pulls in from the full-width top edge.
    /// Interpolating this across the morph is what keeps the silhouette from
    /// jumping: at zero the body runs full width, and the shoulder grows in.
    var shoulderInset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let width = max(0, rect.width)
        let height = max(0, rect.height)
        guard width > 0, height > 0 else { return Path() }
        let top = min(max(0, topRadius), min(width / 2, height))
        let bottom = min(max(0, bottomRadius), min(width / 2, height / 2))

        guard attachment == .notchAttached else {
            return UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: top,
                    bottomLeading: bottom,
                    bottomTrailing: bottom,
                    topTrailing: top
                ),
                style: .continuous
            )
            .path(in: rect)
        }

        return notchPath(width: width, height: height)
    }

    /// A notch-attached top edge always spans the full width flush with the
    /// physical screen edge, so the silhouette meets the hardware without a
    /// seam and square top corners are deliberate. `shoulderInset` pulls the
    /// body in from that edge; the quadratic control points sit on the corners,
    /// matching Droppy's shoulder construction.
    private func notchPath(width: CGFloat, height: CGFloat) -> Path {
        let inset = min(max(0, shoulderInset), width / 2)
        let bodyWidth = width - inset * 2
        let corner = min(max(0, bottomRadius), min(bodyWidth / 2, height / 2))
        let drop = min(inset * Self.shoulderDropRatio, max(0, height - corner))
        let bodyBottom = max(drop, height - corner)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        if inset > 0 {
            // A cubic approximation of an elliptical quarter-arc. A quadratic
            // with its control point on the corner converges horizontally far
            // too early — the edge reads as vertical about halfway down — so
            // the bend would never carry to `drop` the way Droppy's does.
            path.addCurve(
                to: CGPoint(x: inset, y: drop),
                control1: CGPoint(x: inset * Self.arcKappa, y: 0),
                control2: CGPoint(x: inset, y: drop * (1 - Self.arcKappa))
            )
        }
        path.addLine(to: CGPoint(x: inset, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: inset + corner, y: height),
            control: CGPoint(x: inset, y: height)
        )
        path.addLine(to: CGPoint(x: width - inset - corner, y: height))
        path.addQuadCurve(
            to: CGPoint(x: width - inset, y: bodyBottom),
            control: CGPoint(x: width - inset, y: height)
        )
        path.addLine(to: CGPoint(x: width - inset, y: drop))
        if inset > 0 {
            path.addCurve(
                to: CGPoint(x: width, y: 0),
                control1: CGPoint(x: width - inset, y: drop * (1 - Self.arcKappa)),
                control2: CGPoint(x: width - inset * Self.arcKappa, y: 0)
            )
        }
        path.closeSubpath()
        return path
    }

    func appKitPath(in bounds: CGRect) -> CGPath {
        let canonical = path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        return canonical.copy(using: &transform) ?? canonical
    }
}

@MainActor
final class LiquidGlassSurfaceHost: NSView {
    private(set) var auroraView = LiquidGlassAuroraView(frame: .zero)
    private(set) var backingView = NSVisualEffectView(frame: .zero)
    private(set) var glassView: NSView?
    private(set) var hostedContentView: NSView?
    private(set) var capabilities = LiquidGlassCapabilities()
    private(set) var runtimeMode: LiquidGlassRuntimeMode = .notEvaluated

    private var configuration: LiquidGlassConfiguration
    private let backdropSource: LiquidGlassBackdropSource
    private var cornerRadius: CGFloat
    private var surfacePath: LiquidGlassSurfacePath?
    private var activeAppearanceOverrideAvailable: Bool
    private var hasAppliedConfiguration = false
    var contentRevision: String?

    init(
        configuration: LiquidGlassConfiguration,
        backdropSource: LiquidGlassBackdropSource = .behindWindow,
        cornerRadius: CGFloat = 30,
        surfacePath: LiquidGlassSurfacePath? = nil,
        activeAppearanceOverrideAvailable: Bool = false,
        contentRevision: String? = nil,
        contentView: NSView? = nil
    ) {
        self.configuration = configuration
        self.backdropSource = backdropSource
        self.cornerRadius = cornerRadius
        self.surfacePath = surfacePath
        self.activeAppearanceOverrideAvailable = activeAppearanceOverrideAvailable
        self.contentRevision = contentRevision
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(auroraView)
        addSubview(backingView)
        if let contentView { setHostedContentView(contentView) }
        update(configuration: configuration, surfacePath: surfacePath)
    }

    required init?(coder: NSCoder) { nil }

    func setHostedContentView(_ view: NSView?) {
        hostedContentView?.removeFromSuperview()
        hostedContentView = view
        if let view { addSubview(view) }
        needsLayout = true
    }

    func update(
        configuration: LiquidGlassConfiguration,
        cornerRadius: CGFloat? = nil,
        surfacePath: LiquidGlassSurfacePath? = nil,
        activeAppearanceOverrideAvailable: Bool? = nil
    ) {
        let nextActiveAppearanceOverrideAvailable = activeAppearanceOverrideAvailable
            ?? self.activeAppearanceOverrideAvailable
        let appearanceChanged = !hasAppliedConfiguration
            || self.configuration != configuration
            || self.activeAppearanceOverrideAvailable != nextActiveAppearanceOverrideAvailable
            || (configuration.reduceTransparency ? glassView != nil : glassView == nil)

        self.configuration = configuration
        if let cornerRadius { self.cornerRadius = cornerRadius }
        self.surfacePath = surfacePath
        self.activeAppearanceOverrideAvailable = nextActiveAppearanceOverrideAvailable
        applySurfaceGeometry()

        applyChildGeometry(to: backingView)

        // Geometry changes every animation frame, but material setup and the
        // private selector dispatch do not. Repeating those AppKit operations
        // during a 0.38s morph made clicks feel delayed, especially when the
        // native glass view was rebuilding its internal layers.
        if appearanceChanged {
            backingView.material = .menu
            backingView.blendingMode = backdropSource == .behindWindow ? .behindWindow : .withinWindow
            backingView.state = .active
            backingView.isEmphasized = false
            backingView.alphaValue = configuration.reduceTransparency ? 1 : configuration.backingAlpha
            backingView.wantsLayer = true

            if configuration.reduceTransparency {
                replaceGlassView(nil)
                backingView.material = .contentBackground
                backingView.alphaValue = 1
                backingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                runtimeMode = .opaqueAccessibilityFallback
                capabilities = LiquidGlassCapabilities(runtimeMode: runtimeMode)
            } else {
                backingView.layer?.backgroundColor = nil
                ensureGlassView()
                configureGlassView()
            }
            hasAppliedConfiguration = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        auroraView.frame = bounds
        backingView.frame = bounds
        glassView?.frame = bounds
        hostedContentView?.frame = bounds
        applySurfaceGeometry()
        for view in [auroraView, backingView, glassView, hostedContentView].compactMap({ $0 }) {
            view.wantsLayer = true
            applyChildGeometry(to: view)
        }
    }

    private func applySurfaceGeometry() {
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        guard let surfacePath else {
            layer?.mask = nil
            layer?.cornerRadius = max(0, cornerRadius)
            return
        }

        layer?.cornerRadius = 0
        let mask = (layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = bounds
        mask.path = surfacePath.appKitPath(in: bounds)
        layer?.mask = mask
    }

    private func applyChildGeometry(to view: NSView) {
        guard let viewLayer = view.layer else { return }
        viewLayer.cornerCurve = .continuous
        if surfacePath != nil {
            viewLayer.mask = nil
            viewLayer.cornerRadius = 0
            viewLayer.masksToBounds = false
        } else {
            viewLayer.cornerRadius = layer?.cornerRadius ?? 0
            viewLayer.masksToBounds = true
        }
    }

    private func ensureGlassView() {
        if #available(macOS 26.0, *) {
            if glassView == nil { replaceGlassView(NSGlassEffectView(frame: .zero)) }
        } else {
            replaceGlassView(nil)
            runtimeMode = .legacyVisualEffectFallback
            capabilities = LiquidGlassCapabilities(runtimeMode: runtimeMode)
        }
    }

    private func configureGlassView() {
        guard let glassView else { return }
        glassView.wantsLayer = true
        applyChildGeometry(to: glassView)
        if #available(macOS 26.0, *), let native = glassView as? NSGlassEffectView {
            native.cornerRadius = layer?.cornerRadius ?? 0
            capabilities = LiquidGlassRuntimeAdapter.configure(native, configuration: configuration)
            capabilities.activeAppearanceOverrideAvailable = activeAppearanceOverrideAvailable
            if capabilities.runtimeMode == .completePrivateRefraction,
               !activeAppearanceOverrideAvailable {
                capabilities.runtimeMode = .publicGlassFallback
            }
            runtimeMode = capabilities.runtimeMode
        }
    }

    private func replaceGlassView(_ view: NSView?) {
        glassView?.removeFromSuperview()
        glassView = view
        if let view {
            addSubview(view, positioned: .above, relativeTo: backingView)
        }
    }
}

struct LiquidGlassSurfaceContainer<Content: View>: NSViewRepresentable {
    @Bindable var session: AppSession
    let cornerRadius: CGFloat
    var surfacePath: LiquidGlassSurfacePath? = nil
    var backdropSource: LiquidGlassBackdropSource = .behindWindow
    var reduceTransparency = false
    var activeAppearanceOverrideAvailable = false
    /// Replaces the session's frosted backing level for surfaces that draw
    /// their own shade and need the untouched glass underneath it.
    var backingLevelOverride: GlassBackingLevel? = nil
    var contentRevision: String? = nil
    let content: () -> Content

    private var configuration: LiquidGlassConfiguration {
        return LiquidGlassConfiguration(
            tint: session.glassTint,
            backingLevel: backingLevelOverride ?? session.glassBackingLevel,
            lensing: session.glassRefraction,
            reduceTransparency: reduceTransparency,
            privateRefractionEnabled: session.privateRefractionEnabled
        )
    }

    func makeNSView(context: Context) -> LiquidGlassSurfaceHost {
        let contentView = NSHostingView(rootView: content())
        let host = LiquidGlassSurfaceHost(
            configuration: configuration,
            backdropSource: backdropSource,
            cornerRadius: cornerRadius,
            surfacePath: surfacePath,
            activeAppearanceOverrideAvailable: activeAppearanceOverrideAvailable,
            contentRevision: contentRevision,
            contentView: contentView
        )
        publishRuntimeMode(host.runtimeMode)
        return host
    }

    func updateNSView(_ host: LiquidGlassSurfaceHost, context: Context) {
        host.update(
            configuration: configuration,
            cornerRadius: cornerRadius,
            surfacePath: surfacePath,
            activeAppearanceOverrideAvailable: activeAppearanceOverrideAvailable
        )
        if let contentView = host.hostedContentView as? NSHostingView<Content> {
            // Animatable surface geometry updates this representable every
            // frame. Rebuilding the entire hosted SwiftUI tree on those same
            // frames was the remaining source of visible click hitching.
            // Callers with a revision get an update only when their content
            // state changes; legacy surfaces without one retain live updates.
            if contentRevision == nil || host.contentRevision != contentRevision {
                contentView.rootView = content()
            }
        }
        host.contentRevision = contentRevision
        publishRuntimeMode(host.runtimeMode)
    }

    private func publishRuntimeMode(_ mode: LiquidGlassRuntimeMode) {
        guard session.liquidGlassRuntimeMode != mode else { return }
        let session = session
        Task { @MainActor in
            session.setLiquidGlassRuntimeMode(mode)
        }
    }
}

enum LiquidGlassActiveAppearanceOverride {
    nonisolated(unsafe) private static var appliedClasses: Set<ObjectIdentifier> = []

    static let selectorNames = [
        "_hasActiveAppearance",
        "_hasActiveAppearanceIgnoringKeyFocus",
        "_hasActiveControls",
        "_hasKeyAppearance",
        "_hasMainAppearance",
    ]

    @MainActor
    static func apply(to windowClass: AnyClass) -> LiquidGlassActiveAppearanceCapabilities {
        guard #available(macOS 26.0, *) else {
            return LiquidGlassActiveAppearanceCapabilities(
                selectorsPresent: [:],
                selectorsInstalled: [:]
            )
        }

        let identifier = ObjectIdentifier(windowClass)
        var present: [String: Bool] = [:]
        var installed: [String: Bool] = [:]
        let alwaysTrue: @convention(c) (AnyObject, Selector) -> Bool = { _, _ in true }
        let implementation = unsafeBitCast(alwaysTrue, to: IMP.self)

        for name in selectorNames {
            let selector = NSSelectorFromString(name)
            let inheritedMethod = class_getInstanceMethod(NSWindow.self, selector)
            present[name] = inheritedMethod != nil
            let typeEncoding = inheritedMethod.flatMap(method_getTypeEncoding).map(String.init(cString:)) ?? "B@:"
            if !appliedClasses.contains(identifier) {
                class_replaceMethod(windowClass, selector, implementation, typeEncoding)
            }
            installed[name] = class_getInstanceMethod(windowClass, selector) != nil
        }
        appliedClasses.insert(identifier)
        let result = LiquidGlassActiveAppearanceCapabilities(selectorsPresent: present, selectorsInstalled: installed)
        NSLog(
            "LOCKTUNE_GLASS_ACTIVE class=%@ present=%@ installed=%@",
            NSStringFromClass(windowClass),
            result.allSelectorsPresent ? "YES" : "NO",
            result.allSelectorsInstalled ? "YES" : "NO"
        )
        return result
    }
}
