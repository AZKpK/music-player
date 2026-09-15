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
3. Recording hook: `_lastKnownPosition` mechanism from step 1 feeding
   `_handleCurrentIndexChanged` for normal transitions, *plus* the
   backward-jump detection from the second spike for `LoopMode.one`
   repeats, + tests for both paths.
4. `wrap_stats_service.dart` (`isCountedPlay`, `computeWrapStats`) + unit
   tests — pure, testable before anything else exists.
5. `wrap_playlist_service.dart` (generation + collision suffixing) + unit
   tests.
6. `wrap_providers.dart` — wire DB + stats + playlist service together.
7. UI: `library_screen.dart` menu swap, then `wrap_screen.dart` (add
   `fl_chart` to `pubspec.yaml` at this point, not earlier).
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
- Step 8: `flutter analyze` clean, `flutter test` all green, `flutter build
  apk --debug` succeeds — same three-command gate used for prior features
  (e.g. the P0/N5 queue-window work).
- End-to-end (after step 7): play a few songs (including a skip before 50%,
  and a `LoopMode.one` loop), open the Wrap menu entry, confirm top
  songs/artists/albums, total minutes, and (genre toggle on) top genre
  render correctly, and that both generated playlists (`Wrap <year>`,
  `Wrap All-Time`) show the expected songs.
