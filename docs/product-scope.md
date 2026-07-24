# Product scope

## Positioning

LockTune is a local-first Mac information companion. Music and calendar are
compile-time modules presented through a shared app shell and island surface.
It is not a music player with an unrelated calendar widget, and it is not a
runtime third-party plugin host.

## MVP

Music:

- Index user-selected folders in place
- MP3, AAC/M4A, ALAC, FLAC, WAV, and APE
- Songs, albums, artists, and folders
- Search, favorites, persistent queue, shuffle, and repeat
- System Now Playing metadata, artwork, progress, and media commands

Calendar:

- One optional Google account
- Multiple selected calendars
- Calendar read-only OAuth scope
- Event title, time, organizer, attendance state, location, and Meet link
- Incremental polling, offline cache, and optional local notifications

Presentation:

- One main window
- One menu bar control surface
- Notch-attached island on supported built-in displays
- Top-center floating capsule elsewhere
- System Now Playing is the supported lock-screen surface

## Explicitly deferred

- Runtime third-party plugins
- DSD, CUE, exclusive audio output, EQ, and audio plugins
- Metadata writing UI
- Multiple Google accounts
- Meeting recording, transcripts, chat, summaries, or automatic joining
- Automatic cover downloads
- Business backend and cross-device sync
- Mac App Store distribution and notarized stable releases
