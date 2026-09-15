# Spec: Yearly Wrap

Derived from `docs/intent-wrap.md` (approved). This is the Design-stage
artifact — concrete enough to plan Build work from, but implementation
details (exact listener wiring, widget tree) are left to `plan.md` per
Build increment.

## Data model (drift)

Add to `lib/core/db/app_database.dart`, bump `schemaVersion` to 5.

```dart
/// One recorded play of a song. Deliberately thin — unlike `PlaylistSongs`,
/// which duplicates title/artist/album because MediaStore ids aren't a
/// stable long-term reference, play events are far more numerous than
/// playlist rows, so metadata is resolved by joining the current library
/// at read time instead of being copied per row.
@TableIndex(name: 'play_history_played_at', columns: {#playedAt})
class PlayHistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get msListened => integer()();
  // Captured at play time (not re-read from the library later), so the
  // "was this a countable play" rule stays correct even if a file is later
  // deleted/replaced.
  IntColumn get trackDurationMs => integer()();
}

/// Single-row table for wrap-related settings. Reuses drift (already a
/// dependency, already the pattern for local app state) instead of adding
/// `shared_preferences` for two small values.
class WrapSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get genreEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get resetMonth => integer().withDefault(const Constant(1))();
  IntColumn get resetDay => integer().withDefault(const Constant(1))();
  // Last time the yearly snapshot/all-time playlists were (re)generated -
  // compared against the reset-date boundary to decide whether opening the
  // wrap screen should trigger regeneration.
  DateTimeColumn get lastGeneratedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

`WrapSettings` always has exactly one row (`id = 0`), upserted like
`SongOverrides`/`GroupArtworks` already are.

## Recording a play

Hook into `AudioPlayerHandler` where song transitions already happen
(`_handleCurrentIndexChanged`), not a new polling mechanism. When the
current song changes (skip, natural completion, or queue change), record
the outgoing song's `msListened` (how far playback got, from
`_player.position`) and `trackDurationMs` as one `PlayHistoryEntries` row.
This reuses data the handler already tracks — no new background timers.

## Countable-play threshold (Build-stage spike gate)

Per `intent-wrap.md`, this is a technical decision, not a product one:

```dart
const kUseDurationPercentThreshold = true; // flip based on spike result

bool isCountedPlay(int msListened, int trackDurationMs) {
  if (kUseDurationPercentThreshold) {
    return trackDurationMs > 0 && msListened >= trackDurationMs * 0.5;
  }
  return msListened >= 60000;
}
```

Pure, testable function — same style as `buildQueueWindow`/`buildPlayOrder`.
**Total minutes listened is never gated by this** — it sums `msListened`
across all rows regardless of whether a row counts as a "play."

Spike (do first, before building aggregation): confirm `_player.position`
at transition time is a reliable enough proxy for "how far the user got"
(it already is used elsewhere in the handler, e.g. `insertNext`/
`clearQueue`, so this should be low-risk) — if so, ship with
`kUseDurationPercentThreshold = true`; otherwise `false`.

## Aggregation

Pure function(s) in a new `lib/core/services/wrap_stats_service.dart` (or
similar), mirroring the existing `buildQueueWindow`-style pattern — no
Riverpod/DB coupling in the logic itself, so it's unit-testable in
isolation:

```dart
WrapStats computeWrapStats({
  required List<PlayHistoryEntry> entries, // already filtered to one year
  required Map<String, Song> libraryById,   // for title/artist/album/genre lookup
});
```

Returns: top songs, top artists, top albums (all by countable-play count),
total minutes listened (unfiltered sum), and top genre (only computed if
`WrapSettings.genreEnabled`, resolving genre via
`SongOverrides.genre ?? mediaItem.genre`, same fallback already used in
`media_library_providers.dart`).

Songs whose id no longer resolves in `libraryById` (deleted file) are
still counted toward minutes/top-artist-by-name where possible, but
dropped from "top songs" (nothing to show/play).

## Top-100 playlists

Two playlists, built via the existing `Playlists`/`PlaylistSongs` tables
(reuse `createPlaylist`/`addSongToPlaylist` — no new schema needed here):
- **Yearly snapshot** — top 100 songs of the closed year, named `Wrap
  <year>`. Created once, never touched again after creation.
- **All-time** — top 100 songs across all history, named e.g. `Wrap
  All-Time`. Existing playlist (if any) is deleted and recreated (not
  incrementally updated) on each regeneration.

**Name collisions**: if `Wrap <year>` already exists when generation runs
(e.g. user duplicated/renamed a copy), suffix a counter: `Wrap <year> (1)`,
`Wrap <year> (2)`, etc. — check existing playlist names before creating.

**Trigger**: both playlists are only (re)generated when the wrap screen is
opened *and* `WrapSettings.lastGeneratedAt` is before the most recent
reset-date boundary — not on every visit. Opening the wrap screen at any
other time just reads/displays current stats live (cheap query, no writes).

## Genre toggle

Off by default (`WrapSettings.genreEnabled = false`). Lives as a switch on
the wrap screen itself (not in the settings menu, which stays a "coming
soon" placeholder for everything else). When off, the top-genre section is
hidden entirely rather than shown empty/disabled.

## UI

### Library page navigation menu
Replace the existing "Izberi mapo ročno (folder-scan)" `IconButton`
(`library_screen.dart`) with an `AppSelectMenu<LibraryMenuAction>` (reuses
the existing action-menu pattern already used by `_PlayLibraryButton` —
`value: null`, each option is a one-shot action, not a persistent
selection), in order:
1. Settings — `SnackBar` "Kmalu na voljo" ("Coming soon"), no navigation.
2. Play from a folder — existing `LibraryTestScreen` navigation, unchanged
   behavior, just relocated.
3. Wrap — navigates to new `lib/features/wrap/wrap_screen.dart`.

### Wrap screen (`lib/features/wrap/`)
New feature folder (already scaffolded as empty in `docs/faze.md`). Shows,
for the current wrap year (based on `WrapSettings` reset date):
top artists/albums/songs lists, total minutes listened, genre toggle +
(when on) top genre, and a way to open the two generated playlists.
`fl_chart` (not yet a dependency — needs adding to `pubspec.yaml`) for any
bar/ranking visualizations, consistent with the originally planned stack in
`docs/plan1.1.md`.

## Storage (carried from intent, unchanged)
`PlayHistoryEntries` avoids text duplication; estimated ~1–1.5 MB/year for
a heavy listener. Retention/pruning (collapsing rows older than ~5 years
into per-song yearly aggregates) is **not implemented in this pass** —
noted as future work if DB size ever becomes a real concern.

## Testing strategy
Following existing conventions (`audio_player_service_test.dart` style,
pure-function unit tests over widget tests where possible):
- `isCountedPlay`: edge cases at exactly 50%/60s, zero-duration track,
  `msListened > trackDurationMs`.
- Recording: `LoopMode.one` repeats each produce their own
  `PlayHistoryEntries` row (no dedup/collapsing of rapid repeats).
- `computeWrapStats`: empty history, single song, ties in top-N ranking,
  missing library entries (deleted songs), genre on/off.
- Playlist name-collision suffixing: no collision, one collision, multiple.
- Standard gate before commit: `flutter analyze`, `flutter test`,
  `flutter build apk --debug`.

## Decisions from spec review

- **Repeat/loop-mode plays**: each replay within the same session counts
  as a separate play — every completion/transition (including
  `LoopMode.one` repeats) writes its own `PlayHistoryEntries` row, no
  collapsing/deduping of rapid repeats.

## Non-goals (carried from intent)
No cloud sync, no cross-device aggregation, no automatic genre "enough
data" detection.
