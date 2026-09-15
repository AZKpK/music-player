# Spec: Yearly Wrap — correction round 2

- **Status:** draft
- **Intent:** docs/faza2-wrap/intent-wrap2.md
- **Supersedes:** `docs/faza2-wrap/spec-wrap.md` for the sections touched below
  ("Recording a play", "Aggregation", "UI"). Everything else in the original
  spec (data model, Top-100 playlists, storage estimate, non-goals) is
  unchanged and not repeated here.

## Requirements

1. `msListened` recorded for a track reflects actual elapsed playback time,
   not the position reached via seeking. Seeking anywhere in a track and
   then skipping within a few seconds must record only those few seconds.
2. The Wrap screen shows top songs as a ranked list only; no bar chart.
3. The Wrap screen's ranked list can be sorted by play count (existing
   behavior, default) or by cumulative actual listening time, exposed as a
   picker using the same UI pattern as the existing sort pickers.
4. The "show top genre" toggle is not visible by default on the Wrap
   screen; it lives in a three-vertical-dots overflow menu in the Wrap
   screen's app bar.
5. The Library screen's overflow-menu button uses `Icons.more_vert`
   (three vertical dots) instead of `Icons.snippet_folder_outlined`.

## Design

### 1. Listening-time recording (`lib/core/services/audio_player_service.dart`)

Current bug: `AudioPlayerHandler` derives `msListened` from
`_lastKnownPosition`, which mirrors `_player.positionStream` — a seek moves
this value immediately, so "seek to 80%, skip after 5s" records ~80% of the
track's duration as listened.

Fix: stop deriving `msListened` from position. Measure real wall-clock time
the player was actively in the `playing` state instead, using
`_player.playerStateStream` (`PlayerState { playing, processingState }`,
already part of `just_audio`, no new dependency).

New handler state:
```dart
Duration _listenedAccumulator = Duration.zero;
DateTime? _activeSegmentStart;
```

New listener, added alongside the existing ones in the constructor:
```dart
_player.playerStateStream.listen(_handlePlayerStateChanged);
```

```dart
void _handlePlayerStateChanged(PlayerState state) {
  final active = state.playing && state.processingState == ProcessingState.ready;
  if (active && _activeSegmentStart == null) {
    _activeSegmentStart = DateTime.now();
  } else if (!active && _activeSegmentStart != null) {
    _listenedAccumulator += DateTime.now().difference(_activeSegmentStart!);
    _activeSegmentStart = null;
  }
}

/// Flushes any in-progress active segment into the accumulator, returns the
/// total, and resets for the next track. Called at every `_recordPlay` site
/// instead of reading `_lastKnownPosition`. The segment is kept open (not
/// cleared) if still active, because a real song transition does not itself
/// pause playback — there is no separate `playerStateStream` event to close
/// the segment at exactly that moment.
Duration _consumeListenedDuration() {
  if (_activeSegmentStart != null) {
    final now = DateTime.now();
    _listenedAccumulator += now.difference(_activeSegmentStart!);
    _activeSegmentStart = now;
  }
  final result = _listenedAccumulator;
  _listenedAccumulator = Duration.zero;
  return result;
}
```

Every existing `_recordPlay(mediaItem.valueOrNull, _lastKnownPosition)` call
site (`loadQueue`, `_handleCompleted`, `_handleCurrentIndexChanged`, the
loop-one branch in `_handlePositionChanged`) changes to
`_recordPlay(mediaItem.valueOrNull, _consumeListenedDuration())`.

`_lastKnownPosition` and the existing `positionStream` listener are **not**
removed — they remain exactly as-is, solely to detect `LoopMode.one` silent
repeats via `isBackwardJumpToStart`/`isLoopOneRepeat` (just_audio emits no
other event for that case, per the existing spike finding in
`spec-wrap.md`). Position tracking and listened-time tracking become two
independent concerns sharing the same class, instead of one being derived
from the other.

This satisfies the "smallest reliable change, no polling" constraint: it
only adds one more subscription to an already-existing `just_audio` stream,
no timers.

### 2. Top-songs chart removal (`lib/features/wrap/wrap_screen.dart`)

Delete `_TopSongsChart` and the block in `WrapScreen.build` that renders it
(the `SizedBox(height: 220, child: _TopSongsChart(...))` under "Top pesmi").
The existing unconditional `_RankedList` call two lines below already
renders `stats.topSongs` — it becomes the only top-songs presentation, no
new widget needed.

`fl_chart` is used nowhere else in `lib/` — remove the import from
`wrap_screen.dart` and the `fl_chart: ^0.69.2` entry from `pubspec.yaml`.

### 3. Wrap song ordering (play count / listening time)

**`lib/core/services/wrap_stats_service.dart`**
- Add `enum WrapSongSortOption { playCount, listeningTime }`.
- Add `listenedMs` to `WrapSongStat` (alongside the existing `playCount`):
  cumulative `msListened` summed only over entries that satisfy
  `isCountedPlay` for that song — same gating already used to build
  `playCount`, so both metrics rank the same underlying set of "real"
  plays. This is a different number from `WrapStats.totalListened`, which
  stays the ungated sum across all entries per the existing spec.
- `computeWrapStats` takes a new parameter
  `WrapSongSortOption songSortOption = WrapSongSortOption.playCount` and
  sorts `topSongs` by `playCount` or `listenedMs` accordingly (ties broken
  alphabetically by title, same as today). Only `topSongs` ordering is
  affected — `topArtists`/`topAlbums` stay sorted by play count, since
  intent's ordering example is specifically about songs.

**`lib/features/wrap/wrap_providers.dart`**
- Add `wrapSongSortOptionProvider = StateProvider<WrapSongSortOption>((ref) => WrapSongSortOption.playCount)`.
- `wrapStatsProvider` reads it and passes it into `computeWrapStats`.

**`lib/features/wrap/wrap_screen.dart`**
- Add `AppSelectMenu<WrapSongSortOption>` to the app bar's `actions`, same
  pattern as the Library screen's `AppSelectMenu<SongSortOption>`
  (`icon: Icons.sort`, tooltip `'Sortiraj "Top pesmi"'`), with two options:
  `'Število predvajanj'` (play count, default) and `'Čas poslušanja'`
  (listening time). This directly reuses the existing sort-picker pattern
  rather than inventing a new control, per intent's resolution.

### 4. Genre toggle moved into overflow menu (`lib/features/wrap/wrap_screen.dart`)

Remove the inline `SwitchListTile` for "Prikaži top žanr". Add a
three-vertical-dots overflow menu to the Wrap screen's app bar:
`PopupMenuButton<void>` with `icon: const Icon(Icons.more_vert)` and a
single `CheckedPopupMenuItem<bool>(value: true, checked: genreEnabled,
child: Text('Prikaži top žanr'))`; `onSelected` toggles
`updateWrapSettings(genreEnabled: !genreEnabled)`. Tapping the item both
toggles the setting and closes the menu (standard Flutter checkable-item
behavior) — reopening shows the updated check state.

This is a distinct pattern from `AppSelectMenu` (which is for picking one
value out of a list, not a boolean switch), so it is not routed through
that shared widget — see Decisions below.

The top-genre `Chip` display (shown only when `genreEnabled && topGenre !=
null`) is unchanged.

### 5. Library screen overflow-menu icon (`lib/features/library/library_screen.dart`)

One-line change at the existing `AppSelectMenu<LibraryMenuAction>` (line
~181): `icon: const Icon(Icons.snippet_folder_outlined)` →
`icon: const Icon(Icons.more_vert)`. No behavior change — same menu, same
options, only the trigger icon changes. `Icons.more_vert` is already used
elsewhere in this file for the per-song row menu; reusing it for the app
bar's overflow menu is consistent with standard Android convention (global
overflow vs. per-row overflow, both conventionally three dots).

## Decisions

- **Sort-option persistence**: `wrapSongSortOptionProvider` is a plain
  `StateProvider`, not backed by `WrapSettings` — it resets to `playCount`
  each app launch, unlike `genreEnabled` which persists. Reasoning: intent
  only asked for the picker to exist using the existing sort-option UI
  pattern; it did not ask for cross-session persistence, and adding a
  column for one small UI preference is avoidable scope. Revisit if it
  turns out to be annoying in practice.
- **Sort scope**: only `topSongs` gets the new sort option; `topArtists`/
  `topAlbums` remain play-count-only. Intent's problem statement and
  example (issue #3) are specifically about songs; extending it to
  artists/albums wasn't asked for.
- **Top-100 playlist generation unaffected**: `WrapPlaylistGenerator` in
  `wrap_providers.dart` keeps generating both playlists from
  play-count-ranked `topSongs` regardless of the on-screen sort selection.
  The sort picker is a display-only preference; the playlists are a
  separate, existing feature not mentioned in this correction round.
- **Genre toggle widget choice**: used Flutter's built-in
  `CheckedPopupMenuItem` rather than extending `AppSelectMenu` to support
  booleans, since `AppSelectMenu` is purpose-built for single-choice-from-a-
  list (its checkmark marks "the selected option", not "on/off") and
  retrofitting it for a toggle would complicate a widget shared by several
  other screens.
- **fl_chart removal**: since the only usage was `_TopSongsChart`, the
  dependency is dropped entirely rather than left unused — smaller
  dependency footprint, and no future maintenance surface for a library
  no longer in the diff.

## Deferred / out of scope

- Scaling accumulated listened time by `_player.speed` (1.5x/2x playback):
  not one of the five listed issues; the wall-clock accumulator will
  undercount content actually covered relative to `trackDurationMs` at
  non-1x speeds, affecting the 50%-of-duration countable-play threshold.
  Carried forward from `intent-wrap2.md`; revisit only if it proves to
  matter in practice.
- No migration/repair of existing `PlayHistoryEntries` rows — this feature
  was never in production, so none exist yet.
- No change to `isCountedPlay`'s threshold logic itself (`kUseDurationPercentThreshold`)
  — only the `msListened` value fed into it changes.

## Testing strategy

Following the existing `audio_player_service_test.dart` /
`wrap_stats_service` pure-function test style:
- `_consumeListenedDuration`-equivalent logic: exposed as testable pure
  helpers where practical (the accumulator math itself doesn't depend on
  `just_audio` types); otherwise covered via the existing pattern of
  extracting pure decision functions (`isBackwardJumpToStart` etc.) and
  keeping the stream-wiring thin.
- New case: seek deep into a track, then transition within a few seconds —
  `msListened` must reflect elapsed wall-clock time, not the seeked
  position.
- `computeWrapStats`: add cases for `WrapSongSortOption.listeningTime`
  ordering, including the intent's example (short track played multiple
  times vs. long track played once) and ties.
- Standard gate before commit: `flutter analyze`, `flutter test`,
  `flutter build apk --debug`.
