import AppKit
import LockTuneCore
import LockTuneDomain
import SwiftUI

@MainActor
final class IslandWindowController {
    private static let panelSize = NSSize(width: 440, height: 82)

    private var panel: IslandPanel?
    private weak var session: AppSession?
    private var observers: [NSObjectProtocol] = []
    private var isSessionActive = true
    private var isEnabled = true
    private var displayedScreenID: CGDirectDisplayID?
    private var activeAppearanceCapabilities: LiquidGlassActiveAppearanceCapabilities?
    private let coordinator = IslandCoordinator()

    func show(session: AppSession) {
        guard panel == nil else { return }
        self.session = session
        isEnabled = session.isIslandEnabled
        let activeAppearance = LiquidGlassActiveAppearanceOverride.apply(to: IslandPanel.self)
        activeAppearanceCapabilities = activeAppearance
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        panel.acceptsMouseMovedEvents = true
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
        session = nil
        displayedScreenID = nil
    }

    func reposition() {
        guard shouldBeVisible, let panel, let screen = targetScreen else { return }
        let attachment: IslandAttachment = screen.hasHardwareNotch ? .notchAttached : .floatingCapsule
        let topGap: CGFloat = attachment == .notchAttached ? 0 : 8
        let anchorY = attachment == .notchAttached ? screen.frame.maxY : screen.visibleFrame.maxY
        let frame = NSRect(
            x: (screen.frame.midX - panel.frame.width / 2).rounded(),
            y: (anchorY - panel.frame.height - topGap).rounded(),
            width: panel.frame.width,
            height: panel.frame.height
        )
        let screenID = screen.lockTuneDisplayID
        session?.updateIslandDisplayEnvironment(
            displays: displayDescriptors,
            attachment: attachment,
            hardwareNotchWidth: Double(screen.hardwareNotchWidth)
        )
        guard panel.frame != frame || displayedScreenID != screenID else { return }

        panel.orderOut(nil)
        panel.setFrame(frame, display: false)
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        displayedScreenID = screenID
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.session?.preferredIslandDisplayID == nil else { return }
                self?.reposition()
            }
        })
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

    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        let resolved = coordinator.resolveDisplay(
            preferredID: session?.preferredIslandDisplayID,
            mainDisplayID: (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.lockTuneDisplayID.map(String.init),
            displays: displayDescriptors
        )
        return resolved.flatMap { selected in
            screens.first { $0.lockTuneDisplayID.map(String.init) == selected.id }
        } ?? NSScreen.main ?? screens.first
    }

    private var displayDescriptors: [IslandDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.lockTuneDisplayID else { return nil }
            return IslandDisplay(
                id: String(id),
                name: screen.localizedName,
                hasNotch: screen.hasHardwareNotch
            )
        }
    }

    private var shouldBeVisible: Bool {
        coordinator.isVisible(isEnabled: isEnabled, isSessionActive: isSessionActive)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var lockTuneDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var hasHardwareNotch: Bool {
        guard safeAreaInsets.top > 0 else { return false }
        return auxiliaryTopLeftArea != nil || auxiliaryTopRightArea != nil
    }

    var hardwareNotchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }
}

private struct IslandView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    private let coordinator = IslandCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            islandSurface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1, anchor: .top)
        .animation(surfaceAnimation, value: geometry)
        .animation(surfaceAnimation, value: session.islandAttachment)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("island.accessibility")
    }

    private var islandSurface: some View {
        LiquidGlassSurfaceContainer(
            session: session,
            cornerRadius: CGFloat(geometry.cornerRadius),
            backdropSource: .behindWindow,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        ) {
            VStack(spacing: 0) {
                if session.islandAttachment == .notchAttached {
                    Color.clear
                        .frame(height: notchClearance)
                        .allowsHitTesting(false)
                }
                IslandContent {
                    content
                }
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
        }
        .frame(width: resolvedWidth, height: CGFloat(geometry.height))
        .clipShape(shape)
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .shadow(color: .black.opacity(session.islandAttachment == .notchAttached ? 0.18 : 0.24), radius: 18, y: 8)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .music: musicContent
        case .meeting: meetingContent
        case .idle: idleContent
        }
    }

    private var musicContent: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 5) {
                Text(session.currentTrackTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(session.playback.currentItem?.artist ?? String(localized: "player.localFirst"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.primary.opacity(0.86))
                    .accessibilityLabel("island.playbackProgress")
                    .accessibilityValue(Text(progress, format: .percent))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controlButton("player.previous", systemImage: "backward.fill") {
                await session.playPrevious()
            }
            controlButton(
                session.playback.phase == .playing ? "player.pause" : "player.play",
                systemImage: session.playback.phase == .playing ? "pause.fill" : "play.fill",
                prominent: true
            ) {
                await session.togglePlayPause()
            }
            controlButton("player.next", systemImage: "forward.fill") {
                await session.playNext()
            }
        }
        .foregroundStyle(.primary)
    }

    private var meetingContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(.primary.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryText).font(.headline).lineLimit(1)
                Text(secondaryText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let meetURL = session.nextMeeting?.meetURL {
                Button {
                    NSWorkspace.shared.open(meetURL)
                } label: {
                    Label("calendar.joinMeet", systemImage: "video.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
        }
        .foregroundStyle(.primary)
    }

    private var idleContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
            VStack(alignment: .leading, spacing: 1) {
                Text("LockTune").font(.headline)
                Text("island.idle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = session.currentArtworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .frame(width: 50, height: 50)
                .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func controlButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .frame(width: prominent ? 34 : 26, height: prominent ? 34 : 26)
                .background(prominent ? Color.primary : Color.clear, in: Circle())
                .foregroundStyle(prominent ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var presentation: IslandPresentation { session.islandPresentation }
    private var geometry: IslandSurfaceGeometry {
        coordinator.geometry(for: presentation, attachment: session.islandAttachment)
    }
    private var resolvedWidth: CGFloat {
        let contentWidth = CGFloat(geometry.width)
        guard session.islandAttachment == .notchAttached else { return contentWidth }
        return max(contentWidth, CGFloat(session.islandHardwareNotchWidth) + 40)
    }
    private var notchClearance: CGFloat {
        min(32, CGFloat(geometry.height) * 0.42)
    }
    private var shape: IslandContinuousShape {
        IslandContinuousShape(
            topRadius: CGFloat(geometry.topCornerRadius),
            bottomRadius: CGFloat(geometry.cornerRadius)
        )
    }
    private var surfaceAnimation: Animation? {
        let policy = coordinator.motion(
            reduceMotion: reduceMotion,
            materialMotionEnabled: session.glassMotionEnabled
        )
        guard policy.transitionDuration > 0 else { return nil }
        return .spring(duration: policy.transitionDuration, bounce: 0.12)
    }
    private var progress: Double {
        guard let duration = session.playback.duration, duration > 0 else { return 0 }
        return min(max(session.playback.elapsed / duration, 0), 1)
    }
    private var primaryText: String {
        let title = session.nextMeeting?.title ?? ""
        return title.isEmpty ? String(localized: "calendar.untitled") : title
    }
    private var secondaryText: String {
        guard let meeting = session.nextMeeting else { return String(localized: "island.meetingSoon") }
        return meeting.start.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct IslandContent<Content: View>: View {
    let content: () -> Content

    var body: some View { content() }
}

private struct IslandContinuousShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: topRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: topRadius
            ),
            style: .continuous
        )
        .path(in: rect)
    }
}
