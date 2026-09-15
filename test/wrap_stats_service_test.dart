// Unit testi za čiste agregacijske funkcije v wrap_stats_service.dart (glej
// docs/spec-wrap.md "Testing strategy") - brez DB/Riverpod, isti stil kot
// audio_player_service_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/db/app_database.dart';
import 'package:music_player/core/models/song.dart';
import 'package:music_player/core/services/wrap_stats_service.dart';

Song _song(
  String id, {
  String artist = 'Artist',
  String album = 'Album',
  String? genre,
}) => Song(
  id: id,
  title: 'Song $id',
  artist: artist,
  album: album,
  filePath: '/music/$id.mp3',
  genre: genre,
);

PlayHistoryEntry _entry({
  required String songId,
  required int msListened,
  required int trackDurationMs,
  int id = 0,
}) => PlayHistoryEntry(
  id: id,
  songId: songId,
  playedAt: DateTime(2026, 1, 1),
  msListened: msListened,
  trackDurationMs: trackDurationMs,
);

void main() {
  group('isCountedPlay', () {
    test('exactly at the 50% threshold counts', () {
      expect(isCountedPlay(150000, 300000), isTrue);
    });

    test('just under the 50% threshold does not count', () {
      expect(isCountedPlay(149999, 300000), isFalse);
    });

    test('zero-duration track never counts', () {
      expect(isCountedPlay(999999, 0), isFalse);
    });

    test('msListened greater than trackDurationMs still counts', () {
      expect(isCountedPlay(400000, 300000), isTrue);
    });
  });

  group('computeWrapStats', () {
    test('empty history returns empty stats and zero minutes', () {
      final stats = computeWrapStats(entries: [], libraryById: {});

      expect(stats.topSongs, isEmpty);
      expect(stats.topArtists, isEmpty);
      expect(stats.topAlbums, isEmpty);
      expect(stats.totalListened, Duration.zero);
      expect(stats.topGenre, isNull);
    });

    test('single counted play produces one entry in every ranking', () {
      final song = _song('a', artist: 'Artist A', album: 'Album A');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 200000, trackDurationMs: 300000),
        ],
        libraryById: {'a': song},
      );

      expect(stats.topSongs, hasLength(1));
      expect(stats.topSongs.first.song.id, 'a');
      expect(stats.topSongs.first.playCount, 1);
      expect(stats.topArtists.single.name, 'Artist A');
      expect(stats.topAlbums.single.name, 'Album A');
      expect(stats.totalListened, const Duration(milliseconds: 200000));
    });

    test('uncounted play (below threshold) contributes to minutes but not '
        'to top rankings', () {
      final song = _song('a');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 1000, trackDurationMs: 300000),
        ],
        libraryById: {'a': song},
      );

      expect(stats.topSongs, isEmpty);
      expect(stats.topArtists, isEmpty);
      expect(stats.topAlbums, isEmpty);
      expect(stats.totalListened, const Duration(milliseconds: 1000));
    });

    test('ties in play count are broken alphabetically by name', () {
      final songB = _song('b', artist: 'Zebra', album: 'Zeta');
      final songA = _song('a', artist: 'Apple', album: 'Alpha');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'b', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': songA, 'b': songB},
      );

      expect(stats.topSongs.map((s) => s.song.id).toList(), ['a', 'b']);
      expect(stats.topArtists.map((a) => a.name).toList(), ['Apple', 'Zebra']);
      expect(stats.topAlbums.map((a) => a.name).toList(), ['Alpha', 'Zeta']);
    });

    test('higher play count ranks first regardless of name', () {
      final songA = _song('a', artist: 'Artist A');
      final songB = _song('b', artist: 'Artist B');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'b', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'b', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': songA, 'b': songB},
      );

      expect(stats.topSongs.first.song.id, 'b');
      expect(stats.topSongs.first.playCount, 2);
      expect(stats.topArtists.first.name, 'Artist B');
    });

    test('missing library entry (deleted song) still counts toward '
        'total minutes but is dropped from every top ranking', () {
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'gone', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {},
      );

      expect(stats.topSongs, isEmpty);
      expect(stats.topArtists, isEmpty);
      expect(stats.topAlbums, isEmpty);
      expect(stats.totalListened, const Duration(milliseconds: 300000));
    });

    test(
      'genre disabled leaves topGenre null even with genre data present',
      () {
        final song = _song('a', genre: 'Rock');
        final stats = computeWrapStats(
          entries: [
            _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
          ],
          libraryById: {'a': song},
        );

        expect(stats.topGenre, isNull);
      },
    );

    test('genre enabled picks the most-played genre among counted plays', () {
      final rockSong = _song('a', genre: 'Rock');
      final popSong = _song('b', genre: 'Pop');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'b', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': rockSong, 'b': popSong},
        genreEnabled: true,
      );

      expect(stats.topGenre, 'Rock');
    });

    test('genre enabled ignores songs with no known genre', () {
      final song = _song('a');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': song},
        genreEnabled: true,
      );

      expect(stats.topGenre, isNull);
    });

    test(
      'listenedMs sums only counted-play entries for a song, same gate as playCount',
      () {
        final song = _song('a');
        final stats = computeWrapStats(
          entries: [
            // Counted (exactly 50% of duration).
            _entry(songId: 'a', msListened: 150000, trackDurationMs: 300000),
            // Uncounted (below threshold) - must not contribute to listenedMs.
            _entry(songId: 'a', msListened: 1000, trackDurationMs: 300000),
          ],
          libraryById: {'a': song},
        );

        expect(stats.topSongs.single.playCount, 1);
        expect(stats.topSongs.single.listenedMs, 150000);
      },
    );

    test(
      'songSortOption.listeningTime ranks a long track played once above a '
      'short track played more times, even though play count says otherwise',
      () {
        // Intent example: a 3-minute track played 3x (9 min total) should
        // rank below a 17-minute track played once when sorting by time.
        final shortTrack = _song('short');
        final longTrack = _song('long');
        const shortDurationMs = 3 * 60 * 1000;
        const longDurationMs = 17 * 60 * 1000;
        final stats = computeWrapStats(
          entries: [
            for (var i = 0; i < 3; i++)
              _entry(
                songId: 'short',
                msListened: shortDurationMs,
                trackDurationMs: shortDurationMs,
              ),
            _entry(
              songId: 'long',
              msListened: longDurationMs,
              trackDurationMs: longDurationMs,
            ),
          ],
          libraryById: {'short': shortTrack, 'long': longTrack},
          songSortOption: WrapSongSortOption.listeningTime,
        );

        expect(stats.topSongs.map((s) => s.song.id).toList(), [
          'long',
          'short',
        ]);
      },
    );

    test('default songSortOption is playCount, matching existing behavior', () {
      final shortTrack = _song('short');
      final longTrack = _song('long');
      const shortDurationMs = 3 * 60 * 1000;
      const longDurationMs = 17 * 60 * 1000;
      final stats = computeWrapStats(
        entries: [
          for (var i = 0; i < 3; i++)
            _entry(
              songId: 'short',
              msListened: shortDurationMs,
              trackDurationMs: shortDurationMs,
            ),
          _entry(
            songId: 'long',
            msListened: longDurationMs,
            trackDurationMs: longDurationMs,
          ),
        ],
        libraryById: {'short': shortTrack, 'long': longTrack},
      );

      expect(stats.topSongs.map((s) => s.song.id).toList(), ['short', 'long']);
    });

    test('ties in listenedMs are broken alphabetically by title', () {
      final songB = _song('b', artist: 'Zebra');
      final songA = _song('a', artist: 'Apple');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'b', msListened: 300000, trackDurationMs: 300000),
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': songA, 'b': songB},
        songSortOption: WrapSongSortOption.listeningTime,
      );

      expect(stats.topSongs.map((s) => s.song.id).toList(), ['a', 'b']);
    });
  });

  group('computeWrapStats maxTopEntries', () {
    test('null (default) keeps every entry, unbounded', () {
      final entries = [
        for (var i = 0; i < 12; i++)
          _entry(songId: 's$i', msListened: 300000, trackDurationMs: 300000),
      ];
      final libraryById = {
        for (var i = 0; i < 12; i++) 's$i': _song('s$i', artist: 'a$i'),
      };
      final stats = computeWrapStats(
        entries: entries,
        libraryById: libraryById,
      );

      expect(stats.topSongs, hasLength(12));
      expect(stats.topArtists, hasLength(12));
      expect(stats.topAlbums, hasLength(1));
    });

    test('caps topSongs/topArtists/topAlbums to the given limit, keeping '
        'the highest-ranked entries', () {
      final entries = [
        for (var i = 0; i < 12; i++)
          for (var p = 0; p < 12 - i; p++)
            _entry(songId: 's$i', msListened: 300000, trackDurationMs: 300000),
      ];
      final libraryById = {
        for (var i = 0; i < 12; i++) 's$i': _song('s$i', artist: 'a$i'),
      };
      final stats = computeWrapStats(
        entries: entries,
        libraryById: libraryById,
        maxTopEntries: 10,
      );

      expect(stats.topSongs, hasLength(10));
      expect(stats.topArtists, hasLength(10));
      expect(stats.topSongs.map((s) => s.song.id), [
        for (var i = 0; i < 10; i++) 's$i',
      ]);
    });

    test('a limit larger than the actual entry count is a no-op', () {
      final song = _song('a');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': song},
        maxTopEntries: 10,
      );

      expect(stats.topSongs, hasLength(1));
    });
  });

  group('computeSongPlayStats', () {
    test('empty history returns an empty map', () {
      expect(computeSongPlayStats([]), isEmpty);
    });

    test('sums playCount and listenedMs across counted plays for a song', () {
      final stats = computeSongPlayStats([
        _entry(songId: 'a', msListened: 150000, trackDurationMs: 300000),
        _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
      ]);

      expect(stats['a']!.playCount, 2);
      expect(stats['a']!.listenedMs, 450000);
    });

    test('uncounted plays (below threshold) are excluded, same gate as '
        'computeWrapStats', () {
      final stats = computeSongPlayStats([
        _entry(songId: 'a', msListened: 1000, trackDurationMs: 300000),
      ]);

      expect(stats.containsKey('a'), isFalse);
    });

    test('is not scoped to a wrap period - just aggregates whatever entries '
        'it is given', () {
      final stats = computeSongPlayStats([
        _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
      ]);

      expect(stats['a']!.playCount, 1);
    });
  });

  group('mostRecentWrapBoundary', () {
    test('calendar year default: boundary is Jan 1 of the current year', () {
      final boundary = mostRecentWrapBoundary(
        now: DateTime(2026, 6, 15),
        resetMonth: 1,
        resetDay: 1,
      );
      expect(boundary, DateTime(2026, 1, 1));
    });

    test('now exactly on the boundary counts as the current period', () {
      final boundary = mostRecentWrapBoundary(
        now: DateTime(2026, 9, 1),
        resetMonth: 9,
        resetDay: 1,
      );
      expect(boundary, DateTime(2026, 9, 1));
    });

    test('now before this year\'s reset date falls back to last year\'s', () {
      final boundary = mostRecentWrapBoundary(
        now: DateTime(2026, 8, 31),
        resetMonth: 9,
        resetDay: 1,
      );
      expect(boundary, DateTime(2025, 9, 1));
    });
  });

  group('computeWrapPeriodBounds', () {
    test('current and previous period starts are exactly one year apart', () {
      final bounds = computeWrapPeriodBounds(
        now: DateTime(2026, 9, 15),
        resetMonth: 9,
        resetDay: 1,
      );
      expect(bounds.currentPeriodStart, DateTime(2026, 9, 1));
      expect(bounds.previousPeriodStart, DateTime(2025, 9, 1));
    });
  });
}
