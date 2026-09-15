  Highest-impact improvements:

  - Avoid rebuilding the entire player screen on each position tick. PlayerScreen.build watches
    playbackPositionProvider, so its full Scaffold, artwork, title, controls, and app bar rebuild repeatedly during
    playback. Move that watch into _SeekBar only; the mini player already follows this better split. lib/features/
    player/player_screen.dart:69, lib/features/player/mini_player.dart:104

  - Debounce and isolate library search/sorting. Every typed character filters every song, lowercases up to three
    fields per song, creates a new list, then clones and sorts it. Additionally, LibraryScreen watches the result
    solely for the play button, rebuilding its tab layout. Add a ~200–300 ms debounce, precompute normalized search
    fields for large libraries, and make only the active list/play action watch the filtered result. lib/core/
    services/media_library_providers.dart:165, lib/features/library/library_screen.dart:46

  - Deduplicate artwork fetches and bound its cache. Artwork work is fire-and-forget from several state paths;
    concurrent calls for the same track can race into repeated MediaStore reads/writes. Add an in-flight Map<String,
    Future<Uri?>>, remove flush: true unless durability is required, and age/size-limit <temp>/artwork_cache. lib/
    core/services/audio_player_service.dart:596, lib/core/services/media_library_service.dart:60

  - Downsample manually selected cover files. Image.file decodes source-sized images even when rendering 48 px tiles.
    Pass cacheWidth/cacheHeight derived from device pixel ratio; this reduces decode memory, raster load, and
    scrolling jank for high-resolution photos. MediaStore artwork is already requested at display size. lib/shared/
    widgets/song_artwork.dart:25, lib/shared/widgets/group_artwork.dart:35

  Medium-priority:

  - Queue shuffle/reorder has nested linear searches and sequential move calls; it is bounded at 250 entries, so it
    is not catastrophic, but shuffle toggles can still be noticeably slow. Maintain an ID→index map while reordering.
    lib/core/services/audio_player_service.dart:488

  - The sleep timer wakes once per second while active. Its cost is small, but a one-shot pause timer plus a
    foreground-only display ticker would be more battery-conscious. lib/core/services/sleep_timer_provider.dart:18

  - Playlist insertion executes a COUNT(*) before every insert; add a (playlistId, position) index and a bulk-insert
    path if bulk playlist editing is planned. lib/core/db/app_database.dart:123

  Clearly unnecessary or removable:

  - PlaylistsScreen is an unused wrapper; the app uses PlaylistsTab directly. lib/features/playlists/
    playlists_screen.dart:16

  - cupertino_icons, youtube_explode_dart, and fl_chart have no source usage. Remove them from pubspec.yaml unless
    they are deliberately reserved for future work. The icon font alone contributes about 257 KB to the universal
    APK. pubspec.yaml:22

  - The manual folder scanner is not dead—it is reachable from the library toolbar—but it is explicitly temporary/
    legacy. If MediaStore-only support is acceptable, remove LibraryTestScreen, library_scanner.dart, and then likely
    permission_handler. lib/features/library/library_screen.dart:117

  - Music/ contains 50 tracked MP3s, about 293 MB. They are not Flutter assets, so they do not inflate the APK, but
    they greatly slow cloning/history and bloat Git objects. If they are sample data, move them out of Git and use
    Git LFS or a download fixture.

  What is already good: MediaStore is fetched once through a cached provider, the queue is capped at 250 songs,
  artwork is mostly lazy-loaded, and list views use fixed item extents. Those choices avoid the biggest common music-
  player battery/performance mistakes.

  The release APK is ~56 MB because it bundles three CPU architectures. Ship an Android App Bundle or ABI-specific
  APKs for smaller downloads; this does not change runtime performance.