# Architecture

## Principles

- Modular monolith with compile-time feature modules
- Local music remains usable with no Google account or network
- Public macOS APIs only for supported product behavior
- User data persists; indexes and remote caches are rebuildable
- UI observes application state; it does not own playback or synchronization
- Permissions are requested only when the user invokes the related feature

## Module map

    LockTuneApp
    ├── AppShell
    ├── MusicFeature
    ├── CalendarFeature
    ├── IslandPresentation
    └── Settings

    LockTuneCore
    ├── Domain
    ├── MusicLibrary
    ├── Playback
    ├── CalendarIntegration
    └── Persistence

    Infrastructure
    ├── SFBAudioEngineAdapter
    ├── GoogleCalendarREST
    ├── Keychain
    ├── SwiftData stores
    └── Security-scoped file access

The MVP is a single process. Swift Concurrency actors isolate scanning,
playback orchestration, and calendar synchronization. MainActor observable
models adapt those services to SwiftUI.

## Audio boundary

Application code depends on a LockTune-owned AudioEngine protocol. The first
implementation will adapt SFBAudioEngine for APE and the other MVP formats.
SFBAudioEngine is the sole planned non-SPM dependency: source is pinned through
a git submodule and built into an XCFramework by a repository script.

Music files are indexed in place. A Track is a logical library item and a
TrackLocation represents an accessible file. Exact duplicate files may share a
Track; different encodings remain separate by default.

## Island arbitration

IslandCoordinator is the only component allowed to select active island
content. Feature modules publish state and never compete for the window
directly.

Confirmed behavior:

- Imminent meetings take priority over normal music playback
- Short user-triggered playback feedback may temporarily cover a meeting
- Normal playback takes priority over ordinary calendar events
- Expanded UI allows an explicit user-selected feature for that expansion
- Meetings never pause music or join automatically

## Persistence

UserData:

- Favorites, queue, preferences, calendar selection, island settings

MusicIndex, rebuildable:

- Tracks, locations, albums, artists, scan state, artwork cache keys

CalendarCache, rebuildable:

- Recent events, sync cursor, last successful synchronization

OAuth tokens live only in Keychain. Artwork bytes live in the cache directory,
not SwiftData. Music folder access uses security-scoped bookmarks.

## Google Calendar

ASWebAuthenticationSession performs OAuth with PKCE. LockTune supplies the
release Client ID and contributors may override it locally. URLSession calls
the Calendar REST API directly. The app synchronizes on launch, wake, account
connection, and approximately every five minutes while running. It caches one
day of history and fourteen days ahead.

## Privacy

The island hides when macOS locks. The lock screen receives music through
system Now Playing only; calendar titles, attendees, and links are never
published there. Logs exclude paths, track metadata, calendar content, Meet
links, and tokens. Diagnostic export is user initiated and redacted.

## Distribution

The application targets macOS 14 and both arm64 and x86_64. App Sandbox is
enabled from the start. Preview GitHub releases may be ad-hoc signed but are not
notarized. Automated updates and stable distribution signing are deferred until
a paid Apple Developer account is available.
