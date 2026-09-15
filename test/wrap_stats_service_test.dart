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
      expect(stats.topArtists.map((a) => a.name).toList(), [
        'Apple',
        'Zebra',
      ]);
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

    test('genre disabled leaves topGenre null even with genre data present', () {
      final song = _song('a', genre: 'Rock');
      final stats = computeWrapStats(
        entries: [
          _entry(songId: 'a', msListened: 300000, trackDurationMs: 300000),
        ],
        libraryById: {'a': song},
      );

      expect(stats.topGenre, isNull);
    });

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
  });
}
