# Intent 3: Library sort-by-plays/listening-time + Wrap top-10 cap

- **Author:** Andra
- **Status:** accepted
- **Date:** 2026-09-15

Note: per explicit instruction, this round skips the spec/plan stages and goes
straight from intent to build. The scope decisions that a spec would normally
carry are recorded below instead.

## Problem

1. The "sort by number of plays / minutes listened" picker added in wrap2
   only exists on the Wrap screen's "Top pesmi" list. The same play-count and
   listening-time data is not available anywhere in the Library screen, so a
   user browsing their normal library (not the yearly Wrap) has no way to see
   their songs, artists, or playlists ordered by how much they've actually
   listened to them.
2. The Wrap screen's "Top pesmi", "Top izvajalci" and "Top albumi" lists are
   unbounded - `WrapStats.topSongs/topArtists/topAlbums` already carry a code
   comment stating the UI is expected to truncate them, but it currently
   doesn't. With a large library this makes the Wrap screen an unreadably
   long list instead of a "top" ranking.

## Proposed outcome

- The Library screen's "Vse pesmi", "Izvajalci" and "Playliste" tabs each get
  a sort control offering "Število predvajanj" (play count) and "Čas
  poslušanja" (listening time), using the same all-time play-history data and
  labels as the existing Wrap picker.
- The Wrap screen's "Top pesmi", "Top izvajalci" and "Top albumi" lists each
  show at most the top 10 entries.

## Affected users/systems

- Library screen: "Vse pesmi", "Izvajalci", "Playliste" tabs and their app
  bar sort controls.
- Wrap screen's ranked lists (display only).
- Play-history aggregation (`wrap_stats_service.dart`), reused (not
  duplicated) for the new Library-side sorting.

## Decisions

- **Scope of "all songs/artists/playlists" (change 1):** interpreted as the
  Library screen's three tab names ("Vse pesmi", "Izvajalci", "Playliste").
  "Albumi" is intentionally excluded, matching the literal wording (which
  lists songs/artists/playlists, not albums) and keeping the "Albumi" tab's
  existing track-order-preserving behavior for album drill-down untouched.
- **Playlist ranking metric:** a playlist's play count/listening time is the
  sum of those metrics across its member songs (join `PlaylistSongs.songId`
  against the same all-time play-history aggregate used for songs). The
  system "Priljubljene pesmi" entry stays pinned first, unaffected by sort,
  since it isn't a `Playlist` row and has no `playlistId` to aggregate by.
- **Artist ranking metric:** same idea - sum of the metric across all of an
  artist's songs.
- **Data window:** Library-side sorting uses all-time play history (no Wrap
  period boundary), since the Library screen is not year-scoped.
- **Where the top-10 cap lives (change 2):** inside `computeWrapStats` via a
  new optional `maxTopEntries` parameter (default `null` = unbounded), not
  hardcoded into the sort/aggregation. The Wrap screen's stats provider
  passes `10`. Playlist generation (`WrapPlaylistGenerator`, "Top-100
  playlists") keeps calling `computeWrapStats` without the limit, so it is
  unaffected by the new display cap.

## Constraints

- Reuse the existing `isCountedPlay` gate and wrap_stats aggregation
  approach; do not introduce a second definition of what counts as a play.
- No new dependencies, no new screens - only additive sort options in
  existing app bar menus, following the existing `AppSelectMenu` pattern.
- Keep existing valid behavior: playlist generation must still consider up to
  100 songs, unaffected by the new 10-entry Wrap display cap.
- Test using the existing pure-function unit test files
  (`test/wrap_stats_service_test.dart`, `test/media_library_filter_test.dart`)
  and their established style; no new manual/visual verification this round
  (left to the user).

## Open questions

None - resolved above.
