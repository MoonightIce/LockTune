# Google OAuth configuration

LockTune uses Google's installed Desktop app flow with PKCE and a callback on an
ephemeral `127.0.0.1` port. A client secret is not embedded or required.

## Release builds

The LockTune maintainers create one Desktop OAuth client in the LockTune Google
Cloud project, enable the Google Calendar API, configure the OAuth consent
screen, and inject the client ID into the `LOCKTUNE_GOOGLE_CLIENT_ID` Xcode build
setting in the release workflow. The repository intentionally keeps this value
empty until that project-owned client exists.

The requested scopes are read-only:

- `https://www.googleapis.com/auth/calendar.events.readonly`
- `https://www.googleapis.com/auth/calendar.calendarlist.readonly`

## Contributor builds

Contributors can create their own Google Desktop OAuth client and set
`LOCKTUNE_GOOGLE_CLIENT_ID` as an Xcode build-setting override. For example:

    xcodebuild -project LockTune.xcodeproj -scheme LockTune \
      -configuration Debug -destination 'platform=macOS' \
      LOCKTUNE_GOOGLE_CLIENT_ID='example.apps.googleusercontent.com' build

Do not commit account tokens or generated credentials. OAuth tokens are stored
only in the user's Keychain; calendar events are held in a rebuildable local
cache.
