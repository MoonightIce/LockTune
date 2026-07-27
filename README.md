# LockTune

LockTune is an open-source, local-first macOS companion that combines a local
music player with a notch-style information surface for music and upcoming
Google Calendar meetings.

The repository is in active MVP development. Local music indexing and playback,
APE decoding, search, favorites, persistent queue modes, system Now Playing,
Google Calendar/Meet, and the island window are implemented. A real Google
account flow still requires LockTune's release Desktop OAuth Client ID to be
configured in the build.

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
- Sources/LockTuneInfrastructure: playback, metadata, persistence, artwork
  cache, system Now Playing, and security-scoped folder access
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

Google Calendar setup for release and contributor builds is documented in
`docs/google-oauth.md`.

The first preview releases will be ad-hoc signed and not notarized. Stable
signed releases are deferred until the project has a paid Apple Developer
account.

## Local acceptance music

The maintainer may opt into a private local music directory for acceptance
testing in read-only mode. Its path and contents are never committed, uploaded,
logged, or used by CI.

## License

MIT. APE playback uses the pinned 3-clause BSD CXXMonkeysAudio package. See
`THIRD_PARTY_NOTICES.md` for the complete notice and revision.
