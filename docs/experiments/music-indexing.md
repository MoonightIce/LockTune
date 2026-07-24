# Music indexing experiment

## Scope

NAN-156 implements a read-only, rebuildable local index for MP3, AAC/M4A,
ALAC-in-M4A, FLAC, WAV, and APE. It does not implement playback or modify music
files.

## Implementation

- Recursively discovers supported files in user-selected folders.
- Streams SHA-256 fingerprints in 1 MiB chunks and deduplicates exact content.
- Models a logical Track separately from one or more TrackLocation values.
- Reuses unchanged locations by size and modification date during incremental
  scans, and removes stale locations under rescanned roots.
- Uses AVFoundation for system-supported metadata and a LockTune-owned parser
  for APE headers and APEv2 tags.
- Persists the rebuildable index with SwiftData and artwork bytes in the cache
  directory.
- Stores selected folders as read-only, app-scoped security bookmarks.
- Reports unsupported, unreadable, and metadata-unavailable files without
  failing the whole scan.

## Automated evidence

The private acceptance corpus exercised MP3, M4A, FLAC, and APE. A full scan
followed by an incremental scan completed successfully, produced the same Track
and TrackLocation identifiers on the second pass, and matched an independent
count of supported files. Synthetic APE fixtures cover APEv2 text, artwork,
track number, modern duration, and older 3.8x/3.9x duration rules.

The corpus path, filenames, and extracted metadata are intentionally excluded
from source control and logs.

## Maintainer acceptance checklist

Use an ad-hoc signed Debug or Release build. This final system interaction is
manual because choosing a folder grants persistent filesystem access.

1. Launch LockTune and choose Add Music Folder.
2. Select the private music folder and confirm the library populates.
3. Verify representative MP3, M4A, FLAC, and APE rows, artwork, durations, and
   explicit issue counts.
4. Quit LockTune completely and reopen it.
5. Confirm the folder and index restore without another picker prompt.
6. Add, change, and remove disposable copies of files, then refresh and confirm
   the index changes while source files remain untouched.

Do not use irreplaceable originals for step 6.

## Known boundary

Creating a real app-scoped bookmark from an unsigned Swift test process can
fail because it does not have the app's signed sandbox identity. Bookmark
serialization, stale refresh, persistence, and removal are covered through an
injectable boundary; the signed-app restart path is the remaining manual gate.
