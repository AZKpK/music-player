// Unit test za `filterLibrarySongs` (Faza 6.3 - iskanje po knjižnici).
// Namerno testira samo čisto funkcijo, ne providerje - `librarySongsProvider`
// je odvisen od `on_audio_query`/drift platform-channel-ov, ki v testnem
// okolju niso na voljo (glej `widget_test.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/models/song.dart';
import 'package:music_player/core/services/media_library_providers.dart';
import 'package:music_player/core/services/wrap_stats_service.dart';

Song _song({
  required String id,
  required String title,
  required String artist,
  required String album,
  DateTime? dateAdded,
  Duration? duration,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    filePath: '/tmp/$id.mp3',
    dateAdded: dateAdded,
    duration: duration,
  );
}

void main() {
  final songs = [
    _song(
      id: '1',
      title: 'Mr. Brightside',
      artist: 'The Killers',
      album: 'Hot Fuss',
    ),
    _song(
      id: '2',
      title: 'Take Me Out',
      artist: 'Franz Ferdinand',
      album: 'Franz Ferdinand',
    ),
    _song(
      id: '3',
      title: 'Somebody Told Me',
      artist: 'The Killers',
      album: 'Hot Fuss',
    ),
  ];

  test('prazen query vrne vso knjižnico nespremenjeno', () {
    expect(filterLibrarySongs(songs, ''), songs);
    expect(filterLibrarySongs(songs, '   '), songs);
  });

  test('filtrira po naslovu, case-insensitive', () {
    final result = filterLibrarySongs(songs, 'brightside');
    expect(result, [songs[0]]);
  });

  test('filtrira po izvajalcu, vrne vse ujemajoče pesmi', () {
    final result = filterLibrarySongs(songs, 'killers');
    expect(result, [songs[0], songs[2]]);
  });

  test('filtrira po albumu', () {
    final result = filterLibrarySongs(songs, 'hot fuss');
    expect(result, [songs[0], songs[2]]);
  });

  test('brez zadetkov vrne prazen seznam', () {
    expect(filterLibrarySongs(songs, 'nekaj kar ne obstaja'), isEmpty);
  });

  group('filterLibraryGroups', () {
    final groups = <String, List<Song>>{
      'The Killers': [songs[0], songs[2]],
      'Franz Ferdinand': [songs[1]],
    };

    test('filtrira skupine po imenu, case-insensitive', () {
      expect(filterLibraryGroups(groups, 'KILL'), {
        'The Killers': [songs[0], songs[2]],
      });
    });

    test('prazen query vrne vse skupine', () {
      expect(filterLibraryGroups(groups, '  '), groups);
    });
  });

  group('sortLibrarySongs', () {
    final unsorted = [
      _song(
        id: '1',
        title: 'B pesem',
        artist: 'B izvajalec',
        album: 'B album',
        dateAdded: DateTime(2024, 1, 1),
        duration: const Duration(seconds: 200),
      ),
      _song(
        id: '2',
        title: 'A pesem',
        artist: 'A izvajalec',
        album: 'A album',
        dateAdded: DateTime(2024, 6, 1),
        duration: const Duration(seconds: 100),
      ),
      _song(
        id: '3',
        title: 'C pesem',
        artist: 'C izvajalec',
        album: 'C album',
        dateAdded: null,
        duration: const Duration(seconds: 300),
      ),
    ];

    test('title sortira po naslovu naraščajoče', () {
      final result = sortLibrarySongs(unsorted, SongSortOption.title);
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });

    test('artist sortira po izvajalcu naraščajoče', () {
      final result = sortLibrarySongs(unsorted, SongSortOption.artist);
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });

    test('album sortira po albumu naraščajoče', () {
      final result = sortLibrarySongs(unsorted, SongSortOption.album);
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });

    test('dateAddedDesc razvrsti najnovejše najprej, null na konec', () {
      final result = sortLibrarySongs(unsorted, SongSortOption.dateAddedDesc);
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });

    test('duration sortira po trajanju naraščajoče', () {
      final result = sortLibrarySongs(unsorted, SongSortOption.duration);
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });

    test('ne spremeni izvirnega seznama (vrne kopijo)', () {
      final originalOrder = [...unsorted];
      sortLibrarySongs(unsorted, SongSortOption.title);
      expect(unsorted, originalOrder);
    });

    test(
      'title sortira brez razlikovanja velikih/malih črk (case-insensitive)',
      () {
        final mixedCase = [
          _song(id: '1', title: 'boy', artist: 'X', album: 'X'),
          _song(id: '2', title: 'Battle Born', artist: 'X', album: 'X'),
          _song(id: '3', title: 'Bright Lights', artist: 'X', album: 'X'),
        ];
        final result = sortLibrarySongs(mixedCase, SongSortOption.title);
        // "boy" (malo b) mora pristati med ostalimi "B..." naslovi, ne za
        // njimi - `String.compareTo` bi ga sicer dal na konec (velike črke
        // pridejo pred male v ASCII).
        expect(result.map((s) => s.id), ['2', '1', '3']);
      },
    );

    test('playCount sortira padajoče po playStats, brez vnosa šteje kot 0', () {
      final playStats = {
        '1': const SongPlayStat(playCount: 5, listenedMs: 0),
        '3': const SongPlayStat(playCount: 20, listenedMs: 0),
        // '2' namerno izpuščen - mora šteti kot 0, ne vreči napake.
      };
      final result = sortLibrarySongs(
        unsorted,
        SongSortOption.playCount,
        playStats: playStats,
      );
      expect(result.map((s) => s.id), ['3', '1', '2']);
    });

    test('listeningTime sortira padajoče po listenedMs, ne po playCount', () {
      final playStats = {
        '1': const SongPlayStat(playCount: 100, listenedMs: 1000),
        '2': const SongPlayStat(playCount: 1, listenedMs: 500000),
        '3': const SongPlayStat(playCount: 1, listenedMs: 2000),
      };
      final result = sortLibrarySongs(
        unsorted,
        SongSortOption.listeningTime,
        playStats: playStats,
      );
      expect(result.map((s) => s.id), ['2', '3', '1']);
    });

    test('playCount izenačenje se razreši po naslovu (case-insensitive)', () {
      final playStats = {
        '1': const SongPlayStat(playCount: 5, listenedMs: 0),
        '2': const SongPlayStat(playCount: 5, listenedMs: 0),
        '3': const SongPlayStat(playCount: 5, listenedMs: 0),
      };
      final result = sortLibrarySongs(
        unsorted,
        SongSortOption.playCount,
        playStats: playStats,
      );
      expect(result.map((s) => s.id), ['2', '1', '3']);
    });
  });

  group('sortGroupNames', () {
    final groups = <String, List<Song>>{
      'The Killers': [
        _song(id: '1', title: 'a', artist: 'The Killers', album: 'x'),
        _song(id: '2', title: 'b', artist: 'The Killers', album: 'x'),
      ],
      'Franz Ferdinand': [
        _song(id: '3', title: 'c', artist: 'Franz Ferdinand', album: 'x'),
      ],
      'ABBA': [_song(id: '4', title: 'd', artist: 'ABBA', album: 'x')],
    };

    test('alphabetical sortira imena skupin, case-insensitive', () {
      final result = sortGroupNames(groups, GroupSortOption.alphabetical, {});
      expect(result, ['ABBA', 'Franz Ferdinand', 'The Killers']);
    });

    test('playCount sešteje metriko čez vse pesmi skupine, padajoče', () {
      final playStats = {
        '1': const SongPlayStat(playCount: 3, listenedMs: 0),
        '2': const SongPlayStat(playCount: 4, listenedMs: 0),
        '3': const SongPlayStat(playCount: 1, listenedMs: 0),
        // '4' (ABBA) brez vnosa - šteje kot 0.
      };
      final result = sortGroupNames(
        groups,
        GroupSortOption.playCount,
        playStats,
      );
      // The Killers: 3+4=7, Franz Ferdinand: 1, ABBA: 0.
      expect(result, ['The Killers', 'Franz Ferdinand', 'ABBA']);
    });

    test('listeningTime sešteje listenedMs čez vse pesmi skupine', () {
      final playStats = {
        '3': const SongPlayStat(playCount: 0, listenedMs: 500000),
        '1': const SongPlayStat(playCount: 0, listenedMs: 1000),
      };
      final result = sortGroupNames(
        groups,
        GroupSortOption.listeningTime,
        playStats,
      );
      expect(result.first, 'Franz Ferdinand');
    });

    test('izenačenje (vključno z 0) se razreši abecedno', () {
      final result = sortGroupNames(groups, GroupSortOption.playCount, {});
      expect(result, ['ABBA', 'Franz Ferdinand', 'The Killers']);
    });
  });
}
