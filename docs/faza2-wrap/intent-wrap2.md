# Intent: Yearly Wrap — correction round 2

- **Author:** Andra
- **Status:** accepted
- **Date:** 2026-09-15
- **Supersedes:** `docs/faza2-wrap/intent-wrap.md` for the issues below

## Problem

The initial Yearly Wrap implementation has five user-visible issues:

1. Seeking far into a track and then skipping it records the seek position as
   listening time. For example, seeking to 80% of a five-minute track and
   skipping after five seconds is recorded as about five minutes listened.
   This inflates listening-time statistics and can incorrectly count a play.
2. The top-songs chart becomes unreadable: song names overlap even with a
   small library and will be worse with more songs.
3. The Wrap screen cannot order songs by either play count or total actual
   listening time. These are distinct: a three-minute track played three
   times (nine minutes) should rank below a 17-minute track played once when
   sorting by listening time.
4. The "show genre" control takes permanent space on the Wrap screen even
   though it is an optional setting.
5. The Library screen's overflow menu uses an icon that does not clearly
   communicate a menu.

## Proposed outcome

- Wrap records and aggregates time the user actually listened, rather than
  the playback position reached through seeking. Seeking then skipping must
  not falsely add the skipped portion to total listening time or satisfy the
  countable-play threshold.
- Recording mechanism: `msListened` is measured as real wall-clock time the
  player was actively in the `playing` state (via `_player.playerStateStream`
  — `playing == true` and `processingState == ready`), accumulated into a
  running total and reset per track, rather than read from
  `positionStream`/`_lastKnownPosition` as today. A seek never advances this
  clock, so "seek to 80%, skip after 5s" accumulates ~5s regardless of where
  the seek landed — no jump-detection heuristics needed, and no extra
  polling. The existing `positionStream`-based backward-jump detection used
  to notice `LoopMode.one` repeats is unaffected; it just no longer feeds
  `msListened` directly.
- The top-songs chart is removed for now; top songs are presented as a ranked
  list instead, so label overlap is no longer possible.
- The Wrap screen's ranked list offers two additional song-ordering choices,
  play count and cumulative actual listening time, added alongside the
  existing sort options (e.g. naslov A-Ž, album). Time ordering uses the sum
  of recorded listening time for each song.
- The genre visibility setting moves into a three-vertical-dots overflow menu
  in the Wrap screen's top-right app bar.
- The Library screen's existing extra-menu button uses the standard
  three-vertical-dots icon.

## Affected users/systems

- Listeners viewing their personal yearly Wrap statistics.
- Play-history recording in the audio player, including seeks, skips, pauses,
  track transitions, and repeat playback.
- Wrap statistics and ranking presentation.
- The Wrap and Library screen app bars and menus.

## Constraints

- Preserve existing local-only play history; do not introduce cloud sync or
  cross-device aggregation.
- Do not corrupt or reinterpret existing play-history rows. The correction
  applies to future recording unless a safe migration is explicitly designed.
- Keep existing valid behavior for normal playback, queue transitions, and
  loop-one repeats.
- Prefer the smallest reliable recording change; it must distinguish actual
  playback from position jumps without adding avoidable polling or background
  work.
- Keep the current Slovenian UI language and existing menu patterns.
- The feature was never in production, so there are no incorrectly recorded
  play-history entries to migrate or repair; the fix only needs to apply to
  future recording.
- Out of scope for this round: scaling accumulated listened time by
  `_player.speed` when the user changes playback speed (1.5x/2x/etc). Without
  it, `msListened` undercounts content actually covered relative to
  `trackDurationMs` at non-1x speeds, which could affect the 50%-of-duration
  countable-play threshold. Not one of the five listed issues; revisit in a
  future round if it turns out to matter in practice.

## Open questions

None — all resolved above.
