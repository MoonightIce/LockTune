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

enum LiquidGlassDebugFixture {
    #if DEBUG
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--locktune-glass-fixture")
    }

    static var noGlass: Bool {
        enabled && ProcessInfo.processInfo.arguments.contains("--locktune-glass-no-glass")
    }

    static var lensingOverride: Double? {
        guard enabled else { return nil }
        let prefix = "--locktune-glass-lensing="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Double(argument.dropFirst(prefix.count)).map { min(max($0.rounded(), 0), 6) }
    }
    #else
    static let enabled = false
    static let noGlass = false
    static let lensingOverride: Double? = nil
    #endif
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
        capabilities.underscoredTintSelectorAvailable = setObjectSPI(
            view,
            selectorName: "set_tintColor:",
            value: tint
        )
        if !capabilities.underscoredTintSelectorAvailable {
            // Public tint is the supported fallback. Assigning nil here is
            // also the required cleanup path when a tint is removed later.
            view.tintColor = tint
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
    static func clearTint(on view: NSGlassEffectView) {
        if !setObjectSPI(view, selectorName: "set_tintColor:", value: nil) {
            view.tintColor = nil
        }
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
    var animates = true {
        didSet {
            if animates { startAnimationIfNeeded() } else { stopAnimation() }
            needsDisplay = true
        }
    }

    var fixtureEnabled = false {
        didSet { needsDisplay = true }
    }

    private var phase: CGFloat = 0
    private var timer: Timer?

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if animates { startAnimationIfNeeded() }
    }

    override func removeFromSuperview() {
        stopAnimation()
        super.removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        context.saveGState()
        defer { context.restoreGState() }

        if fixtureEnabled {
            drawFixture(in: context, bounds: bounds)
            return
        }

        let background = NSColor(calibratedWhite: 0.08, alpha: 0.18).cgColor
        context.setFillColor(background)
        context.fill(bounds)

        drawRadial(in: context, bounds: bounds, center: CGPoint(x: bounds.width * 0.18, y: bounds.height * 0.68), radius: bounds.width * 0.72, color: NSColor.systemBlue.withAlphaComponent(0.34).cgColor)
        drawRadial(in: context, bounds: bounds, center: CGPoint(x: bounds.width * 0.78, y: bounds.height * 0.24), radius: bounds.width * 0.68, color: NSColor.systemPurple.withAlphaComponent(0.28).cgColor)

        let waveHeight = bounds.height * 0.18
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: -20, y: bounds.height * 0.45))
        for x in stride(from: -20.0, through: bounds.width + 20, by: 4) {
            let y = bounds.height * 0.45 + sin((x / max(bounds.width, 1)) * 5 + phase) * waveHeight
            wave.addLine(to: CGPoint(x: x, y: y))
        }
        wave.addLine(to: CGPoint(x: bounds.width + 20, y: -20))
        wave.addLine(to: CGPoint(x: -20, y: -20))
        wave.closeSubpath()
        context.addPath(wave)
        context.setFillColor(NSColor.systemTeal.withAlphaComponent(0.2).cgColor)
        context.fillPath()
    }

    private func drawRadial(in context: CGContext, bounds: CGRect, center: CGPoint, radius: CGFloat, color: CGColor) {
        let colors = [color, color.copy(alpha: 0) ?? color] as CFArray
        let locations: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private func drawFixture(in context: CGContext, bounds: CGRect) {
        let stripeWidth = max(bounds.width / 11, 1)
        for index in 0..<12 {
            let rect = CGRect(x: CGFloat(index) * stripeWidth, y: 0, width: stripeWidth, height: bounds.height)
            let color: NSColor = index.isMultiple(of: 2) ? .systemOrange : .systemBlue
            context.setFillColor(color.withAlphaComponent(0.75).cgColor)
            context.fill(rect)
        }
        let checkerSize = max(min(bounds.width, bounds.height) / 5, 1)
        for row in 0..<5 {
            for column in 0..<12 {
                if (row + column).isMultiple(of: 2) {
                    context.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
                    context.fill(CGRect(x: CGFloat(column) * checkerSize, y: CGFloat(row) * checkerSize, width: checkerSize, height: checkerSize))
                }
            }
        }
    }

    private func startAnimationIfNeeded() {
        guard timer == nil, window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.animates else { return }
                self.phase += 0.06
                self.needsDisplay = true
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
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
    private var fixtureNoGlass: Bool

    init(
        configuration: LiquidGlassConfiguration,
        backdropSource: LiquidGlassBackdropSource = .behindWindow,
        cornerRadius: CGFloat = 30,
        fixtureNoGlass: Bool = false,
        contentView: NSView? = nil
    ) {
        self.configuration = configuration
        self.backdropSource = backdropSource
        self.cornerRadius = cornerRadius
        self.fixtureNoGlass = fixtureNoGlass
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(auroraView)
        addSubview(backingView)
        if let contentView { setHostedContentView(contentView) }
        update(configuration: configuration)
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
        fixtureNoGlass: Bool? = nil
    ) {
        self.configuration = configuration
        if let cornerRadius { self.cornerRadius = cornerRadius }
        if let fixtureNoGlass { self.fixtureNoGlass = fixtureNoGlass }
        layer?.cornerRadius = max(0, self.cornerRadius)
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        auroraView.animates = configuration.dynamicAurora && !configuration.reduceMotion && !configuration.reduceTransparency
        backingView.material = .menu
        backingView.blendingMode = backdropSource == .behindWindow ? .behindWindow : .withinWindow
        backingView.state = .active
        backingView.isEmphasized = false
        backingView.alphaValue = configuration.reduceTransparency ? 1 : configuration.backingAlpha
        backingView.wantsLayer = true
        backingView.layer?.cornerRadius = layer?.cornerRadius ?? 0
        backingView.layer?.cornerCurve = .continuous
        backingView.layer?.masksToBounds = true

        if configuration.reduceTransparency {
            replaceGlassView(nil)
            backingView.material = .contentBackground
            backingView.alphaValue = 1
            backingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            runtimeMode = .opaqueAccessibilityFallback
            capabilities = LiquidGlassCapabilities(runtimeMode: runtimeMode)
        } else if fixtureNoGlass == true {
            replaceGlassView(nil)
            runtimeMode = .publicGlassFallback
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
        for view in [auroraView, backingView, glassView, hostedContentView].compactMap({ $0 }) {
            view.wantsLayer = true
            view.layer?.cornerRadius = layer?.cornerRadius ?? 0
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
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
        glassView.layer?.cornerRadius = layer?.cornerRadius ?? 0
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        if #available(macOS 26.0, *), let native = glassView as? NSGlassEffectView {
            native.cornerRadius = layer?.cornerRadius ?? 0
            capabilities = LiquidGlassRuntimeAdapter.configure(native, configuration: configuration)
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
    var backdropSource: LiquidGlassBackdropSource = .behindWindow
    var reduceMotion = false
    var reduceTransparency = false
    var fixtureEnabled = false
    let content: () -> Content

    private var configuration: LiquidGlassConfiguration {
        let fixture = fixtureEnabled || LiquidGlassDebugFixture.enabled
        return LiquidGlassConfiguration(
            tint: fixture ? 0 : session.glassTint,
            backingLevel: fixture ? .clear : session.glassBackingLevel,
            lensing: fixture ? (LiquidGlassDebugFixture.lensingOverride ?? session.glassRefraction) : session.glassRefraction,
            dynamicAurora: fixture ? false : session.glassMotionEnabled,
            reduceMotion: reduceMotion,
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
            fixtureNoGlass: fixtureEnabled || LiquidGlassDebugFixture.noGlass,
            contentView: contentView
        )
        host.auroraView.fixtureEnabled = fixtureEnabled || LiquidGlassDebugFixture.enabled
        session.setLiquidGlassRuntimeMode(host.runtimeMode)
        return host
    }

    func updateNSView(_ host: LiquidGlassSurfaceHost, context: Context) {
        host.update(
            configuration: configuration,
            cornerRadius: cornerRadius,
            fixtureNoGlass: fixtureEnabled || LiquidGlassDebugFixture.noGlass
        )
        host.auroraView.fixtureEnabled = fixtureEnabled || LiquidGlassDebugFixture.enabled
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
