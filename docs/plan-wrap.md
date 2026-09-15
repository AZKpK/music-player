# Plan: Yearly Wrap

- **Spec:** docs/spec-wrap.md

## Files to change

- `lib/core/db/app_database.dart` — add `PlayHistoryEntries` + `WrapSettings`
  tables (schema fully specified in `spec-wrap.md`), bump `schemaVersion`
  4 → 5, add an additive `onUpgrade` branch (`if (from < 5)`) creating both
  tables — same pattern as the existing `from < 2`/`from < 3`/`from < 4`
  branches.
- `lib/core/db/app_database.g.dart` — regenerated via `build_runner`, never
  hand-edited.
- `lib/core/services/audio_player_service.dart` — `_handleCurrentIndexChanged`
  (line 629) currently does `mediaItem.add(queue.value[index])` first thing,
  overwriting the outgoing song. Record the play *before* that overwrite:
  capture `mediaItem.valueOrNull` (outgoing item) and `_player.position`
  (how far it got) prior to the `mediaItem.add` call, then insert one
  `PlayHistoryEntries` row.
- `lib/core/services/wrap_stats_service.dart` (new) — `isCountedPlay` and
  `computeWrapStats` pure functions, exactly as specified in `spec-wrap.md`.
  No Riverpod/DB imports, mirroring the existing `buildQueueWindow` style.
- `lib/features/wrap/wrap_playlist_service.dart` (new) — snapshot + all-time
  Top-100 playlist generation, using the existing `AppDatabase.createPlaylist`
  / `addSongToPlaylist` (`app_database.dart:119,134`) plus name-collision
  suffixing (check existing playlist names before creating).
- `lib/features/wrap/wrap_screen.dart` (new, replaces the empty
  `lib/features/wrap/.gitkeep` scaffold) — top artists/albums/songs, total
  minutes, genre toggle + top genre, links to the two generated playlists.
- `lib/features/wrap/wrap_providers.dart` (new) — Riverpod wiring: watches
  `PlayHistoryEntries` for the current wrap year, joins against
  `librarySongsProvider`/`SongOverrides` for metadata (same genre fallback
  already used in `media_library_providers.dart`), exposes `WrapSettings`
  read/update.
- `lib/features/library/library_screen.dart` — replace the
  `Icons.snippet_folder_outlined` `IconButton` (lines 160–168) with an
  `AppSelectMenu<LibraryMenuAction>` (same `value: null` one-shot pattern as
  `_PlayLibraryButton`, line 206): Settings (snackbar "Kmalu na voljo"), Play
  from a folder (existing `LibraryTestScreen` push, unchanged), Wrap (push
  `WrapScreen`).
- `pubspec.yaml` — add `fl_chart` dependency (not present today).
- `test/wrap_stats_service_test.dart` (new) — `isCountedPlay` edge cases,
  `computeWrapStats` cases (empty, single, ties, missing library entries,
  genre on/off).
- `test/wrap_playlist_service_test.dart` (new) — name-collision suffixing (no
  collision / one / multiple), via `AppDatabase.forTesting` (in-memory).
- `test/audio_player_service_test.dart` — add cases for play recording on
  song transition, including `LoopMode.one` repeats each writing their own
  row (no dedup).

## Order of work

1. **Spike (first) — DONE:** confirmed on-device (two manual skips, logcat)
   that `_player.position` read synchronously inside
   `_handleCurrentIndexChanged` reflects the *incoming* track (~0ms), not
   the outgoing one — the naive synchronous read doesn't work. Corrected
   mechanism (continuously-tracked `_lastKnownPosition` via
   `positionStream`, captured before the transition overwrites the current
   item) written back into `spec-wrap.md`. `kUseDurationPercentThreshold`
   still ships `true` (50% rule) — the threshold choice was independent of
   the capture-mechanism bug.

   **Second spike — DONE:** confirmed on-device (seek-to-end under
   `LoopMode.one`, timestamped logcat) that a loop-one repeat fires *no*
   stream event at all (`processingStateStream` never emits `completed`,
   `currentIndexStream` never fires) — just_audio loops silently. Corrected
   mechanism (detect a backward jump in `positionStream` while
   `LoopMode.one` is active, treat it as a completed play of the looped
   track) written back into `spec-wrap.md`.
2. DB schema: add both tables + migration, regenerate `app_database.g.dart`.
3. **Recording hook — DONE:** `_lastKnownPosition` (updated from
   `positionStream`) feeds `_handleCurrentIndexChanged` for normal
   transitions, `_handleCompleted` for natural queue-end, and a
   backward-jump check in `positionStream` for `LoopMode.one` repeats — all
   three routed through one `_recordPlay` helper (`AppDatabase.recordPlay`).
   Extended beyond the plan's literal text to also cover a fourth case found
   while reading `loadQueue`: replacing the whole queue mid-song (the
   existing `mediaItem.add` pre-publish there means `_handleCurrentIndexChanged`
   alone would silently lose that play) — `loadQueue` now records the
   outgoing song itself before rebuilding the queue.

   **On-device smoke test caught a real bug**, not just confirmed the
   design: `positionStream` fires a ~0 position event for the *next* track
   before `currentIndexStream` fires, so the original
   `_handlePositionChanged` (which unconditionally updated
   `_lastKnownPosition`) stomped it to 0 right before
   `_handleCurrentIndexChanged` could record it — every transition-recorded
   play had `msListened = 0`. Fixed by extracting the loop-one backward-jump
   check into a shared `isBackwardJumpToStart` (repeat-mode-agnostic) and
   having `_handlePositionChanged` skip updating `_lastKnownPosition` on any
   such jump that isn't the loop-one case, leaving it for
   `_handleCurrentIndexChanged` to consume and reset. Re-verified on-device
   afterward: skipping "Battle Born" → "Mr. Brightside" wrote
   `msListened = 18157` (real elapsed ms) instead of `0`. Unit tests
   (`isRealSongTransition`, `isLoopOneRepeat`, `isBackwardJumpToStart`,
   `buildPlayHistoryEntry`) cover the pure logic; the stream-ordering bug
   itself only surfaced on-device, since it's about event ordering between
   two listeners, not something a pure-function unit test exercises.
4. **`wrap_stats_service.dart` — DONE:** `isCountedPlay` (50% threshold) and
   `computeWrapStats` (top songs/artists/albums, unfiltered total minutes,
   optional top genre), ranked with a count-desc/name-asc tiebreak for
   deterministic ordering. Returns full sorted lists rather than a fixed
   top-N — the spec only specifies N=100 for the two generated playlists,
   not for the on-screen lists, so the UI (step 7) slices as needed. Missing
   `libraryById` entries (deleted songs) still count toward total minutes
   but not toward any ranking, since `PlayHistoryEntries` has no
   artist/album/genre of its own to fall back on.
5. **`wrap_playlist_service.dart` — DONE:** `generateYearlySnapshotPlaylist`
   (suffixes on name collision, per spec) and `generateAllTimePlaylist`
   (deletes + recreates any existing same-named playlist instead of
   suffixing), both built on the existing `createPlaylist`/
   `addSongToPlaylist`. Added two small `AppDatabase` helpers
   (`allPlaylistNames`, `findPlaylistByName`) needed for the collision
   check/lookup — not schema changes, just queries. `resolvePlaylistName`
   is a standalone pure function so the suffixing logic itself doesn't need
   a DB in tests.

   **Environment note:** `wrap_playlist_service_test.dart` is the first
   test in this repo to actually execute real Drift queries (not just
   construct `AppDatabase.forTesting`) — this surfaced that the dev
   sandbox's `libsqlite3-0` package doesn't provide the unversioned
   `libsqlite3.so` symlink `package:sqlite3`'s FFI loader looks for
   (`libsqlite3.so.0` exists, `libsqlite3.so` doesn't). Worked around
   locally via a scratchpad symlink + `LD_LIBRARY_PATH` for this session;
   not a code change, but worth installing `libsqlite3-dev` (provides the
   symlink) on this machine so future `flutter test` runs don't need the
   workaround.
6. **`wrap_providers.dart` — DONE:** `wrapSettingsProvider` (`StreamProvider<WrapSetting?>`,
   `null` until a row exists — every downstream provider then falls back to
   the table defaults, per spec), `wrapPeriodBoundsProvider` (current/
   previous period start from `resetMonth`/`resetDay`, via new pure
   `mostRecentWrapBoundary`/`computeWrapPeriodBounds` in
   `wrap_stats_service.dart`), `currentPeriodPlayHistoryProvider` (live,
   read-only — per spec's "opening the wrap screen ... displays live
   current-period stats"), `wrapStatsProvider` joining that against
   `librarySongsProvider`, and a `WrapPlaylistGenerator` controller
   (`regenerateIfDue`, mirroring the existing `SongLikesController` pattern)
   that regenerates both playlists only when `WrapSettings.lastGeneratedAt`
   predates the current period's start, then stamps
   `lastGeneratedAt = DateTime.now()`. Added three small `AppDatabase`
   methods needed to back this (`watchWrapSettings`, `updateWrapSettings`,
   `markWrapPlaylistsGenerated`, plus `watchPlayHistoryEntries({from, to})`)
   — same delta-companion upsert pattern as `upsertOverride`, not schema
   changes. No dedicated test file for this step, consistent with
   `playlist_providers.dart`/`media_library_providers.dart` (thin reactive
   wiring, not pure logic) — the boundary math it depends on
   (`mostRecentWrapBoundary`, `computeWrapPeriodBounds`) is pure and is
   covered directly in `wrap_stats_service_test.dart` instead.
7. **UI — DONE:** `library_screen.dart`'s folder-scan `IconButton` replaced
   with `AppSelectMenu<LibraryMenuAction>` (Settings snackbar / Play from a
   folder / Wrap), exactly the 3-option menu from spec. `wrap_screen.dart`
   (new): total minutes card, genre toggle (writes straight to
   `AppDatabase.updateWrapSettings`, same direct-DB-call pattern already used
   elsewhere in the UI layer, e.g. `playlists_screen.dart`), a small
   `fl_chart` `BarChart` of the top 5 songs, full ranked lists for top
   songs/artists/albums, and two playlist links (`Wrap <previous year>`,
   `Wrap All-Time`) resolved by name from `playlistsProvider` — disabled with
   "Še ni na voljo" if that playlist doesn't exist yet (e.g. no play history).
   Triggers `WrapPlaylistGenerator.regenerateIfDue()` once in `initState`
   (fire-and-forget; genuinely a no-op unless the reset-date boundary was
   actually crossed). `fl_chart: ^0.69.2` added to `pubspec.yaml`,
   `flutter pub get` resolved cleanly.
8. Full gate: `flutter analyze`, `flutter test`, `flutter build apk --debug`.

Each numbered step is its own commit (code + its tests together).

## Risks

- ~~Spike could go either way~~ — resolved: synchronous `_player.position`
  read doesn't work, corrected to a continuously-tracked `_lastKnownPosition`
  field (see `spec-wrap.md`). No change to the 50%/60s threshold decision
  itself.
- ~~LoopMode.one repeats might not surface a distinct event~~ — resolved:
  confirmed no stream event fires at all for a loop-one repeat; corrected to
  a backward-jump detection in `positionStream` (see `spec-wrap.md`).
- Migration is additive-only (two new tables) — no risk to existing
  playlist/override data.
- `fl_chart` is a new dependency — confirm `flutter pub get` resolves
  cleanly before relying on it.
- Playlist name collisions — edge case, only exercised by tests; the suffix
  logic is the main place a bug could hide.
- Genre resolution correctness — reuses the exact existing fallback, but
  gets its own direct unit test rather than trusting the reuse blindly.

## Proof

- Step 3: new `audio_player_service_test.dart` cases pass, including the
  `LoopMode.one` no-dedup case.
- Step 4: `wrap_stats_service_test.dart` covers every case in the spec's
  Testing strategy section.
- Step 5: `wrap_playlist_service_test.dart` covers 0/1/many name collisions.
- Step 6: `wrap_stats_service_test.dart` covers `mostRecentWrapBoundary`/
  `computeWrapPeriodBounds` (calendar-year default, exact-boundary edge,
  before-reset-date fallback to last year); the Riverpod wiring itself is
  exercised end-to-end in the step 7 manual verification below (no dedicated
  provider test file, matching existing `*_providers.dart` convention).
- Step 8: `flutter analyze` clean, `flutter test` all green, `flutter build
  apk --debug` succeeds — same three-command gate used for prior features
  (e.g. the P0/N5 queue-window work).
- End-to-end (after step 7): play a few songs (including a skip before 50%,
  and a `LoopMode.one` loop), open the Wrap menu entry, confirm top
  songs/artists/albums, total minutes, and (genre toggle on) top genre
  render correctly, and that both generated playlists (`Wrap <year>`,
  `Wrap All-Time`) show the expected songs.
