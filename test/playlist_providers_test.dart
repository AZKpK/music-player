// Unit test za `sortPlaylists` (glej docs/faza2-wrap/intent3.md) - čista
// funkcija, brez DB/Riverpod, isti stil kot media_library_filter_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/db/app_database.dart';
import 'package:music_player/core/services/playlist_providers.dart';
import 'package:music_player/core/services/wrap_stats_service.dart';

Playlist _playlist(int id, String name) =>
    Playlist(id: id, name: name, createdAt: DateTime(2026, 1, 1));

void main() {
  final playlists = [
    _playlist(1, 'Zabava'),
    _playlist(2, 'Anthems'),
    _playlist(3, 'Chill'),
  ];

  group('sortPlaylists', () {
    test('alphabetical sorts by name, case-insensitive', () {
      final result = sortPlaylists(
        playlists,
        GroupSortOption.alphabetical,
        const {},
      );
      expect(result.map((p) => p.id), [2, 3, 1]);
    });

    test('playCount sorts by aggregated play count descending', () {
      final stats = {
        1: const SongPlayStat(playCount: 5, listenedMs: 0),
        2: const SongPlayStat(playCount: 20, listenedMs: 0),
        3: const SongPlayStat(playCount: 1, listenedMs: 0),
      };
      final result = sortPlaylists(playlists, GroupSortOption.playCount, stats);
      expect(result.map((p) => p.id), [2, 1, 3]);
    });

    test(
      'listeningTime sorts by aggregated listened milliseconds descending',
      () {
        final stats = {
          1: const SongPlayStat(playCount: 0, listenedMs: 60000),
          2: const SongPlayStat(playCount: 0, listenedMs: 10000),
          3: const SongPlayStat(playCount: 0, listenedMs: 300000),
        };
        final result = sortPlaylists(
          playlists,
          GroupSortOption.listeningTime,
          stats,
        );
        expect(result.map((p) => p.id), [3, 1, 2]);
      },
    );

    test('playlists missing from the stats map count as zero, sink to the '
        'bottom', () {
      final stats = {2: const SongPlayStat(playCount: 3, listenedMs: 0)};
      final result = sortPlaylists(playlists, GroupSortOption.playCount, stats);
      expect(result.first.id, 2);
    });

    test('ties are broken alphabetically by name', () {
      final stats = {
        1: const SongPlayStat(playCount: 5, listenedMs: 0),
        2: const SongPlayStat(playCount: 5, listenedMs: 0),
        3: const SongPlayStat(playCount: 5, listenedMs: 0),
      };
      final result = sortPlaylists(playlists, GroupSortOption.playCount, stats);
      expect(result.map((p) => p.id), [2, 3, 1]);
    });

    test('does not mutate the original list', () {
      final originalOrder = [...playlists];
      sortPlaylists(playlists, GroupSortOption.alphabetical, const {});
      expect(playlists, originalOrder);
    });
  });
}
