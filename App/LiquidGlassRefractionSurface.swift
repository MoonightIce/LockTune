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
    let attachment: IslandAttachment
    let topRadius: CGFloat
    let bottomRadius: CGFloat

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

        // A notched Island continues above the physical screen edge. The
        // short cubic shoulders therefore enter the visible top edge from
        // outside the local bounds instead of forming a second, inset shape.
        let shoulderDepth = max(1, top * 0.7)
        let shoulderEndY = min(height - bottom, max(top * 0.78, 1))
        let kappa = 0.5522847498
        var path = Path()
        path.move(to: CGPoint(x: top, y: -shoulderDepth))
        path.addLine(to: CGPoint(x: width - top, y: -shoulderDepth))
        path.addCurve(
            to: CGPoint(x: width, y: shoulderEndY),
            control1: CGPoint(x: width - top * 0.24, y: -shoulderDepth),
            control2: CGPoint(x: width, y: shoulderEndY * 0.14)
        )
        path.addLine(to: CGPoint(x: width, y: height - bottom))
        path.addCurve(
            to: CGPoint(x: width - bottom, y: height),
            control1: CGPoint(x: width, y: height - bottom + bottom * kappa),
            control2: CGPoint(x: width - bottom + bottom * kappa, y: height)
        )
        path.addLine(to: CGPoint(x: bottom, y: height))
        path.addCurve(
            to: CGPoint(x: 0, y: height - bottom),
            control1: CGPoint(x: bottom - bottom * kappa, y: height),
            control2: CGPoint(x: 0, y: height - bottom + bottom * kappa)
        )
        path.addLine(to: CGPoint(x: 0, y: shoulderEndY))
        path.addCurve(
            to: CGPoint(x: top, y: -shoulderDepth),
            control1: CGPoint(x: 0, y: shoulderEndY * 0.14),
            control2: CGPoint(x: top * 0.24, y: -shoulderDepth)
        )
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

    init(
        configuration: LiquidGlassConfiguration,
        backdropSource: LiquidGlassBackdropSource = .behindWindow,
        cornerRadius: CGFloat = 30,
        surfacePath: LiquidGlassSurfacePath? = nil,
        activeAppearanceOverrideAvailable: Bool = false,
        contentView: NSView? = nil
    ) {
        self.configuration = configuration
        self.backdropSource = backdropSource
        self.cornerRadius = cornerRadius
        self.surfacePath = surfacePath
        self.activeAppearanceOverrideAvailable = activeAppearanceOverrideAvailable
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
        self.configuration = configuration
        if let cornerRadius { self.cornerRadius = cornerRadius }
        self.surfacePath = surfacePath
        if let activeAppearanceOverrideAvailable {
            self.activeAppearanceOverrideAvailable = activeAppearanceOverrideAvailable
        }
        applySurfaceGeometry()

        backingView.material = .menu
        backingView.blendingMode = backdropSource == .behindWindow ? .behindWindow : .withinWindow
        backingView.state = .active
        backingView.isEmphasized = false
        backingView.alphaValue = configuration.reduceTransparency ? 1 : configuration.backingAlpha
        backingView.wantsLayer = true
        applyChildGeometry(to: backingView)

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
    let content: () -> Content

    private var configuration: LiquidGlassConfiguration {
        return LiquidGlassConfiguration(
            tint: session.glassTint,
            backingLevel: session.glassBackingLevel,
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
            contentView: contentView
        )
        session.setLiquidGlassRuntimeMode(host.runtimeMode)
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
            contentView.rootView = content()
        }
        session.setLiquidGlassRuntimeMode(host.runtimeMode)
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
