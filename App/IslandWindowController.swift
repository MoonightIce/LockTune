import AppKit
import LockTuneCore
import LockTuneDomain
import SwiftUI

private extension Notification.Name {
    static let lockTuneIslandEscape = Notification.Name("LockTune.IslandEscape")
    static let lockTuneIslandPointerDown = Notification.Name("LockTune.IslandPointerDown")
    static let lockTuneIslandGeometryStateChanged = Notification.Name("LockTune.IslandGeometryStateChanged")
}

@MainActor
final class IslandWindowController {
    // The transparent panel reserves the maximum expanded height. The visible
    // surface inside it morphs between the session's collapsed reference
    // height, 47 and 132 points while its top anchor remains fixed.
    private static let panelSize = NSSize(width: 440, height: 132)

    private var panel: IslandPanel?
    private weak var session: AppSession?
    private var observers: [NSObjectProtocol] = []
    private var isSessionActive = true
    private var isEnabled = true
    private var displayedScreenID: CGDirectDisplayID?
    private var activeAppearanceCapabilities: LiquidGlassActiveAppearanceCapabilities?
    private var keyMonitor: Any?
    private let coordinator = IslandCoordinator()

    func show(session: AppSession) {
        guard panel == nil else { return }
        self.session = session
        isEnabled = session.isIslandEnabled
        let activeAppearance = LiquidGlassActiveAppearanceOverride.apply(to: IslandPanel.self)
        activeAppearanceCapabilities = activeAppearance
        session.setIslandActiveAppearanceOverrideAvailable(
            activeAppearance.allSelectorsPresent && activeAppearance.allSelectorsInstalled
        )
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
        panel.contentView = IslandContentHostingView(rootView: IslandView(session: session))
        self.panel = panel
        reposition()
        installObservers()
        installEscapeMonitor()
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.close()
        panel = nil
        session = nil
        displayedScreenID = nil
    }

    func reposition() {
        guard shouldBeVisible,
              let panel,
              let screen = targetScreen,
              let displayGeometry = screen.islandDisplayGeometry
        else { return }
        panel.allowsTopSafeArea = displayGeometry.attachment == .notchAttached
        let panelWidth = min(Self.panelSize.width, max(1, displayGeometry.visibleFrame.width))
        let placement = coordinator.panelPlacement(
            for: displayGeometry,
            panelWidth: Double(panelWidth),
            panelHeight: Double(panel.frame.height)
        )
        let requestedFrame = NSRect(
            x: placement.frame.minX,
            y: placement.frame.minY,
            width: placement.frame.width,
            height: placement.frame.height
        )
        let screenID = displayGeometry.displayID
        let displays = displayDescriptors
        if session?.availableIslandDisplays != displays || session?.islandDisplayGeometry != displayGeometry {
            session?.updateIslandDisplayEnvironment(displays: displays, geometry: displayGeometry)
        }
        if panel.frame != requestedFrame || displayedScreenID != screenID {
            panel.orderOut(nil)
            panel.setFrame(requestedFrame, display: false)
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
        }
        validatePlacement(
            panel: panel,
            targetScreen: screen,
            displayGeometry: displayGeometry,
            requestedFrame: requestedFrame,
            placement: placement
        )
        displayedScreenID = screenID
        // SwiftUI may still be laying out the shared path when setFrame
        // returns. Re-read the applied panel and surface frames once the next
        // run-loop turn has committed the host hierarchy.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.shouldBeVisible else { return }
            self.validatePlacement(
                panel: panel,
                targetScreen: screen,
                displayGeometry: displayGeometry,
                requestedFrame: requestedFrame,
                placement: placement
            )
        }
    }

    private func validatePlacement(
        panel: IslandPanel,
        targetScreen: NSScreen,
        displayGeometry: IslandDisplayGeometry,
        requestedFrame: NSRect,
        placement: IslandPanelPlacement
    ) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let appliedFrame = panel.frame
        let surfaceFrame = surfaceGlobalFrame(in: panel)
        let appliedTopError = abs(appliedFrame.maxY - placement.targetTop)
        let surfaceTopError = surfaceFrame.map { abs($0.maxY - placement.targetTop) }
            ?? .infinity
        let panelDisplayID = displayContaining(panel.frame)?.lockTuneDisplayID
        let targetDisplayID = targetScreen.lockTuneDisplayID ?? displayGeometry.displayID
        let displayMatches = panelDisplayID == targetDisplayID
        let placementPassed = appliedTopError <= 0.5
            && surfaceTopError <= 0.5
            && displayMatches
        let surfaceDescription = surfaceFrame.map(frameDescription) ?? "pending"
        NSLog(
            "LOCKTUNE_ISLAND_PLACEMENT status=%@ attachment=%@ display=%u requested=%@ applied=%@ surface=%@ targetTop=%.2f panelTopError=%.2f surfaceTopError=%.2f panelDisplay=%@ targetDisplay=%u layer=%ld alpha=%.2f onscreen=%@",
            placementPassed ? "PASS" : "FAIL",
            displayGeometry.attachment == .notchAttached ? "notch" : "floating",
            displayGeometry.displayID,
            frameDescription(requestedFrame),
            frameDescription(appliedFrame),
            surfaceDescription,
            placement.targetTop,
            appliedTopError,
            surfaceTopError,
            panelDisplayID.map(String.init) ?? "none",
            targetDisplayID,
            panel.level.rawValue,
            panel.alphaValue,
            panel.isOnActiveSpace && panel.isVisible ? "YES" : "NO"
        )

        guard appliedTopError > 0.5 else { return }
        var correctedFrame = appliedFrame
        correctedFrame.origin.y += placement.targetTop - appliedFrame.maxY
        panel.setFrame(correctedFrame, display: false)
        panel.displayIfNeeded()
        let correctedApplied = panel.frame
        let correctedError = abs(correctedApplied.maxY - placement.targetTop)
        NSLog(
            "LOCKTUNE_ISLAND_PLACEMENT_CORRECTION requested=%@ applied=%@ topError=%.2f",
            frameDescription(correctedFrame),
            frameDescription(correctedApplied),
            correctedError
        )
    }

    private func validateCurrentPlacement() {
        guard shouldBeVisible,
              let panel,
              let screen = targetScreen,
              let displayGeometry = session?.islandDisplayGeometry
        else { return }
        let panelWidth = min(Self.panelSize.width, max(1, displayGeometry.visibleFrame.width))
        let placement = coordinator.panelPlacement(
            for: displayGeometry,
            panelWidth: Double(panelWidth),
            panelHeight: Double(panel.frame.height)
        )
        validatePlacement(
            panel: panel,
            targetScreen: screen,
            displayGeometry: displayGeometry,
            requestedFrame: NSRect(
                x: placement.frame.minX,
                y: placement.frame.minY,
                width: placement.frame.width,
                height: placement.frame.height
            ),
            placement: placement
        )
    }

    private func surfaceGlobalFrame(in panel: IslandPanel) -> NSRect? {
        guard let host = findSurfaceHost(in: panel.contentView),
              let window = host.window
        else { return nil }
        let windowFrame = host.convert(host.bounds, to: nil)
        return window.convertToScreen(windowFrame)
    }

    private func findSurfaceHost(in view: NSView?) -> LiquidGlassSurfaceHost? {
        guard let view else { return nil }
        if let host = view as? LiquidGlassSurfaceHost { return host }
        for child in view.subviews {
            if let host = findSurfaceHost(in: child) { return host }
        }
        return nil
    }

    private func displayContaining(_ frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func frameDescription(_ frame: NSRect) -> String {
        String(format: "{{%.2f,%.2f},{%.2f,%.2f}}", frame.minX, frame.minY, frame.width, frame.height)
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
        observers.append(NotificationCenter.default.addObserver(
            forName: .lockTuneIslandGeometryStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // The state notification marks the start of the shared SwiftUI
                // animation. Validate again after the longest 0.38s morph so
                // each final state has a recorded surface-global top error.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    MainActor.assumeIsolated { self?.validateCurrentPlacement() }
                }
            }
        })
    }

    private func installEscapeMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.shouldBeVisible == true else { return event }
            NotificationCenter.default.post(name: .lockTuneIslandEscape, object: nil)
            return nil
        }
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
    var allowsTopSafeArea = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsTopSafeArea ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    override func sendEvent(_ event: NSEvent) {
        // A nonactivating status-bar panel does not reliably deliver SwiftUI's
        // gesture recognizer. Bridge only the initial pointer down; the view
        // decides whether this is an expand or collapse transition.
        if event.type == .leftMouseDown,
           let contentView,
           contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)) != nil {
            NotificationCenter.default.post(
                name: .lockTuneIslandPointerDown,
                object: nil
            )
        }
        super.sendEvent(event)
    }
}

private final class IslandContentHostingView: NSHostingView<IslandView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The panel reserves the maximum expanded height so the surface can
        // morph downward from a stable top anchor. Its transparent reserve
        // must not intercept clicks intended for the main window underneath.
        guard let surfaceHost = findSurfaceHost(in: self) else {
            return super.hitTest(point)
        }
        let surfaceFrame = surfaceHost.convert(surfaceHost.bounds, to: self)
        guard surfaceFrame.contains(point) else { return nil }
        return super.hitTest(point)
    }

    private func findSurfaceHost(in view: NSView) -> LiquidGlassSurfaceHost? {
        if let host = view as? LiquidGlassSurfaceHost { return host }
        for child in view.subviews {
            if let host = findSurfaceHost(in: child) { return host }
        }
        return nil
    }
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

    var islandDisplayGeometry: IslandDisplayGeometry? {
        guard let displayID = lockTuneDisplayID else { return nil }
        let attachment: IslandAttachment = hasHardwareNotch ? .notchAttached : .floatingCapsule
        return IslandDisplayGeometry(
            displayID: displayID,
            frame: IslandRect(
                x: Double(frame.minX), y: Double(frame.minY),
                width: Double(frame.width), height: Double(frame.height)
            ),
            visibleFrame: IslandRect(
                x: Double(visibleFrame.minX), y: Double(visibleFrame.minY),
                width: Double(visibleFrame.width), height: Double(visibleFrame.height)
            ),
            safeAreaInsets: IslandEdgeInsets(
                top: Double(safeAreaInsets.top),
                left: Double(safeAreaInsets.left),
                bottom: Double(safeAreaInsets.bottom),
                right: Double(safeAreaInsets.right)
            ),
            auxiliaryTopLeftArea: auxiliaryTopLeftArea.map {
                IslandRect(x: Double($0.minX), y: Double($0.minY), width: Double($0.width), height: Double($0.height))
            },
            auxiliaryTopRightArea: auxiliaryTopRightArea.map {
                IslandRect(x: Double($0.minX), y: Double($0.minY), width: Double($0.width), height: Double($0.height))
            },
            attachment: attachment
        )
    }
}

private struct IslandView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var expansionState: IslandExpansionState = .collapsed
    @State private var revealExpandedContent = false
    /// The collapsed wings start visible so a launch into the collapsed state
    /// does not wait on a contraction that never happens.
    @State private var wingIconsRevealed = true

    private let coordinator = IslandCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            islandSurface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(containerAnimation, value: expansionState)
        .animation(containerAnimation, value: session.islandAttachment)
        .onExitCommand { collapse() }
        .onReceive(NotificationCenter.default.publisher(for: .lockTuneIslandEscape)) { _ in
            collapse()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lockTuneIslandPointerDown)) { _ in
            guard expansionState != .expanded else { return }
            surfaceTapped()
        }
        .task(id: expansionState) {
            guard expansionState == .expanded else {
                revealExpandedContent = false
                await revealWingsAfterContraction()
                return
            }
            // The wings belong to the collapsed silhouette. Dropping them on the
            // way out is what makes the next collapse re-reveal them only after
            // the surface has finished contracting.
            wingIconsRevealed = false
            if reduceMotion {
                revealExpandedContent = true
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, expansionState == .expanded else { return }
            withAnimation(revealAnimation) { revealExpandedContent = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("island.accessibility")
    }

    private var islandSurface: some View {
        let wingOnlyCompact = session.islandAttachment == .notchAttached
            && expansionState == .collapsed
        return IslandSurfaceMorph(
            session: session,
            attachment: session.islandAttachment,
            width: resolvedWidth,
            height: CGFloat(geometry.height),
            topRadius: CGFloat(geometry.topCornerRadius),
            bottomRadius: CGFloat(geometry.cornerRadius),
            shoulderInset: CGFloat(geometry.shoulderInset),
            reduceTransparency: reduceTransparency,
            activeAppearanceOverrideAvailable: session.islandActiveAppearanceOverrideAvailable,
            // The expanded surface fills the panel to within 10pt, far less
            // than the 18pt shadow radius, so the window edge would clip the
            // soft falloff into two hard-edged grey bands. Narrower states
            // keep their shadow because the panel has room to render it.
            shadowEnabled: !wingOnlyCompact && expansionState != .expanded,
            // Any shaded surface supplies its own darkness, so the frosted
            // backing is cleared to keep the ramp's floor at its measured value
            // instead of hazing it toward grey.
            backingLevelOverride: expansionState == .collapsed ? nil : .clear,
            contentRevision: islandContentRevision
        ) {
            ZStack {
                if wingOnlyCompact {
                    // The collapsed notch silhouette is intentionally opaque
                    // black. It still travels through the same glass host and
                    // path, but the hardware cutout and both icon wings read
                    // as one continuous black shape.
                    Color.black
                        .allowsHitTesting(false)
                } else if expansionState != .collapsed {
                    // One vertical ramp over the same refractive host, shared by
                    // the hovered and expanded surfaces so the shade animates
                    // continuously between them. It must reach both side edges,
                    // so the content inset lives on the content stack rather
                    // than on this container.
                    IslandShadeLayer(
                        coordinator: coordinator,
                        statusBarHeight: statusBarBandHeight,
                        reduceTransparency: reduceTransparency
                    )
                    .allowsHitTesting(false)
                }
                Color.clear
                    .allowsHitTesting(false)

                if expansionState == .expanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { collapse() }
                }

                VStack(spacing: 0) {
                    if session.islandAttachment == .notchAttached,
                       expansionState == .expanded {
                        Color.clear
                            .frame(height: notchClearance)
                            .allowsHitTesting(false)
                    }
                    IslandContent {
                        ZStack {
                            if coordinator.showsCompactContent(
                                attachment: session.islandAttachment,
                                expansionState: expansionState
                            ) {
                                Group {
                                    if wingOnlyCompact {
                                        wingOnlyCompactContent
                                    } else {
                                        compactContent
                                    }
                                }
                                .opacity(expansionState == .expanded ? 0 : 1)
                            }
                            content
                                .opacity(revealExpandedContent ? 1 : 0)
                                .allowsHitTesting(expansionState == .expanded && revealExpandedContent)
                                .environment(\.colorScheme, .dark)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                // The body is narrower than the surface by the shoulder inset,
                // so content has to clear that too or the clip path cuts into
                // it. Using the target inset rather than the interpolated one
                // keeps this off the per-frame path.
                .padding(.horizontal, wingOnlyCompact ? 0 : 16 + CGFloat(geometry.shoulderInset))
            }
        }
        .onHover { updateHover($0) }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch presentation {
        case .music:
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                Text(session.currentTrackTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        case .meeting:
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text(primaryText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        case .idle:
            idleContent
        }
    }

    private var wingOnlyCompactContent: some View {
        HStack(spacing: 0) {
            compactWingIcon(for: presentation)
                .frame(width: 40, height: geometry.height)
            Spacer(minLength: CGFloat(session.islandHardwareNotchWidth))
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: geometry.height)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .opacity(wingIconsRevealed ? 1 : 0)
    }

    /// The wings are laid out against the surface's current width, so revealing
    /// them mid-contraction puts them where the surface used to be and lets the
    /// shrinking clip path cut into them. Waiting for the morph to settle is
    /// also how Droppy sequences it: contract first, then show the wings.
    private func revealWingsAfterContraction() async {
        guard !wingIconsRevealed else { return }
        guard !reduceMotion else {
            wingIconsRevealed = true
            return
        }
        let policy = coordinator.motion(
            reduceMotion: reduceMotion,
            materialMotionEnabled: session.glassMotionEnabled
        )
        try? await Task.sleep(nanoseconds: UInt64(policy.collapseDuration * 1_000_000_000))
        guard !Task.isCancelled, expansionState != .expanded else { return }
        withAnimation(.easeOut(duration: 0.14)) { wingIconsRevealed = true }
    }

    @ViewBuilder
    private func compactWingIcon(for presentation: IslandPresentation) -> some View {
        switch presentation {
        case .music:
            Image(systemName: "music.note")
        case .meeting:
            Image(systemName: "calendar.badge.clock")
        case .idle:
            Image(systemName: "music.note")
        }
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
    private var islandContentRevision: String {
        [
            expansionState.rawValue,
            revealExpandedContent ? "revealed" : "hidden",
            wingIconsRevealed ? "wings" : "noWings",
            String(describing: presentation),
            session.currentTrackTitle,
            session.playback.currentItem?.artist ?? "",
            String(describing: session.playback.phase),
            primaryText,
            secondaryText,
            String(Int(progress * 100))
        ].joined(separator: "|")
    }
    private var geometry: IslandSurfaceGeometry {
        coordinator.geometry(
            for: presentation,
            attachment: session.islandAttachment,
            expansionState: expansionState,
            collapsedReferenceHeight: session.islandCollapsedReferenceHeight
        )
    }
    private var resolvedWidth: CGFloat {
        let availableWidth = session.islandDisplayGeometry.map {
            Double(max(0, $0.visibleFrame.width - 32))
        }
        return CGFloat(coordinator.resolvedWidth(
            for: geometry,
            attachment: session.islandAttachment,
            hardwareNotchWidth: session.islandHardwareNotchWidth,
            availableWidth: availableWidth
        ))
    }
    private var notchClearance: CGFloat {
        CGFloat(session.islandDisplayGeometry?.hardwareNotchHeight ?? 0)
    }
    /// Raises the shade's opaque band when the status bar reaches past the
    /// coordinator's default. A floating capsule hangs below the menu bar and
    /// overlaps nothing, so it just takes the default band.
    private var statusBarBandHeight: CGFloat {
        session.islandAttachment == .notchAttached ? notchClearance : 0
    }
    private var containerAnimation: Animation? {
        animation(for: expansionState)
    }
    private var revealAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: 0.16)
    }
    private func animation(for state: IslandExpansionState) -> Animation? {
        let policy = coordinator.motion(
            reduceMotion: reduceMotion,
            materialMotionEnabled: session.glassMotionEnabled
        )
        switch state {
        case .hovered:
            guard policy.hoverDuration > 0 else { return nil }
            return .easeOut(duration: policy.hoverDuration)
        case .expanded:
            guard policy.expansionDuration > 0 else { return nil }
            return .spring(duration: policy.expansionDuration, bounce: 0.11)
        case .collapsed:
            guard policy.collapseDuration > 0 else { return nil }
            return .easeInOut(duration: policy.collapseDuration)
        }
    }
    private func updateHover(_ hovering: Bool) {
        guard expansionState != .expanded else { return }
        transition(to: hovering ? .hovered : .collapsed)
    }
    private func surfaceTapped() {
        transition(to: expansionState == .expanded ? .collapsed : .expanded)
    }
    private func collapse() {
        guard expansionState != .collapsed else { return }
        transition(to: .collapsed)
    }
    private func transition(to state: IslandExpansionState) {
        withAnimation(animation(for: state)) {
            expansionState = state
        }
        NotificationCenter.default.post(
            name: .lockTuneIslandGeometryStateChanged,
            object: nil,
            userInfo: ["state": state.rawValue]
        )
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

/// Animates the numeric surface values themselves so SwiftUI's clip shape and
/// the AppKit host receive the same intermediate path on every animation frame.
@MainActor
private struct IslandSurfaceMorph<Content: View>: View, @preconcurrency Animatable {
    @Bindable var session: AppSession
    let attachment: IslandAttachment
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var shoulderInset: CGFloat
    let reduceTransparency: Bool
    let activeAppearanceOverrideAvailable: Bool
    let shadowEnabled: Bool
    /// The expanded surface supplies its own shade, so it clears the frosted
    /// backing to keep its bottom edge pure Liquid Glass.
    let backingLevelOverride: GlassBackingLevel?
    let contentRevision: String
    let content: () -> Content

    var animatableData: AnimatablePair<
        CGFloat,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    > {
        get {
            AnimatablePair(
                width,
                AnimatablePair(
                    height,
                    AnimatablePair(topRadius, AnimatablePair(bottomRadius, shoulderInset))
                )
            )
        }
        set {
            width = newValue.first
            height = newValue.second.first
            topRadius = newValue.second.second.first
            bottomRadius = newValue.second.second.second.first
            shoulderInset = newValue.second.second.second.second
        }
    }

    var body: some View {
        let path = LiquidGlassSurfacePath(
            attachment: attachment,
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            shoulderInset: shoulderInset
        )
        let shape = IslandContinuousShape(
            attachment: attachment,
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            shoulderInset: shoulderInset
        )
        return LiquidGlassSurfaceContainer(
            session: session,
            cornerRadius: max(topRadius, bottomRadius),
            surfacePath: path,
            backdropSource: .behindWindow,
            reduceTransparency: reduceTransparency,
            activeAppearanceOverrideAvailable: activeAppearanceOverrideAvailable,
            backingLevelOverride: backingLevelOverride,
            contentRevision: contentRevision,
            content: content
        )
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay {
            shape.stroke(.white.opacity(reduceTransparency ? 0.18 : 0.12), lineWidth: 0.55)
        }
        .contentShape(shape)
        .shadow(
            color: shadowEnabled ? .black.opacity(attachment == .notchAttached ? 0.18 : 0.24) : .clear,
            radius: shadowEnabled ? 18 : 0,
            y: shadowEnabled ? 8 : 0
        )
    }
}

/// Reads the live surface height so the opaque band keeps its measured
/// status-bar height through the morph, instead of scaling with it.
private struct IslandShadeLayer: View {
    let coordinator: IslandCoordinator
    let statusBarHeight: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            let shade = coordinator.surfaceShade(
                statusBarHeight: Double(statusBarHeight),
                surfaceHeight: Double(proxy.size.height),
                reduceTransparency: reduceTransparency
            )
            LinearGradient(
                stops: shade.stops.map {
                    Gradient.Stop(
                        color: .black.opacity($0.opacity),
                        location: CGFloat($0.location)
                    )
                },
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct IslandContent<Content: View>: View {
    let content: () -> Content

    var body: some View { content() }
}

private struct IslandContinuousShape: Shape {
    var attachment: IslandAttachment
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var shoulderInset: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topRadius, AnimatablePair(bottomRadius, shoulderInset)) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second.first
            shoulderInset = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        LiquidGlassSurfacePath(
            attachment: attachment,
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            shoulderInset: shoulderInset
        )
        .path(in: rect)
    }
}
