import SwiftUI
import LockTuneDomain
import AppKit
import ImageIO

struct ContentView: View {
    @Bindable var session: AppSession
    @State private var selection: SidebarItem? = .library

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        LockTuneBrandMark().frame(width: 36, height: 36)
                        Text("app.name").font(.title3.weight(.bold))
                    }
                    .padding(.horizontal, 23).padding(.top, 25).padding(.bottom, 28)
                    VStack(spacing: 8) {
                        ForEach(SidebarItem.allCases) { item in
                            Button { selection = item } label: {
                                Label(item.title, systemImage: item.systemImage)
                                    .font(.system(size: 14, weight: selection == item ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 15).frame(height: 46)
                                    .background(selection == item ? Color.white.opacity(0.9) : .clear,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 15)
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Label("本地音乐库", systemImage: "circle.fill").font(.callout).foregroundStyle(.secondary)
                        Text("\(session.musicLibrary.tracks.count) 首歌曲").font(.caption).foregroundStyle(.tertiary).padding(.leading, 20)
                    }.padding(.horizontal, 25).padding(.bottom, 25)
                }
                .frame(width: 218).background(Color(red: 0.925, green: 0.932, blue: 0.955))
                Divider()
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
        }
    }
}

private struct MusicLibraryView: View {
    @Bindable var session: AppSession
    @State private var selectedTrackID: Track.ID?
    @State private var searchText = ""
    @State private var browseMode: LibraryBrowseMode = .songs
    @State private var isCalendarPanelVisible = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Menu { Picker("library.browse", selection: $browseMode) { ForEach(LibraryBrowseMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) } } } label: { Label(browseMode.title, systemImage: browseMode.systemImage) }.menuStyle(.borderlessButton)
                Button("library.refresh", systemImage: "arrow.clockwise") { Task { await session.scanMusicFolders() } }.labelStyle(.iconOnly).disabled(session.musicFolders.isEmpty || session.isScanningMusic)
                Button("library.addFolder", systemImage: "folder.badge.plus") { Task { await session.chooseMusicFolder() } }.labelStyle(.iconOnly).disabled(session.isScanningMusic)
                Button("文件信息修复", systemImage: "text.badge.plus") { Task { await session.repairMusicMetadata() } }.labelStyle(.titleAndIcon).disabled(!session.canRepairMusicMetadata() || session.isScanningMusic)
                Button { withAnimation(.easeInOut(duration: 0.2)) { isCalendarPanelVisible.toggle() } } label: { Label(isCalendarPanelVisible ? "隐藏日历" : "显示日历", systemImage: isCalendarPanelVisible ? "calendar.badge.minus" : "calendar.badge.plus") }.buttonStyle(.bordered)
                Spacer()
                TextField("搜索音乐", text: $searchText).textFieldStyle(.roundedBorder).frame(width: 180)
            }.padding(.horizontal, 20).frame(height: 54).background(Color.white.opacity(0.86))
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) { Text("音乐库").font(.caption).foregroundStyle(.secondary); Text("你的声音收藏").font(.system(size: 30, weight: .medium, design: .rounded)) }
                        Spacer()
                        Button("播放全部", systemImage: "play.fill") { if let first = sortedRows.first { Task { await session.play(trackID: first.id) } } }.buttonStyle(.borderedProminent).tint(.black).disabled(sortedRows.isEmpty || session.isScanningMusic)
                    }.padding(.horizontal, 30).padding(.top, 27).padding(.bottom, 20)
                    if session.musicLibrary.tracks.isEmpty {
                        ContentUnavailableView { Label("sidebar.library", systemImage: "music.note.list") } description: { Text("placeholder.library") } actions: { Button("library.addFolder", systemImage: "folder.badge.plus") { Task { await session.chooseMusicFolder() } } }
                    } else {
                        List(selection: $selectedTrackID) {
                            ForEach(sortedRows) { row in
                                let track = row.track
                                HStack(spacing: 12) {
                                    artwork(track)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.metadata.title ?? String(localized: "library.unknownTitle")).fontWeight(selectedTrackID == track.id ? .semibold : .regular).lineLimit(1)
                                        Text(track.metadata.artist ?? String(localized: "library.unknown")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                                    Text(track.metadata.album ?? String(localized: "library.unknown")).foregroundStyle(.secondary).lineLimit(1).frame(width: 190, alignment: .leading)
                                    Text(duration(track.metadata.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                                }
                                .padding(.horizontal, 18).padding(.vertical, 4).contentShape(Rectangle())
                                .tag(track.id)
                                .listRowBackground(RoundedRectangle(cornerRadius: 9).fill(selectedTrackID == track.id ? Color.accentColor.opacity(0.14) : .clear).padding(.horizontal, 8))
                                .onTapGesture { selectedTrackID = track.id }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { Task { await session.play(trackID: track.id) } })
                            }
                        }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.white)
                    }
                }.frame(maxWidth: .infinity).background(Color.white)
                if isCalendarPanelVisible { Divider(); CompactCalendarPanel(session: session).frame(width: 310) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let progress = session.musicScanProgress {
                MusicScanProgressCard(
                    progress: progress,
                    cancel: session.cancelMusicScan
                )
                    .padding(16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.musicScanProgress != nil)
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
                if let notice = session.musicLibraryNotice {
                    Divider()
                    Text(notice).font(.callout).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                }
            }
        }
    }

    private var sortedRows: [LibraryTrackRow] {
        let folderNamesByTrackID = session.musicLibrary.locations.reduce(
            into: [Track.ID: String]()
        ) { result, location in
            guard result[location.trackID] == nil else { return }
            result[location.trackID] = location.url.deletingLastPathComponent().lastPathComponent
        }
        let unknownFolder = String(localized: "library.unknown")
        let matching = session.musicLibrary.tracks.compactMap { track -> LibraryTrackRow? in
            let folderName = folderNamesByTrackID[track.id] ?? unknownFolder
            let fields = [track.metadata.title, track.metadata.artist, track.metadata.album, folderName]
                .compactMap { $0 }
            let matchesSearch = searchText.isEmpty || fields.contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
            guard matchesSearch,
                  browseMode != .favorites || session.favoriteTrackIDs.contains(track.id)
            else { return nil }
            return LibraryTrackRow(track: track, folderName: folderName)
        }
        return matching.sorted { lhs, rhs in
            let lhsKeys = sortKeys(for: lhs)
            let rhsKeys = sortKeys(for: rhs)
            for (left, right) in zip(lhsKeys, rhsKeys) {
                let order = left.localizedStandardCompare(right)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortKeys(for row: LibraryTrackRow) -> [String] {
        let track = row.track
        let title = track.metadata.title ?? ""
        switch browseMode {
        case .songs, .favorites: return [title]
        case .albums: return [track.metadata.album ?? "", String(format: "%06d", track.metadata.trackNumber ?? 0), title]
        case .artists: return [track.metadata.artist ?? "", track.metadata.album ?? "", title]
        case .folders: return [row.folderName, title]
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
        LibraryArtworkView(track: track, session: session)
    }

    private func issueLabel(_ reason: MusicScanIssueReason) -> String {
        switch reason {
        case .unreadable: String(localized: "library.issue.unreadable")
        case .metadataUnavailable: String(localized: "library.issue.metadataUnavailable")
        case .unsupportedFormat: String(localized: "library.issue.unsupportedFormat")
        }
    }
}

private struct MusicScanProgressCard: View {
    let progress: MusicScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: phaseImage)
                    .foregroundStyle(.tint)
                Text("library.scan.title")
                    .font(.headline)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 72, alignment: .trailing)
                }
            }
            Text(phaseLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text("library.scan.readOnly")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("library.scan.cancel", role: .cancel, action: cancel)
                .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6))
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private var phaseLabel: LocalizedStringKey {
        switch progress.phase {
        case .discovering: "library.scan.discovering"
        case .indexing: "library.scan.indexing"
        case .artwork: "library.scan.artwork"
        case .saving: "library.scan.saving"
        }
    }

    private var phaseImage: String {
        switch progress.phase {
        case .discovering: "folder.badge.gearshape"
        case .indexing: "waveform.badge.magnifyingglass"
        case .artwork: "photo.stack"
        case .saving: "internaldrive"
        }
    }
}

private struct LibraryTrackRow: Identifiable {
    let track: Track
    let folderName: String
    var id: Track.ID { track.id }
}

@MainActor
private final class ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()

    private let images = NSCache<NSString, NSImage>()

    private init() {
        images.countLimit = 2_000
        images.totalCostLimit = 16 * 1_024 * 1_024
    }

    func image(data: Data, key: String) -> NSImage? {
        guard !data.isEmpty else { return nil }
        let key = NSString(string: key)
        if let cached = images.object(forKey: key) { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 68,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: thumbnail, size: NSSize(width: 34, height: 34))
        images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}

private struct LibraryArtworkView: View {
    let track: Track
    @Bindable var session: AppSession
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "questionmark")
                    .accessibilityLabel(Text("library.artworkUnknown"))
                    .help("library.artworkUnknown")
            }
        }
        .frame(width: 34, height: 34)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: track.metadata.artworkCacheKey) {
            guard let data = await session.loadArtworkData(for: track.id) else {
                image = nil
                return
            }
            image = ArtworkThumbnailCache.shared.image(
                data: data,
                key: track.metadata.artworkCacheKey ?? track.contentFingerprint
            )
        }
    }
}

private enum LibraryBrowseMode: String, CaseIterable, Identifiable {
    case songs, albums, artists, folders, favorites
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .songs: "library.browse.songs"
        case .albums: "library.browse.albums"
        case .artists: "library.browse.artists"
        case .folders: "library.browse.folders"
        case .favorites: "library.browse.favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .folders: "folder"
        case .favorites: "heart"
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

private struct CalendarView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if session.calendarSnapshot.events.isEmpty {
                ContentUnavailableView {
                    Label("sidebar.calendar", systemImage: "calendar")
                } description: {
                    Text(calendarDescription)
                } actions: {
                    if !isConnected {
                        VStack(spacing: 8) {
                            Button(
                                session.calendarConnectionState == .connecting ? "calendar.cancelConnect" : "calendar.connect",
                                systemImage: session.calendarConnectionState == .connecting ? "xmark.circle" : "person.crop.circle.badge.plus"
                            ) {
                                Task {
                                    if session.calendarConnectionState == .connecting {
                                        await session.cancelGoogleConnection()
                                    } else {
                                        await session.connectGoogleCalendar()
                                    }
                                }
                            }
                            .disabled(!session.isGoogleCalendarConfigured)
                            if !session.isGoogleCalendarConfigured {
                                Text("calendar.configurationRequired")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
            } else {
                List {
                    ForEach(groupedDays, id: \.self) { day in
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(events(on: day)) { event in
                                CalendarEventRow(event: event)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("sidebar.calendar")
        .toolbar {
            ToolbarItemGroup {
                if session.calendarConnectionState == .syncing || session.calendarConnectionState == .connecting {
                    ProgressView().controlSize(.small)
                }
                Button("calendar.refresh", systemImage: "arrow.clockwise") {
                    Task { await session.syncCalendar(forceFull: true) }
                }
                .disabled(!isConnected || session.calendarConnectionState == .syncing)
                if isConnected, !session.calendarSnapshot.calendars.isEmpty {
                    Menu("calendar.chooseCalendars", systemImage: "calendar.badge.checkmark") {
                        ForEach(session.calendarSnapshot.calendars) { calendar in
                            Button {
                                Task { await session.toggleCalendarSelection(calendar.id) }
                            } label: {
                                Label(
                                    calendar.title,
                                    systemImage: session.selectedCalendarIDs.contains(calendar.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .disabled(
                                session.selectedCalendarIDs.contains(calendar.id)
                                    && session.selectedCalendarIDs.count == 1
                            )
                        }
                    }
                    .disabled(session.calendarConnectionState == .syncing)
                }
                if isConnected {
                    Button("calendar.disconnect", systemImage: "person.crop.circle.badge.minus") {
                        Task { await session.disconnectGoogleCalendar() }
                    }
                } else if session.calendarConnectionState == .connecting {
                    Button("calendar.cancelConnect", systemImage: "xmark.circle") {
                        Task { await session.cancelGoogleConnection() }
                    }
                } else {
                    Button("calendar.connect", systemImage: "person.crop.circle.badge.plus") {
                        Task { await session.connectGoogleCalendar() }
                    }
                    .disabled(!session.isGoogleCalendarConfigured || session.calendarConnectionState == .connecting)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.calendarError != nil || session.calendarSnapshot.lastSuccessfulSync != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let error = session.calendarError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        if let lastSync = session.calendarSnapshot.lastSuccessfulSync {
                            Label(lastSyncLabel(lastSync), systemImage: "clock")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if session.calendarError != nil,
                       session.calendarSnapshot.lastSuccessfulSync != nil {
                        Text("calendar.offlineCache")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
    }

    private var isConnected: Bool {
        session.calendarConnectionState == .connected
            || session.calendarConnectionState == .syncing
    }

    private var calendarDescription: LocalizedStringKey {
        if !session.isGoogleCalendarConfigured { return "calendar.notConfigured" }
        if session.calendarConnectionState == .connecting { return "calendar.connecting" }
        if isConnected { return "calendar.noUpcomingEvents" }
        return "placeholder.calendar"
    }

    private func lastSyncLabel(_ date: Date) -> String {
        String(
            format: String(localized: "calendar.lastSync"),
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private var groupedDays: [Date] {
        let calendar = Calendar.current
        return Set(session.calendarSnapshot.events.map { calendar.startOfDay(for: $0.start) }).sorted()
    }

    private func events(on day: Date) -> [CalendarEvent] {
        session.calendarSnapshot.events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.isAllDay ? String(localized: "calendar.allDay") : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                if !event.isAllDay {
                    Text(event.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let allDayRange {
                    Text(allDayRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title.isEmpty ? String(localized: "calendar.untitled") : event.title)
                    .font(.headline)
                if let organizer = event.organizer {
                    Label(organizer, systemImage: "person")
                }
                if let calendarTitle = event.calendarTitle {
                    Label(calendarTitle, systemImage: "calendar")
                }
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                Label(attendanceLabel, systemImage: attendanceImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 7) {
                if let meetURL = event.meetURL {
                    Link(destination: meetURL) {
                        Label("calendar.joinMeet", systemImage: "video.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let calendarURL = event.calendarURL {
                    Link("calendar.openInGoogle", destination: calendarURL)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var attendanceLabel: LocalizedStringKey {
        switch event.attendanceStatus {
        case .accepted: "calendar.attendance.accepted"
        case .declined: "calendar.attendance.declined"
        case .tentative: "calendar.attendance.tentative"
        case .needsAction: "calendar.attendance.needsAction"
        case .unknown: "calendar.attendance.unknown"
        }
    }

    private var attendanceImage: String {
        switch event.attendanceStatus {
        case .accepted: "checkmark.circle"
        case .declined: "xmark.circle"
        case .tentative: "questionmark.circle"
        case .needsAction, .unknown: "circle.dashed"
        }
    }

    private var allDayRange: String? {
        let calendar = Calendar.current
        guard let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: event.end),
              !calendar.isDate(event.start, inSameDayAs: inclusiveEnd)
        else { return nil }
        return "\(event.start.formatted(date: .abbreviated, time: .omitted)) - \(inclusiveEnd.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct LockTuneBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.24, green: 0.37, blue: 0.82))
            Circle().fill(Color(red: 1, green: 0.39, blue: 0.39)).frame(width: 23, height: 23).offset(x: 10, y: -10)
            Circle().fill(Color(red: 0.93, green: 0.79, blue: 0.58)).frame(width: 17, height: 17).offset(x: -11, y: 12)
        }.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct CompactCalendarPanel: View {
    @Bindable var session: AppSession

    private var events: [CalendarEvent] { Array(session.upcomingTimedEvents.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide))).foregroundStyle(.secondary)
                Text(Calendar.current.component(.day, from: .now).formatted()).font(.system(size: 40, weight: .bold, design: .rounded))
                Text(Date.now.formatted(.dateTime.month(.abbreviated))).foregroundStyle(.secondary)
            }.padding(.top, 35)
            Text("接下来的日程").font(.callout).foregroundStyle(.secondary).padding(.top, 33).padding(.bottom, 15)
            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: session.calendarConnectionState == .connected ? "calendar.badge.checkmark" : "calendar.badge.plus").font(.title2).foregroundStyle(.secondary)
                    Text(session.calendarConnectionState == .connected ? "今天没有更多日程" : "连接 Google 日历").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 35)
            } else {
                VStack(spacing: 11) {
                    ForEach(events) { event in
                        HStack(spacing: 12) {
                            Text(event.start.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 4, height: 37)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title.isEmpty ? "未命名日程" : event.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(event.meetURL == nil ? (event.location ?? "日历") : "Google Meet").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if let url = event.meetURL { Link(destination: url) { Image(systemName: "video.fill") }.buttonStyle(.plain) }
                        }.padding(.horizontal, 13).frame(height: 74).background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
            Spacer()
            Text(session.calendarConnectionState == .connected ? "Google 日历已同步" : "Google 日历未连接").font(.caption).foregroundStyle(.secondary).padding(.bottom, 25)
        }.padding(.horizontal, 23).background(Color(red: 0.94, green: 0.946, blue: 0.962))
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case nowPlaying

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .library: "sidebar.library"
        case .nowPlaying: "sidebar.nowPlaying"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "music.note.list"
        case .nowPlaying: "play.circle"
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

                Button("player.shuffle", systemImage: "shuffle") {
                    Task {
                        await session.setPlaybackOrder(
                            session.playback.order == .shuffled ? .sequential : .shuffled
                        )
                    }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(session.playback.order == .shuffled ? Color.accentColor : Color.secondary)
                .disabled(session.playback.queue.count < 2)

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

                Button(repeatLabel, systemImage: repeatImage) {
                    Task { await session.setRepeatMode(nextRepeatMode) }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(session.playback.repeatMode == .off ? Color.secondary : Color.accentColor)
                .disabled(session.playback.queue.isEmpty)

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
        session.playback.currentItem != nil && [.idle, .playing, .paused].contains(session.playback.phase)
    }

    private var nextRepeatMode: PlaybackRepeatMode {
        switch session.playback.repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    private var repeatImage: String {
        session.playback.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatLabel: LocalizedStringKey {
        switch session.playback.repeatMode {
        case .off: "player.repeat.off"
        case .all: "player.repeat.all"
        case .one: "player.repeat.one"
        }
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
