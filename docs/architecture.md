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
    ├── SystemAudioMetadataReader
    ├── APEMetadataParser
    ├── GoogleCalendarREST
    ├── Keychain
    ├── SwiftData stores
    └── Security-scoped file access

The MVP is a single process. Swift Concurrency actors isolate scanning,
playback orchestration, and calendar synchronization. MainActor observable
models adapt those services to SwiftUI.

## Audio boundary

Indexing depends on a LockTune-owned AudioMetadataReading protocol. AVFoundation
reads metadata for system-supported files and a small LockTune-owned parser
reads APE headers and APEv2 tags. No third-party codec is required for indexing.

Playback depends on a separate LockTune-owned AudioEngine protocol. System
formats use AVFAudio. APE playback uses a minimal C++ bridge to CXXMonkeysAudio,
pinned to commit `a33138a7bff0ef65dfa67f2a25463e201d7dff64`. The dependency is
3-clause BSD licensed and its complete notice is preserved in
`THIRD_PARTY_NOTICES.md`. No SFBAudioEngine binary or LGPL codec is linked.

PlaybackController owns queue transitions and publishes immutable snapshots to
the UI. SystemAudioEngine creates its AVAudioEngine graph only when playback
starts, so indexing and decode validation do not require an active output
device. Security-scoped folder access stays active for the app session so a
track remains readable after scanning and across window, lock, and wake events.

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

Favorites, calendar selection, and island preferences use local defaults.
Queue state is an atomically written JSON document in Application Support.

MusicIndex, rebuildable:

- Tracks, locations, albums, artists, scan state, artwork cache keys

CalendarCache, rebuildable:

- Recent events, sync cursor, last successful synchronization

OAuth tokens live only in Keychain. Artwork bytes live in the cache directory,
not SwiftData. Music folder access uses security-scoped bookmarks.

## Google Calendar

A loopback listener bound only to `127.0.0.1` receives the Desktop OAuth
callback, and PKCE plus a per-request state value protect the authorization
code flow. LockTune supplies release Desktop OAuth client credentials and
contributors may override them locally. Google requires the
Desktop client secret during token exchange, but distributed desktop secrets
are not confidential; LockTune never treats that value as an authentication
boundary or commits a real value. URLSession calls the Calendar REST API
directly with read-only event and calendar-list scopes. The app synchronizes on
launch, wake, account connection, and approximately every five minutes while
running. The initial one-day-history/fourteen-day-ahead window is paginated;
later polls use per-calendar update cursors and merge changed or cancelled
events into the offline cache.

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

## IslandPresentation Liquid Glass experiment

The supported product behavior remains based on public macOS APIs. The
`IslandPresentation` Liquid Glass refraction experiment is an explicit,
isolated exception: on macOS 26 and later it may probe and dispatch the
undocumented `NSGlassEffectView` variant/lensing setters and install active
appearance overrides on the `IslandPanel` subclass only. No other window,
feature module, persistence path, or permission boundary may depend on these
selectors.

Runtime diagnostics must distinguish `complete private refraction` from
`public glass fallback` and `opaque accessibility fallback`. Missing selectors
are observable capability mismatches, not a successful full-refraction result.
The experiment is not App Store compatible by default; disabling private
refraction must leave music, calendar, Island content, and window lifecycle
usable through the public glass or older-system visual-effect fallback.
