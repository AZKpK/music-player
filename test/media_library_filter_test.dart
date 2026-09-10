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
}) {
  return Song(id: id, title: title, artist: artist, album: album, filePath: '/tmp/$id.mp3');
}

void main() {
  final songs = [
    _song(id: '1', title: 'Mr. Brightside', artist: 'The Killers', album: 'Hot Fuss'),
    _song(id: '2', title: 'Take Me Out', artist: 'Franz Ferdinand', album: 'Franz Ferdinand'),
    _song(id: '3', title: 'Somebody Told Me', artist: 'The Killers', album: 'Hot Fuss'),
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
}
