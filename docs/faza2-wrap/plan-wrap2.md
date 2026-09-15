# Plan: Yearly Wrap — correction round 2

- **Spec:** docs/faza2-wrap/spec-wrap2.md

## Files to change

- `lib/core/services/audio_player_service.dart` — replace the
  `_lastKnownPosition`-derived `msListened` with a wall-clock accumulator
  fed by `_player.playerStateStream`, per spec section 1. Concretely:
  - New pure helpers (top-level functions, alongside `isBackwardJumpToStart`/
    `isRealSongTransition`, so the accumulator math is unit-testable without
    a real `just_audio` player or `DateTime.now()`):
    ```dart
    @immutable
    class ListenedAccumulator {
      const ListenedAccumulator({this.total = Duration.zero, this.activeSegmentStart});
      final Duration total;
      final DateTime? activeSegmentStart;
    }

    ListenedAccumulator updateListenedAccumulator({
      required ListenedAccumulator current,
      required bool active,
      required DateTime now,
    });

    class ConsumedListened {
      const ConsumedListened({required this.duration, required this.remainder});
      final Duration duration;
      final ListenedAccumulator remainder;
    }

    ConsumedListened consumeListenedDuration({
      required ListenedAccumulator current,
      required DateTime now,
    });
    ```
    `updateListenedAccumulator` opens a segment (`activeSegmentStart = now`)
    when transitioning to active and none is open, closes it (folds the
    elapsed time into `total`, clears `activeSegmentStart`) when transitioning
    to inactive with one open, and is a no-op otherwise (matches spec's
    `_handlePlayerStateChanged` body). `consumeListenedDuration` flushes any
    open segment into `total` (restarting it at `now` rather than clearing
    it, exactly as spec's `_consumeListenedDuration` comment explains — a
    real transition doesn't itself pause playback), returns the flushed
    total, and resets the remainder's `total` to zero.
  - `AudioPlayerHandler` gets one new field, `ListenedAccumulator
    _listenedAccumulator = const ListenedAccumulator();`, one new
    constructor listener (`_player.playerStateStream.listen(_handlePlayerStateChanged)`),
    and two thin wrapper methods (`_handlePlayerStateChanged` calls
    `updateListenedAccumulator(current: _listenedAccumulator, active: ...,
    now: DateTime.now())` and stores the result; `_consumeListenedDuration`
    calls `consumeListenedDuration(current: _listenedAccumulator, now:
    DateTime.now())`, stores `.remainder`, returns `.duration`).
  - `_lastKnownPosition`, `_handlePositionChanged`, `isBackwardJumpToStart`,
    `isLoopOneRepeat` are **unchanged** — still drive loop-one detection only.
  - All four `_recordPlay(mediaItem.valueOrNull, _lastKnownPosition)` call
    sites (`loadQueue:371`, `_handleCompleted:710`, `_handleCurrentIndexChanged:717`,
    the loop-one branch in `_handlePositionChanged:742`) change their second
    argument to `_consumeListenedDuration()`. The `_lastKnownPosition = ...`
    reset lines next to them stay as-is (still needed for loop-one math).
- `lib/features/wrap/wrap_screen.dart`:
  - Delete `_TopSongsChart` and the `SizedBox(height: 220, child:
    _TopSongsChart(...))` block (lines 63–71); `_RankedList` two lines below
    already renders `stats.topSongs` unconditionally.
  - Remove the `fl_chart` import.
  - Remove the inline `SwitchListTile` "Prikaži top žanr" (lines 50–56).
    Add a `PopupMenuButton<void>` (`icon: const Icon(Icons.more_vert)`) to
    `AppBar.actions`, containing one
    `CheckedPopupMenuItem<bool>(value: true, checked: genreEnabled, child:
    Text('Prikaži top žanr'))`; `onSelected` calls the existing
    `ref.read(appDatabaseProvider).updateWrapSettings(genreEnabled:
    !genreEnabled)`. The genre `Chip` (lines 57–61) is unchanged.
  - Add `AppSelectMenu<WrapSongSortOption>` to `AppBar.actions` (same slot,
    before the new overflow menu), mirroring `library_screen.dart:150-178`:
    `icon: Icons.sort`, `tooltip: 'Sortiraj "Top pesmi"'`, reading/writing
    `wrapSongSortOptionProvider`, two `AppSelectOption`s (`'Število
    predvajanj'` / `'Čas poslušanja'`).
  - `_RankedEntry` gains an optional `listenedMs` field and `_RankedList`'s
    trailing text switches between `'${playCount}x'` and a formatted
    `mm:ss`/`h:mm` duration based on which sort option is active — without
    this, switching to time-sort would reorder the list but still show play
    counts, which doesn't visibly justify the new order. Not spelled out in
    spec-wrap2.md's Design section; noted here as the concrete UI call
    since spec section 3 only specifies the picker itself. Only the
    `topSongs` `_RankedList` call passes `listenedMs`/sort option through;
    the artists/albums `_RankedList` calls are unchanged (always play-count
    trailing), matching spec's "only topSongs" sort scope.
- `lib/core/services/wrap_stats_service.dart`:
  - Add `enum WrapSongSortOption { playCount, listeningTime }`.
  - `WrapSongStat` gains `final int listenedMs;` (required constructor
    param).
  - In `computeWrapStats`'s existing per-entry loop (where `songPlayCounts`
    is updated, ~line 87), add a parallel `songListenedMs = <String,
    int>{}` accumulator, summing `entry.msListened` for the same
    `isCountedPlay`-gated entries — same gate already used for
    `songPlayCounts`, so both metrics rank the same underlying set of plays
    (per spec's explicit "same gating" requirement).
  - `computeWrapStats` gains `WrapSongSortOption songSortOption =
    WrapSongSortOption.playCount`; the `topSongs` sort comparator branches
    on it (`playCount` or `listenedMs`, both via the existing
    `_compareStats`-style desc-then-alphabetical tiebreak — generalize
    `_compareStats`'s first two `int` params to accept either metric rather
    than duplicating the function). `topArtists`/`topAlbums` sorting is
    unchanged (always play-count).
- `lib/features/wrap/wrap_providers.dart`:
  - Add `final wrapSongSortOptionProvider =
    StateProvider<WrapSongSortOption>((ref) => WrapSongSortOption.playCount);`.
  - `wrapStatsProvider` reads it and passes `songSortOption: ...` into
    `computeWrapStats`.
  - `WrapPlaylistGenerator.regenerateIfDue`'s two `computeWrapStats` calls
    (closed-year snapshot, all-time) stay on the default `playCount` — do
    **not** wire `wrapSongSortOptionProvider` into them, matching spec's
    "Top-100 playlist generation unaffected" decision.
- `lib/features/library/library_screen.dart` — line 181: `icon: const
  Icon(Icons.snippet_folder_outlined)` → `icon: const
  Icon(Icons.more_vert)`. No other change.
- `pubspec.yaml` — remove the `fl_chart: ^0.69.2` line (only consumer was
  `_TopSongsChart`); run `flutter pub get` after.
- `test/audio_player_service_test.dart` — new `group('updateListenedAccumulator')`
  and `group('consumeListenedDuration')` covering: segment open on
  active-transition, segment close (elapsed folded into total) on
  inactive-transition, no-op when state doesn't change activity, consume
  with no open segment (returns `total`, resets to zero), consume with an
  open segment (flushes elapsed, restarts segment at `now`, per-call
  `total` reset to zero but segment survives) — this last case is the
  concrete "seek then transition within a few seconds" scenario from
  spec's Testing strategy, expressed at the pure-function level.
- `test/wrap_stats_service_test.dart` — new cases in `group('computeWrapStats')`:
  `listenedMs` populated correctly per song (only counted plays
  contribute), `songSortOption: listeningTime` reorders `topSongs` (using
  the intent's example: short track played 3x vs. long track played once),
  ties broken alphabetically under `listeningTime` too, default
  (`playCount`) behavior unchanged from existing tests.

## Order of work

Each numbered step is its own commit (code + its tests together).

1. **Listening-time recording** (`audio_player_service.dart` +
   `audio_player_service_test.dart`): add the pure accumulator helpers and
   their tests first, then wire `_handlePlayerStateChanged`/
   `_consumeListenedDuration` into `AudioPlayerHandler` and switch all four
   `_recordPlay` call sites. This is the highest-risk change (touches live
   playback recording) — land and verify it in isolation before touching
   UI/stats code that only reads its output.
2. **Wrap song sort + listenedMs** (`wrap_stats_service.dart` +
   `wrap_stats_service_test.dart`): add `WrapSongSortOption`, `listenedMs`,
   and the sort branch, independent of step 1 (only needs
   `PlayHistoryEntry.msListened`, already in the schema) and of the UI.
3. **Wrap providers** (`wrap_providers.dart`): add
   `wrapSongSortOptionProvider`, wire it into `wrapStatsProvider`, confirm
   `WrapPlaylistGenerator` call sites deliberately left on the default. No
   dedicated test file, matching existing convention for this file (thin
   reactive wiring — see `plan-wrap.md` step 6's reasoning).
4. **Wrap screen UI** (`wrap_screen.dart`): remove the chart + `fl_chart`
   import, move the genre toggle into the overflow menu, add the sort
   `AppSelectMenu`, extend `_RankedEntry`/`_RankedList` for the
   listened-time trailing text.
5. **Library screen icon** (`library_screen.dart`): one-line icon swap.
6. **Dependency cleanup** (`pubspec.yaml`): remove `fl_chart`, run `flutter
   pub get`.
7. **Full gate**: `flutter analyze`, `flutter test`, `flutter build apk
   --debug`, then a manual on-device check (see Proof).

## Risks

- Wall-clock accumulation depends on `playerStateStream` firing promptly
  and in the expected order relative to the four `_recordPlay` sites; if
  a real device defers/reorders these events differently than the pure
  logic assumes (as happened with `positionStream` ordering in round 1 —
  see `plan-wrap.md` step 3), a second on-device spike-style check may be
  needed before trusting step 1 as done. Budget for this even though
  spec-wrap2.md doesn't call out a spike this round.
- `consumeListenedDuration` restarting (not clearing) an open segment at
  `now` relies on every `_recordPlay` call site actually calling
  `_consumeListenedDuration()` exactly once per transition — a duplicate or
  missed call would double-count or drop listened time. All four sites are
  covered in the Files list above; worth grepping for any other
  `_lastKnownPosition`-adjacent `_recordPlay`-like call before closing step 1.
- Removing `fl_chart` from `pubspec.yaml` before confirming no other file
  imports it would break the build — already checked (spec section 2:
  "used nowhere else in `lib/`"), re-verify with a grep in step 6 before
  editing `pubspec.yaml`.
- `_RankedEntry`/`_RankedList` trailing-text change (step 4) is this plan's
  own addition beyond spec's literal text — low risk (isolated, cosmetic),
  but flagged since it's a design call made during planning rather than in
  spec-wrap2.md itself.

## Proof

- Step 1: new `audio_player_service_test.dart` accumulator cases pass,
  including the "seek then transition within a few seconds" case from
  spec's Testing strategy.
- Step 2: new `wrap_stats_service_test.dart` cases pass, including the
  intent's short-track-x3-vs-long-track-x1 ordering example.
- Step 3–5: covered by the full gate (step 7) plus manual verification, no
  dedicated tests (matches existing convention for provider-wiring/UI
  files in this codebase).
- Step 7: `flutter analyze` clean, `flutter test` all green, `flutter build
  apk --debug` succeeds. Manual on-device check (Pixel_7 emulator, same
  setup as round 1): seek into a track and skip within a few seconds,
  confirm the recorded play's listened time is small (not the seeked
  position); switch the Wrap sort picker and confirm song order changes
  and the displayed metric matches; toggle the genre setting from the new
  overflow menu; confirm the top-songs section is a ranked list only (no
  chart); confirm the Library screen's overflow icon is three dots.
