import Foundation

public enum IslandPresentation: Equatable, Sendable {
    case idle
    case music
    case meeting
}

public enum IslandAttachment: String, Codable, Equatable, Sendable {
    case notchAttached
    case floatingCapsule
}

/// The container state is intentionally independent from IslandPresentation,
/// which only selects the content category (idle, music, or meeting).
public enum IslandExpansionState: String, Equatable, Sendable {
    case collapsed
    case hovered
    case expanded
}

public struct IslandEdgeInsets: Equatable, Sendable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Platform-neutral rectangle used in display snapshots. Keeping AppKit's
/// `CGRect` at the application boundary makes this value safe to pass through
/// the core/domain modules and keeps placement tests deterministic.
public struct IslandRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// Immutable display geometry shared by the AppKit panel and SwiftUI content.
/// The display ID is part of the value so a screen change cannot silently
/// reuse a stale safe-area or notch measurement.
public struct IslandDisplayGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let frame: IslandRect
    public let visibleFrame: IslandRect
    public let safeAreaInsets: IslandEdgeInsets
    public let auxiliaryTopLeftArea: IslandRect?
    public let auxiliaryTopRightArea: IslandRect?
    public let attachment: IslandAttachment

    public init(
        displayID: UInt32,
        frame: IslandRect,
        visibleFrame: IslandRect,
        safeAreaInsets: IslandEdgeInsets,
        auxiliaryTopLeftArea: IslandRect?,
        auxiliaryTopRightArea: IslandRect?,
        attachment: IslandAttachment
    ) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.attachment = attachment
    }

    public var hardwareNotchWidth: Double {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }

    public var hardwareNotchHeight: Double {
        safeAreaInsets.top
    }
}

public struct IslandPanelPlacement: Equatable, Sendable {
    public let frame: IslandRect
    public let targetTop: Double
    public let topGap: Double

    public init(frame: IslandRect, targetTop: Double, topGap: Double) {
        self.frame = frame
        self.targetTop = targetTop
        self.topGap = topGap
    }
}

public struct IslandSurfaceGeometry: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let cornerRadius: Double
    /// Corner radius for a floating capsule's top edge. A notch-attached
    /// surface takes its top geometry from `shoulderInset` instead, since its
    /// top edge is flush with the physical screen edge.
    public let topCornerRadius: Double
    /// Additional width required around a hardware notch. The collapsed state
    /// uses 80 points for its two 40-point icon wings; floating capsules use 0.
    public let notchSideInset: Double
    /// How far each side of a notch-attached body pulls in from its full-width
    /// top edge, forming the shoulder. Zero keeps the body full width. This is
    /// interpolated across the morph, so the shoulder grows in continuously
    /// rather than the silhouette switching shape partway through.
    public let shoulderInset: Double

    public init(
        width: Double,
        height: Double,
        cornerRadius: Double,
        topCornerRadius: Double,
        notchSideInset: Double = 0,
        shoulderInset: Double = 0
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.topCornerRadius = topCornerRadius
        self.notchSideInset = notchSideInset
        self.shoulderInset = shoulderInset
    }
}

/// Vertical black ramp drawn over the expanded surface. The band that overlaps
/// the system status bar stays fully opaque; the remainder falls to clear so the
/// bottom edge of the surface is untinted Liquid Glass.
public struct IslandSurfaceShade: Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        /// Fraction of the surface height, measured from its top edge.
        public let location: Double
        public let opacity: Double

        public init(location: Double, opacity: Double) {
            self.location = location
            self.opacity = opacity
        }
    }

    public let stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }
}

public struct IslandMotionPolicy: Equatable, Sendable {
    public let hoverDuration: Double
    public let expansionDuration: Double
    public let collapseDuration: Double
    public let animatesOpticalHighlight: Bool

    public init(
        hoverDuration: Double,
        expansionDuration: Double,
        collapseDuration: Double,
        animatesOpticalHighlight: Bool
    ) {
        self.hoverDuration = hoverDuration
        self.expansionDuration = expansionDuration
        self.collapseDuration = collapseDuration
        self.animatesOpticalHighlight = animatesOpticalHighlight
    }
}

public enum GlassBackingLevel: Int, CaseIterable, Codable, Identifiable, Sendable {
    case clear = 0
    case light = 25
    case medium = 50
    case strong = 75
    case solid = 100

    public var id: Int { rawValue }
    public var opacity: Double { Double(rawValue) / 100 }

    public init(nearest value: Double) {
        let clamped = min(max(value, 0), 100)
        self = Self.allCases.min {
            abs(Double($0.rawValue) - clamped) < abs(Double($1.rawValue) - clamped)
        } ?? .light
    }

    public init(migratingLegacyBlur value: Double) {
        let clampedBlur = min(max(value, 0), 36)
        let firstNonzeroLevel = ceil(clampedBlur / 36 * 4) * 25
        self.init(nearest: firstNonzeroLevel)
    }
}

public enum LiquidGlassRuntimeMode: String, Equatable, Sendable {
    case notEvaluated
    case completePrivateRefraction
    case publicGlassFallback
    case legacyVisualEffectFallback
    case opaqueAccessibilityFallback
}

public enum LiquidGlassDispatchCommand: Equatable, Sendable {
    case variant(Int)
    case contentLensing(Int)
    case scrim(Int)
    case subdued(Int)
    case tint(Double?)
}

public struct LiquidGlassDispatchPlan: Equatable, Sendable {
    public let commands: [LiquidGlassDispatchCommand]

    public init(
        variant: Int,
        lensing: Int,
        scrim: Int = 0,
        subdued: Int = 0,
        tintOpacity: Double?
    ) {
        commands = [
            .variant(variant),
            .contentLensing(lensing),
            .scrim(scrim),
            .subdued(subdued),
            .tint(tintOpacity),
        ]
    }
}

public struct LiquidGlassConfiguration: Equatable, Sendable {
    public static let dockVariant = 2
    public static let dockLensing = 6

    public let tintOpacity: Double
    public let backingAlpha: Double
    public let variant: Int
    public let lensing: Int
    public let scrim: Int
    public let subdued: Int
    public let reduceTransparency: Bool
    public let privateRefractionEnabled: Bool

    public init(
        tint: Double,
        backingLevel: GlassBackingLevel,
        lensing: Double,
        reduceTransparency: Bool = false,
        privateRefractionEnabled: Bool = true
    ) {
        tintOpacity = min(max(tint, 0), 0.3)
        backingAlpha = backingLevel.opacity
        variant = Self.dockVariant
        self.lensing = min(max(Int(lensing.rounded()), 0), 6)
        scrim = 0
        subdued = 0
        self.reduceTransparency = reduceTransparency
        self.privateRefractionEnabled = privateRefractionEnabled
    }

    public var dispatchPlan: LiquidGlassDispatchPlan {
        LiquidGlassDispatchPlan(
            variant: variant,
            lensing: privateRefractionEnabled ? lensing : 0,
            scrim: scrim,
            subdued: subdued,
            tintOpacity: tintOpacity
        )
    }
}

public struct IslandDisplay: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let hasNotch: Bool

    public init(id: String, name: String, hasNotch: Bool) {
        self.id = id
        self.name = name
        self.hasNotch = hasNotch
    }
}

public struct IslandContext: Equatable, Sendable {
    public var hasCurrentTrack: Bool
    public var minutesUntilMeeting: Int?

    public init(
        hasCurrentTrack: Bool,
        minutesUntilMeeting: Int?
    ) {
        self.hasCurrentTrack = hasCurrentTrack
        self.minutesUntilMeeting = minutesUntilMeeting
    }
}
