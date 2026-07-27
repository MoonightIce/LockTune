import SwiftUI
import LockTuneDomain
import AppKit

struct ContentView: View {
    @Bindable var session: AppSession
    @State private var selection: SidebarItem? = .library

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
                .navigationTitle("app.name")
            } detail: {
                detail
            }

            Divider()
            PlayerBar(session: session)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .library {
        case .library:
            MusicLibraryView(session: session)
        case .nowPlaying:
            NowPlayingView(session: session)
        case .calendar:
            PlaceholderView(
                title: "sidebar.calendar",
                systemImage: "calendar",
                message: "placeholder.calendar"
            )
        }
    }
}

private struct MusicLibraryView: View {
    @Bindable var session: AppSession
    @State private var selectedTrackID: Track.ID?

    var body: some View {
        Group {
            if session.musicLibrary.tracks.isEmpty {
                ContentUnavailableView {
                    Label("sidebar.library", systemImage: "music.note.list")
                } description: {
                    Text("placeholder.library")
                } actions: {
                    Button("library.addFolder", systemImage: "folder.badge.plus") {
                        Task { await session.chooseMusicFolder() }
                    }
                }
            } else {
                Table(sortedTracks, selection: $selectedTrackID) {
                    TableColumn("library.title") { track in
                        HStack(spacing: 8) {
                            artwork(track)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.metadata.title ?? String(localized: "library.unknownTitle"))
                                if track.metadata.status != .complete {
                                    Text(track.metadata.status == .unavailable
                                         ? "library.metadataUnavailable"
                                         : "library.metadataPartial")
                                        .font(.caption)
                                        .foregroundStyle(track.metadata.status == .unavailable ? .red : .secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            Task { await session.play(trackID: track.id) }
                        }
                    }
                    TableColumn("library.artist") { track in
                        Text(track.metadata.artist ?? String(localized: "library.unknown"))
                    }
                    TableColumn("library.album") { track in
                        Text(track.metadata.album ?? String(localized: "library.unknown"))
                    }
                    TableColumn("library.trackNumber") { track in
                        Text(track.metadata.trackNumber.map(String.init)
                             ?? String(localized: "library.unknown"))
                    }
                    .width(72)
                    TableColumn("library.duration") { track in
                        Text(duration(track.metadata.duration))
                            .monospacedDigit()
                    }
                    .width(72)
                }
            }
        }
        .navigationTitle("sidebar.library")
        .toolbar {
            ToolbarItemGroup {
                if session.isScanningMusic { ProgressView().controlSize(.small) }
                Button("player.playSelected", systemImage: "play.fill") {
                    guard let selectedTrackID else { return }
                    Task { await session.play(trackID: selectedTrackID) }
                }
                .disabled(selectedTrackID == nil || session.isScanningMusic)
                Button("library.refresh", systemImage: "arrow.clockwise") {
                    Task { await session.scanMusicFolders() }
                }
                .disabled(session.musicFolders.isEmpty || session.isScanningMusic)
                Button("library.addFolder", systemImage: "folder.badge.plus") {
                    Task { await session.chooseMusicFolder() }
                }
                .disabled(session.isScanningMusic)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if !session.musicLibrary.issues.isEmpty {
                    Divider()
                    Menu {
                        ForEach(Array(session.musicLibrary.issues.enumerated()), id: \.offset) { _, issue in
                            Label {
                                Text("\(issue.url.lastPathComponent) — \(issueLabel(issue.reason))")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        }
                    } label: {
                        Label(
                            String.localizedStringWithFormat(
                                String(localized: "library.issueCount"),
                                session.musicLibrary.issues.count
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
                if let error = session.musicLibraryError {
                    Divider()
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }
        }
    }

    private var sortedTracks: [Track] {
        session.musicLibrary.tracks.sorted {
            ($0.metadata.title ?? "").localizedStandardCompare($1.metadata.title ?? "") == .orderedAscending
        }
    }

    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return String(localized: "library.unknown")
        }
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    @ViewBuilder
    private func artwork(_ track: Track) -> some View {
        if let data = track.metadata.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "questionmark")
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel(Text("library.artworkUnknown"))
                .help("library.artworkUnknown")
        }
    }

    private func issueLabel(_ reason: MusicScanIssueReason) -> String {
        switch reason {
        case .unreadable: String(localized: "library.issue.unreadable")
        case .metadataUnavailable: String(localized: "library.issue.metadataUnavailable")
        case .unsupportedFormat: String(localized: "library.issue.unsupportedFormat")
        }
    }
}

private struct NowPlayingView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if session.playback.queue.isEmpty {
                ContentUnavailableView(
                    "sidebar.nowPlaying",
                    systemImage: "play.circle",
                    description: Text("placeholder.nowPlaying")
                )
            } else {
                List(Array(session.playback.queue.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: index == session.playback.currentIndex
                              ? playbackIndicator
                              : "music.note")
                            .foregroundStyle(
                                index == session.playback.currentIndex
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .fontWeight(index == session.playback.currentIndex ? .semibold : .regular)
                            Text(item.artist ?? String(localized: "library.unknown"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatDuration(item.duration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        Task { await session.playQueueItem(at: index) }
                    }
                    .accessibilityAddTraits(index == session.playback.currentIndex ? .isSelected : [])
                }
            }
        }
        .navigationTitle("sidebar.nowPlaying")
    }

    private var playbackIndicator: String {
        session.playback.phase == .playing ? "speaker.wave.2.fill" : "pause.fill"
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case nowPlaying
    case calendar

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .library: "sidebar.library"
        case .nowPlaying: "sidebar.nowPlaying"
        case .calendar: "sidebar.calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "music.note.list"
        case .nowPlaying: "play.circle"
        case .calendar: "calendar"
        }
    }
}

private struct PlaceholderView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

private struct PlayerBar: View {
    @Bindable var session: AppSession
    @State private var pendingSeek: Double = 0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 7) {
            if let failureReason = session.playback.failureReason {
                HStack {
                    Label(failureLabel(failureReason), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("player.skip") { Task { await session.playNext() } }
                    Button("player.retry") { Task { await session.retryPlayback() } }
                }
                .font(.callout)
            }

            HStack(spacing: 14) {
                artwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.currentTrackTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(session.playback.currentItem?.artist ?? String(localized: "player.localFirst"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 180, alignment: .leading)

                Button("player.previous", systemImage: "backward.fill") {
                    Task { await session.playPrevious() }
                }
                .labelStyle(.iconOnly)
                .disabled(session.playback.currentItem == nil || session.playback.phase == .loading)

                Button(playPauseLabel, systemImage: playPauseImage) {
                    Task { await session.togglePlayPause() }
                }
                .labelStyle(.iconOnly)
                .controlSize(.large)
                .disabled(!canTogglePlayback)

                Button("player.next", systemImage: "forward.fill") {
                    Task { await session.playNext() }
                }
                .labelStyle(.iconOnly)
                .disabled(session.playback.currentItem == nil || session.playback.phase == .loading)

                Text(formatDuration(displayedElapsed))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)

                Slider(
                    value: seekBinding,
                    in: 0...max(session.playback.duration ?? 0, 1),
                    onEditingChanged: seekEditingChanged
                )
                .disabled(session.playback.currentItem == nil || session.playback.duration == nil)

                Text(formatDuration(session.playback.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .leading)

                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(session.playback.volume) },
                        set: { value in Task { await session.setVolume(Float(value)) } }
                    ),
                    in: 0...1
                )
                .frame(width: 90)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = session.artworkData(for: session.playback.currentItem?.trackID),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: "music.note")
                .frame(width: 46, height: 46)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var playPauseLabel: LocalizedStringKey {
        session.playback.phase == .playing ? "player.pause" : "player.play"
    }

    private var playPauseImage: String {
        session.playback.phase == .playing ? "pause.fill" : "play.fill"
    }

    private var canTogglePlayback: Bool {
        session.playback.currentItem != nil && [.playing, .paused].contains(session.playback.phase)
    }

    private var displayedElapsed: Double {
        isSeeking ? pendingSeek : session.playback.elapsed
    }

    private var seekBinding: Binding<Double> {
        Binding(
            get: { displayedElapsed },
            set: { pendingSeek = $0 }
        )
    }

    private func seekEditingChanged(_ editing: Bool) {
        if editing {
            pendingSeek = session.playback.elapsed
            isSeeking = true
        } else {
            isSeeking = false
            let target = pendingSeek
            Task { await session.seek(to: target) }
        }
    }

    private func failureLabel(_ reason: PlaybackFailureReason) -> LocalizedStringKey {
        switch reason {
        case .cannotOpen: "player.error.cannotOpen"
        case .decodingFailed: "player.error.decodingFailed"
        case .audioOutputUnavailable: "player.error.audioOutputUnavailable"
        }
    }
}

private func formatDuration(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—:—" }
    return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}
