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
            PlaceholderView(
                title: "sidebar.nowPlaying",
                systemImage: "play.circle",
                message: "placeholder.nowPlaying"
            )
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
                Table(sortedTracks) {
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
                    }
                    TableColumn("library.artist") { track in
                        Text(track.metadata.artist ?? String(localized: "library.unknown"))
                    }
                    TableColumn("library.album") { track in
                        Text(track.metadata.album ?? String(localized: "library.unknown"))
                    }
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

    private var sortedTracks: [IndexedTrack] {
        session.musicLibrary.tracks.sorted {
            ($0.metadata.title ?? "").localizedStandardCompare($1.metadata.title ?? "") == .orderedAscending
        }
    }

    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    @ViewBuilder
    private func artwork(_ track: IndexedTrack) -> some View {
        if let data = track.metadata.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "music.note")
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .frame(width: 42, height: 42)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.currentTrackTitle)
                    .font(.headline)
                Text("player.localFirst")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("player.unavailable", systemImage: "play.fill") {}
                .buttonStyle(.borderless)
                .disabled(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
