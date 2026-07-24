# LockTune

LockTune is an open-source, local-first macOS companion that combines a local
music player with a notch-style information surface for music and upcoming
Google Calendar meetings.

The repository is in its engineering-foundation phase. The app shell and the
first tested island-priority seam exist; audio playback, file indexing, system
Now Playing, and Google Calendar are tracked work, not completed features.

## Product boundaries

- macOS 14 Sonoma or later
- Universal app architecture: Apple Silicon and Intel
- Local music works without any account
- Google Calendar is optional and read-only
- Music files stay in place and are read-only in the MVP
- The system Now Playing surface is the supported lock-screen integration
- No analytics or automatic crash upload
- GitHub Releases first; Mac App Store later

## Repository structure

- App: SwiftUI application shell, menu bar entry, entitlements, localization
- Sources/LockTuneDomain: shared domain values
- Sources/LockTuneCore: dependency-light application rules
- Tests: public-seam tests for core behavior
- docs: product, architecture, and agent guidance

## Build

Requirements:

- Xcode 26 or a compatible Xcode with the macOS 14 SDK
- Swift 6

Run core tests:

    swift test

Build the application without distribution signing:

    xcodebuild -project LockTune.xcodeproj -scheme LockTune \
      -configuration Debug -destination 'platform=macOS' \
      CODE_SIGNING_ALLOWED=NO build

The first preview releases will be ad-hoc signed and not notarized. Stable
signed releases are deferred until the project has a paid Apple Developer
account.

## Local acceptance music

The maintainer may test against /Users/admin/Documents/Music in read-only mode.
That directory and its contents are never committed, uploaded, logged, or used
by CI.

## License

MIT. Third-party audio components will retain their own notices and license
requirements.
