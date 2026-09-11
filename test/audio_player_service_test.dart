// Unit test za `buildPlayOrder` (P0/N2 - shuffle model, glej
// docs/plan1.1.md #15). Testira samo čisto funkcijo, ne `AudioPlayerHandler`
// v celoti - ta je odvisen od `just_audio`/`audio_service` platform-channel-ov,
// ki v testnem okolju niso na voljo (glej `widget_test.dart`).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/models/song.dart';
import 'package:music_player/core/services/audio_player_service.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  filePath: '/music/$id.mp3',
);

void main() {
  group('buildPlayOrder - shuffle off', () {
    test('current song stays first, followed by source order after it, '
        'wrapping to before it', () {
      final source = [
        QueueEntry(_song('a'), 0),
        QueueEntry(_song('b'), 1),
        QueueEntry(_song('c'), 2),
        QueueEntry(_song('d'), 3),
        QueueEntry(_song('e'), 4),
      ];
      final current = source[2]; // 'c'

      final result = buildPlayOrder(
        sourceOrder: source,
        current: current,
        shuffled: false,
      );

      expect(result.map((e) => e.song.id).toList(), ['c', 'd', 'e', 'a', 'b']);
    });

    test('current song already first is a no-op reordering', () {
      final source = [
        QueueEntry(_song('a'), 0),
        QueueEntry(_song('b'), 1),
        QueueEntry(_song('c'), 2),
      ];

      final result = buildPlayOrder(
        sourceOrder: source,
        current: source[0],
        shuffled: false,
      );

      expect(result.map((e) => e.song.id).toList(), ['a', 'b', 'c']);
    });
  });

  group('buildPlayOrder - shuffle on', () {
    test('current song stays first, remaining songs are a shuffled '
        'permutation of the rest', () {
      final source = [
        QueueEntry(_song('a'), 0),
        QueueEntry(_song('b'), 1),
        QueueEntry(_song('c'), 2),
        QueueEntry(_song('d'), 3),
        QueueEntry(_song('e'), 4),
      ];
      final current = source[1]; // 'b'

      final result = buildPlayOrder(
        sourceOrder: source,
        current: current,
        shuffled: true,
        random: Random(42),
      );

      expect(result.first.song.id, 'b');
      expect(
        result.map((e) => e.queueItemId).toSet(),
        source.map((e) => e.queueItemId).toSet(),
      );
      // Deterministična (seeded) primerjava - z drugim seedom bi lahko
      // naključno vrnila isti vrstni red kot vhod, zato preverimo samo,
      // da rezultat ni preprosto "current + nespremenjen rep".
      expect(
        result.map((e) => e.song.id).toList(),
        isNot(['b', 'a', 'c', 'd', 'e']),
      );
    });

    test('single-song queue returns just the current song', () {
      final source = [QueueEntry(_song('a'), 0)];

      final result = buildPlayOrder(
        sourceOrder: source,
        current: source[0],
        shuffled: true,
        random: Random(1),
      );

      expect(result.map((e) => e.song.id).toList(), ['a']);
    });
  });

  group('buildQueueWindow', () {
    test('empty input returns empty list', () {
      expect(buildQueueWindow([], 0), isEmpty);
    });

    test('maxLength > remaining length returns songs through the end', () {
      final songs = [_song('a'), _song('b'), _song('c')];

      final result = buildQueueWindow(songs, 1, maxLength: 10);

      expect(result.map((s) => s.id).toList(), ['b', 'c']);
    });

    test('starting at the last song returns only that song', () {
      final songs = [_song('a'), _song('b'), _song('c')];

      final result = buildQueueWindow(songs, 2, maxLength: 3);

      expect(result.map((s) => s.id).toList(), ['c']);
    });

    test('maxLength < length returns a partial window', () {
      final songs = [
        _song('a'),
        _song('b'),
        _song('c'),
        _song('d'),
        _song('e'),
      ];

      final result = buildQueueWindow(songs, 3, maxLength: 4);

      expect(result.map((s) => s.id).toList(), ['d', 'e']);
    });

    test('startIndex = 0 starts at the beginning', () {
      final songs = [_song('a'), _song('b'), _song('c')];

      final result = buildQueueWindow(songs, 0, maxLength: 2);

      expect(result.map((s) => s.id).toList(), ['a', 'b']);
    });

    test('startIndex = last index does not wrap around', () {
      final songs = [_song('a'), _song('b'), _song('c')];

      final result = buildQueueWindow(songs, 2, maxLength: 2);

      expect(result.map((s) => s.id).toList(), ['c']);
    });

    test('does not wrap around the end of the list', () {
      final songs = [
        _song('a'),
        _song('b'),
        _song('c'),
        _song('d'),
        _song('e'),
      ];

      final result = buildQueueWindow(songs, 4, maxLength: 4);

      expect(result.map((s) => s.id).toList(), ['e']);
    });
  });

  group('duplicate queue entries', () {
    test('same song added twice gets distinct queueItemIds', () {
      final song = _song('a');
      final first = QueueEntry(song, 0);
      final second = QueueEntry(song, 1);

      expect(first.song.id, second.song.id);
      expect(first.queueItemId, isNot(second.queueItemId));
    });

    test('buildPlayOrder keeps both duplicate entries distinct and in '
        'source order when shuffle is off', () {
      final song = _song('a');
      final source = [
        QueueEntry(song, 0),
        QueueEntry(_song('b'), 1),
        QueueEntry(song, 2),
      ];

      final result = buildPlayOrder(
        sourceOrder: source,
        current: source[0],
        shuffled: false,
      );

      expect(result.map((e) => e.queueItemId).toList(), [0, 1, 2]);
    });
  });
}
