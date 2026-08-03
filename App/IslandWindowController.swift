import AppKit
import LockTuneCore
import LockTuneDomain
import SwiftUI

@MainActor
final class IslandWindowController {
    private var panel: IslandPanel?
    private var observers: [NSObjectProtocol] = []
    private var isSessionActive = true
    private var isEnabled = true
    private var displayedScreenID: CGDirectDisplayID?
    private let visibilityPolicy = IslandCoordinator()

    func show(session: AppSession) {
        guard panel == nil else { return }
        isEnabled = session.isIslandEnabled
        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.title = "LockTune Island"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.setAccessibilityLabel(String(localized: "island.accessibility"))
        panel.contentView = NSHostingView(rootView: IslandView(session: session))
        self.panel = panel
        reposition()
        installObservers()
        if shouldBeVisible { panel.orderFrontRegardless() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if shouldBeVisible {
            reposition()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.close()
        panel = nil
        displayedScreenID = nil
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionActive = false
                self?.panel?.orderOut(nil)
            }
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSessionActive = true
                self?.reposition()
                if self?.shouldBeVisible == true { self?.panel?.orderFrontRegardless() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
    }

    private func reposition() {
        guard shouldBeVisible, let panel, let screen = targetScreen else { return }
        let x = screen.frame.midX - panel.frame.width / 2
        let availableTop = screen.safeAreaInsets.top > 0
            ? screen.frame.maxY - screen.safeAreaInsets.top
            : screen.visibleFrame.maxY
        let y = availableTop - panel.frame.height - 4
        let frame = NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: panel.frame.width,
            height: panel.frame.height
        )
        let screenID = screen.displayID
        guard panel.frame != frame || displayedScreenID != screenID else { return }

        // Move the independent status-bar panel without animating or carrying
        // the previous display's glass snapshot into the new screen.
        panel.orderOut(nil)
        panel.setFrame(frame, display: false)
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        displayedScreenID = screenID
    }

    private var targetScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first(where: { $0.isBuiltin }) ?? NSScreen.screens.first
    }

    private var shouldBeVisible: Bool {
        visibilityPolicy.isVisible(isEnabled: isEnabled, isSessionActive: isSessionActive)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltin: Bool {
        guard let screenNumber = displayID
        else { return false }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }
}

private struct IslandView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private let islandAnimation = Animation.spring(response: 0.38, dampingFraction: 0.84)

    var body: some View {
        islandContent
        .scaleEffect(isHovered ? 1.012 : 1)
        .animation(reduceMotion ? nil : islandAnimation, value: geometry)
        .onHover { hovering in
            guard !reduceMotion else { return }
            isHovered = hovering
        }
            .padding(4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("island.accessibility")
    }

    private var islandContent: some View {
        ZStack {
            Color.white.opacity(session.glassTint)
                .clipShape(RoundedRectangle(cornerRadius: geometry.cornerRadius, style: .continuous))
            GlassEdgeMaterial(session: session, cornerRadius: geometry.cornerRadius)
            HStack(spacing: 12) {
                icon
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryText)
                        .font(.headline)
                        .lineLimit(1)
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if presentation == .meeting, let meetURL = session.nextMeeting?.meetURL {
                    Button {
                        NSWorkspace.shared.open(meetURL)
                    } label: {
                        Image(systemName: "video.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("calendar.joinMeet")
                } else if presentation == .music {
                    Button {
                        Task { await session.togglePlayPause() }
                    } label: {
                        Image(systemName: session.playback.phase == .playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .foregroundStyle(.primary)
        }
        .frame(width: geometry.width, height: geometry.height)
    }

    private var presentation: IslandPresentation { session.islandPresentation }

    private var geometry: IslandGeometry {
        switch presentation {
        case .idle:
            IslandGeometry(width: 188, height: 48, cornerRadius: 24)
        case .music:
            IslandGeometry(width: 308, height: 56, cornerRadius: 28)
        case .meeting:
            IslandGeometry(width: 380, height: 64, cornerRadius: 32)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch presentation {
        case .meeting: Image(systemName: "calendar.badge.clock")
        case .music: Image(systemName: "waveform")
        case .idle: Image(systemName: "music.note")
        }
    }

    private var primaryText: String {
        switch presentation {
        case .meeting:
            let title = session.nextMeeting?.title ?? ""
            return title.isEmpty ? String(localized: "calendar.untitled") : title
        case .music: return session.currentTrackTitle
        case .idle: return String(localized: "app.name")
        }
    }

    private var secondaryText: String {
        switch presentation {
        case .meeting:
            guard let meeting = session.nextMeeting else { return String(localized: "island.meetingSoon") }
            return meeting.start.formatted(date: .abbreviated, time: .shortened)
        case .music:
            return session.playback.currentItem?.artist ?? String(localized: "player.localFirst")
        case .idle:
            return String(localized: "island.idle")
        }
    }
}

struct GlassEdgeMaterial: View {
    @Bindable var session: AppSession
    let cornerRadius: CGFloat

    private var edgeWidth: CGFloat {
        2 + CGFloat(session.glassRefraction) / 16
    }

    var body: some View {
        ZStack {
            EdgeMaterialView(
                tint: session.glassTint,
                edgeWidth: edgeWidth,
                cornerRadius: cornerRadius
            )
            .blur(radius: CGFloat(session.glassBlur) / 6)
            .mask(edgeMask)

            if session.glassMotionEnabled {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [.white.opacity(0.04), .white.opacity(0.3), .white.opacity(0.04)],
                                center: .center,
                                angle: .degrees(context.date.timeIntervalSinceReferenceDate * 16)
                            ),
                            lineWidth: 1.5 + CGFloat(session.glassRefraction) / 24
                        )
                }
            }
        }
        .opacity(0.35 + session.glassRefraction / 250)
        .allowsHitTesting(false)
    }

    private var edgeMask: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white, lineWidth: edgeWidth)
    }
}

private struct EdgeMaterialView: NSViewRepresentable {
    let tint: Double
    let edgeWidth: CGFloat
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> EdgeMaterialHostView {
        EdgeMaterialHostView()
    }

    func updateNSView(_ view: EdgeMaterialHostView, context: Context) {
        view.update(tint: tint, edgeWidth: edgeWidth, cornerRadius: cornerRadius)
    }
}

private final class EdgeMaterialHostView: NSView {
    private let materialView: NSView
    private let maskLayer = CAShapeLayer()
    private var edgeWidth: CGFloat = 8
    private var cornerRadius: CGFloat = 28

    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = 0
            materialView = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .underWindowBackground
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.isEmphasized = false
            materialView = effectView
        }
        super.init(frame: frameRect)
        wantsLayer = true
        materialView.wantsLayer = true
        materialView.layer?.mask = maskLayer
        addSubview(materialView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tint: Double, edgeWidth: CGFloat, cornerRadius: CGFloat) {
        self.edgeWidth = edgeWidth
        self.cornerRadius = cornerRadius
        if #available(macOS 26.0, *), let glassView = materialView as? NSGlassEffectView {
            glassView.tintColor = NSColor.white.withAlphaComponent(tint)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        let ring = CGMutablePath()
        ring.addPath(CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        ))
        let inset = min(edgeWidth, min(bounds.width, bounds.height) / 2)
        let innerBounds = bounds.insetBy(dx: inset, dy: inset)
        ring.addPath(CGPath(
            roundedRect: innerBounds,
            cornerWidth: max(0, cornerRadius - inset),
            cornerHeight: max(0, cornerRadius - inset),
            transform: nil
        ))
        maskLayer.frame = bounds
        maskLayer.path = ring
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.cgColor
    }
}

private struct IslandGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
}
