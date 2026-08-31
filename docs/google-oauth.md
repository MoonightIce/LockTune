# Google OAuth configuration

LockTune uses Google's installed Desktop app flow with PKCE and a callback on an
ephemeral `127.0.0.1` port. Google currently requires the Desktop OAuth client
secret during token exchange. Desktop app secrets cannot be kept confidential
from a distributed binary, so LockTune manages it as release configuration and
never commits it to the repository.

## Release builds

The LockTune maintainers create one Desktop OAuth client in the LockTune Google
Cloud project, enable the Google Calendar API, configure the OAuth consent
screen, and inject the client ID and client secret into the
`LOCKTUNE_GOOGLE_CLIENT_ID` and `LOCKTUNE_GOOGLE_CLIENT_SECRET` Xcode build
settings in the release workflow. The repository intentionally keeps both
values empty.

The requested scopes are read-only:

- `https://www.googleapis.com/auth/calendar.events.readonly`
- `https://www.googleapis.com/auth/calendar.calendarlist.readonly`

## Contributor builds

Contributors can create their own Google Desktop OAuth client and set both
credential build-setting overrides. For example:

    scripts/build-app.sh Debug \
      LOCKTUNE_GOOGLE_CLIENT_ID='example.apps.googleusercontent.com' \
      LOCKTUNE_GOOGLE_CLIENT_SECRET='example-client-secret'

Do not commit account tokens or generated credentials. OAuth tokens are stored
only in the user's Keychain; calendar events are held in a rebuildable local
cache.
