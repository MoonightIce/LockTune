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

public struct IslandSurfaceGeometry: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let cornerRadius: Double
    public let topCornerRadius: Double

    public init(width: Double, height: Double, cornerRadius: Double, topCornerRadius: Double) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.topCornerRadius = topCornerRadius
    }
}

public struct IslandMotionPolicy: Equatable, Sendable {
    public let transitionDuration: Double
    public let animatesOpticalHighlight: Bool

    public init(transitionDuration: Double, animatesOpticalHighlight: Bool) {
        self.transitionDuration = transitionDuration
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
    public let dynamicAurora: Bool
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let privateRefractionEnabled: Bool

    public init(
        tint: Double,
        backingLevel: GlassBackingLevel,
        lensing: Double,
        dynamicAurora: Bool = true,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        privateRefractionEnabled: Bool = true
    ) {
        tintOpacity = min(max(tint, 0), 0.3)
        backingAlpha = backingLevel.opacity
        variant = Self.dockVariant
        self.lensing = min(max(Int(lensing.rounded()), 0), 6)
        scrim = 0
        subdued = 0
        self.dynamicAurora = dynamicAurora
        self.reduceMotion = reduceMotion
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
