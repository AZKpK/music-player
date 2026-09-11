// Unit test za `filterLibrarySongs` (Faza 6.3 - iskanje po knjižnici).
// Namerno testira samo čisto funkcijo, ne providerje - `librarySongsProvider`
// je odvisen od `on_audio_query`/drift platform-channel-ov, ki v testnem
// okolju niso na voljo (glej `widget_test.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/models/song.dart';
import 'package:music_player/core/services/media_library_providers.dart';

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
  });
}
