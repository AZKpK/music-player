# Intent: Yearly Wrap

## Goal
Give the user a Spotify-Wrapped-style yearly summary of their own listening,
based purely on local play data (no cloud/account involved).

## What it should show
- Top artists (most listened)
- Top albums (most listened)
- Top songs (most listened)
- Total minutes listened
- Top genre — **flagged as the hardest part**: genre is not reliably
  available today. `SongOverrides.genre` already exists as a nullable,
  manually-editable field, but most songs won't have it set unless the
  source file's ID3 tag has it or the user fills it in by hand. Top-genre
  will only be as good as tag/override coverage allows.

## Feature: auto-generated Top 100 playlists
At wrap time, automatically create/update two playlists (reusing the
existing `Playlists`/`PlaylistSongs` tables):
- A per-year **snapshot** playlist (e.g. "Wrap 2026") with that year's top
  100 most-listened songs — created once per year, not touched afterward.
- One **all-time** playlist with the top 100 most-listened songs across all
  history — regenerated (overwritten) each time a new wrap is generated.

## Feature: Library page navigation menu
Replace the "play from a folder" button on the library page with a dropdown
menu containing, in order:
1. Settings — placeholder only for now, no functionality yet
2. Play from a folder — existing behavior, moved into the menu
3. Wrap — navigates to the wrap screen, so the user can revisit it anytime
   instead of only at year-end

## Decisions (resolved)
- **Countable "play" threshold**: 50% of the track listened is the target
  rule for counting a song toward top-songs/top-artists/top-albums. This is
  gated by a Build-stage technical spike (see below) rather than further
  product input — if `just_audio`/`audio_service` can reliably and quickly
  report "% of track played," use 50%; otherwise fall back to a flat 60s
  threshold. Either way, **total minutes listened counts actual playback
  time**, not gated by the same threshold (a partial listen still adds its
  played duration to the total).
- **Top genre**: off by default for v1 (not computed/shown), with a manual
  toggle to turn it on later once enough songs are tagged. No automatic
  "enough data" detection needed.
- **Top 100 playlists**: two playlists — per-year snapshot + regenerating
  all-time (see Feature section above).
- **Year boundary**: calendar year (Jan 1, like Spotify) by default,
  user-changeable in settings; changing the reset date only affects future
  bucketing, past play-history is not re-bucketed.
- **All-time playlist regeneration**: overwritten only on wrap generation,
  never as continuous background work.
- **Snapshot playlist name collisions**: if a name collision occurs (e.g.
  user renamed/duplicated a past "Wrap 2026"), suffix a counter — "Wrap
  2026 (1)", "Wrap 2026 (2)", etc.
- **Settings menu item**: tapping it shows a "coming soon" message — no
  real settings screen yet.
- **Genre toggle location**: lives on the wrap screen itself, not in
  settings.
- **Wrap generation trigger**: opening the wrap screen anytime just
  *displays* current stats (recomputed live from play-history, cheap read).
  The all-time playlist and the per-year snapshot playlist only actually
  *regenerate*/get created on the yearly trigger (reset-date boundary), not
  on every visit.

## Open questions for spec.md
- **Build-stage spike** (not blocking intent approval): confirm whether
  reliable, low-cost "% of track played" tracking is feasible in
  `just_audio`/`audio_service` (accounting for seeks/skips) to decide
  between the 50% rule and the 60s fallback.

## Storage design constraint: keep the DB small
Investigated during planning (see `lib/core/db/app_database.dart` for
existing schema conventions):

- Unlike `PlaylistSongs`, which intentionally duplicates song metadata
  (title/artist/album/path) because MediaStore ids aren't stable long-term,
  a play-history table should **not** duplicate text metadata per row —
  play events are far more numerous than playlist entries. Store only
  `songId` + `playedAt` + `msListened` per play, and resolve
  title/artist/album/genre by joining against the current library (via
  `SongOverrides`/MediaStore) at read/aggregation time.
- Estimated row cost: ~15–25 bytes/row raw, ~35–50 bytes/row once an index
  for aggregation queries (e.g. on `playedAt` or `songId`) is added.
- Estimated yearly size: a heavy listener (~100 plays/day) generates
  ~36,500 rows/year → roughly **1–1.5 MB/year**. Even several years of
  history stays well under 10 MB — negligible on any phone, so aggressive
  optimization isn't required for v1.
- Optional future retention strategy if multi-year growth ever becomes a
  concern: after a year closes, collapse its raw play-history rows into a
  small per-song yearly aggregate table (songId, year, playCount,
  totalMsListened) and drop rows older than ~5 years. This bounds DB size
  regardless of how many years of history accumulate, without losing the
  wrap-relevant aggregates. //dont implement just yet

## Non-goals (for now)
- No cloud sync or sharing beyond local export/screenshot.
- No cross-device aggregation.
