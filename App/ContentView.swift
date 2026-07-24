import SwiftUI

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
            PlaceholderView(
                title: "sidebar.library",
                systemImage: "music.note.list",
                message: "placeholder.library"
            )
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

            Button {
                session.isPlaying.toggle()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(session.isPlaying ? "player.pause" : "player.play")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
