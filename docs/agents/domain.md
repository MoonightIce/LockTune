# Domain language

- AppSession: the single application-lifecycle composition root
- AudioEngine: LockTune-owned playback interface
- Track: logical music-library item
- TrackLocation: one accessible encoded file for a track
- MusicIndex: rebuildable local-file index
- CalendarCache: rebuildable Google event cache
- IslandModule: compile-time feature that can propose island content
- IslandCoordinator: sole authority choosing active island content
- IslandPresentation: selected presentation category
- Imminent meeting: an event beginning within ten minutes
- System Now Playing: supported macOS lock-screen and media-control integration
- Experimental lock-screen visual: non-core feasibility work that cannot rely
  on private APIs
