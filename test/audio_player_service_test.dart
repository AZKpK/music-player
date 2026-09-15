// Unit test za `buildPlayOrder` (P0/N2 - shuffle model, glej
// docs/plan1.1.md #15). Testira samo čisto funkcijo, ne `AudioPlayerHandler`
// v celoti - ta je odvisen od `just_audio`/`audio_service` platform-channel-ov,
// ki v testnem okolju niso na voljo (glej `widget_test.dart`).

import 'dart:math';

import 'package:audio_service/audio_service.dart';
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
    test('restores the exact source order while keeping the current entry', () {
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

      expect(result.map((e) => e.song.id).toList(), ['a', 'b', 'c', 'd', 'e']);
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

  group('buildInitialQueue', () {
    test('keeps a short album intact and starts at the selected song', () {
      final songs = [
        _song('a'),
        _song('b'),
        _song('c'),
        _song('d'),
        _song('e'),
      ];

      final result = buildInitialQueue(songs: songs, startIndex: 3);

      expect(result.songs.map((song) => song.id).toList(), [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(result.initialIndex, 3);
    });

    test('uses a bounded window for a large library', () {
      final songs = [for (var i = 0; i < 300; i++) _song('$i')];

      final result = buildInitialQueue(songs: songs, startIndex: 275);

      expect(result.songs, hasLength(25));
      expect(result.songs.first.id, '275');
      expect(result.songs.last.id, '299');
      expect(result.initialIndex, 0);
    });
  });

  group('buildShuffledQueueWindow', () {
    test(
      'keeps the selected song first and samples beyond the next window',
      () {
        final songs = [for (var i = 0; i < 300; i++) _song('$i')];

        final result = buildShuffledQueueWindow(
          songs,
          0,
          maxLength: 250,
          random: Random(42),
        );

        expect(result, hasLength(250));
        expect(result.first.id, '0');
        expect(result.map((song) => song.id).toSet(), hasLength(250));
        expect(result.skip(1).any((song) => int.parse(song.id) >= 250), isTrue);
      },
    );

    test('keeps only the bounded sample for a large library', () {
      final songs = [for (var i = 0; i < 10 * 1000; i++) _song('$i')];

      final result = buildShuffledQueueWindow(
        songs,
        5000,
        maxLength: 250,
        random: Random(42),
      );

      expect(result, hasLength(250));
      expect(result.first.id, '5000');
      expect(result.map((song) => song.id).toSet(), hasLength(250));
    });

    test('does not add songs when the selected song is the only one', () {
      final songs = [_song('a')];

      expect(buildShuffledQueueWindow(songs, 0, random: Random(1)), [
        songs.first,
      ]);
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

  group('updateQueueItemDuration', () {
    MediaItem item(String id, int queueItemId, [Duration? duration]) =>
        MediaItem(
          id: id,
          title: id,
          duration: duration,
          extras: {queueItemIdExtraKey: queueItemId},
        );

    test('updates only the matching queue entry when a duration arrives', () {
      final items = [item('same-song', 10), item('same-song', 11)];

      final result = updateQueueItemDuration(
        items,
        11,
        const Duration(minutes: 3, seconds: 42),
      );

      expect(result[0].duration, isNull);
      expect(result[1].duration, const Duration(minutes: 3, seconds: 42));
      expect(result[1].extras?[queueItemIdExtraKey], 11);
    });

    test('leaves the original queue untouched when the entry is absent', () {
      final items = [item('song', 10)];

      expect(
        identical(
          updateQueueItemDuration(items, 99, const Duration(seconds: 1)),
          items,
        ),
        isTrue,
      );
    });
  });

  group('buildPlayHistoryEntry', () {
    test('captures songId, msListened and playedAt from the arguments', () {
      final outgoing = MediaItem(
        id: 'song-a',
        title: 'Song A',
        duration: const Duration(minutes: 3),
      );
      final playedAt = DateTime(2026, 9, 15, 12, 0);

      final entry = buildPlayHistoryEntry(
        outgoing: outgoing,
        msListened: const Duration(seconds: 90),
        playedAt: playedAt,
      );

      expect(entry.songId.value, 'song-a');
      expect(entry.msListened.value, 90000);
      expect(entry.trackDurationMs.value, 180000);
      expect(entry.playedAt.value, playedAt);
    });

    test('falls back to 0 trackDurationMs when duration is unknown', () {
      final outgoing = MediaItem(id: 'song-a', title: 'Song A');

      final entry = buildPlayHistoryEntry(
        outgoing: outgoing,
        msListened: const Duration(seconds: 5),
        playedAt: DateTime(2026, 9, 15),
      );

      expect(entry.trackDurationMs.value, 0);
    });
  });

  group('isRealSongTransition', () {
    MediaItem item(String id, int queueItemId) => MediaItem(
      id: id,
      title: id,
      extras: {queueItemIdExtraKey: queueItemId},
    );

    test('false when outgoing is null (nothing was playing yet)', () {
      expect(
        isRealSongTransition(outgoing: null, incoming: item('a', 0)),
        isFalse,
      );
    });

    test('false when outgoing and incoming are the same queue entry', () {
      expect(
        isRealSongTransition(outgoing: item('a', 0), incoming: item('a', 0)),
        isFalse,
      );
    });

    test('true when outgoing and incoming differ', () {
      expect(
        isRealSongTransition(outgoing: item('a', 0), incoming: item('b', 1)),
        isTrue,
      );
    });
  });

  group('isLoopOneRepeat', () {
    test('false when repeat mode is not one', () {
      expect(
        isLoopOneRepeat(
          repeatMode: AudioServiceRepeatMode.all,
          previousPosition: const Duration(minutes: 3),
          newPosition: Duration.zero,
        ),
        isFalse,
      );
    });

    test('true on a backward jump to near-zero from a real position', () {
      expect(
        isLoopOneRepeat(
          repeatMode: AudioServiceRepeatMode.one,
          previousPosition: const Duration(minutes: 3),
          newPosition: Duration.zero,
        ),
        isTrue,
      );
    });

    test('false during normal forward playback', () {
      expect(
        isLoopOneRepeat(
          repeatMode: AudioServiceRepeatMode.one,
          previousPosition: const Duration(seconds: 10),
          newPosition: const Duration(seconds: 11),
        ),
        isFalse,
      );
    });

    test('false for a manual rewind that does not land near zero', () {
      expect(
        isLoopOneRepeat(
          repeatMode: AudioServiceRepeatMode.one,
          previousPosition: const Duration(minutes: 4),
          newPosition: const Duration(minutes: 3, seconds: 55),
        ),
        isFalse,
      );
    });

    test('false when previous position was already near the start', () {
      expect(
        isLoopOneRepeat(
          repeatMode: AudioServiceRepeatMode.one,
          previousPosition: const Duration(seconds: 1),
          newPosition: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('isBackwardJumpToStart', () {
    // Deljena logika z isLoopOneRepeat (glej `_handlePositionChanged`), a
    // brez repeatMode omejitve - uporablja se tudi za normalne prehode na
    // naslednjo pesem, kjer just_audio sprosti positionStream dogodek na ~0
    // preden currentIndexStream ujame prehod.
    test('true on a backward jump to near-zero from a real position', () {
      expect(
        isBackwardJumpToStart(
          previousPosition: const Duration(minutes: 3),
          newPosition: Duration.zero,
        ),
        isTrue,
      );
    });

    test('false during normal forward playback', () {
      expect(
        isBackwardJumpToStart(
          previousPosition: const Duration(seconds: 10),
          newPosition: const Duration(seconds: 11),
        ),
        isFalse,
      );
    });

    test('false when previous position was already near the start', () {
      expect(
        isBackwardJumpToStart(
          previousPosition: const Duration(seconds: 1),
          newPosition: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('updateListenedAccumulator', () {
    test('opens a segment on transition to active', () {
      final now = DateTime(2026, 9, 15, 12, 0, 0);
      final result = updateListenedAccumulator(
        current: const ListenedAccumulator(),
        active: true,
        now: now,
      );

      expect(result.total, Duration.zero);
      expect(result.activeSegmentStart, now);
    });

    test('closes a segment on transition to inactive, folding elapsed time in', () {
      final start = DateTime(2026, 9, 15, 12, 0, 0);
      final now = start.add(const Duration(seconds: 5));
      final result = updateListenedAccumulator(
        current: ListenedAccumulator(activeSegmentStart: start),
        active: false,
        now: now,
      );

      expect(result.total, const Duration(seconds: 5));
      expect(result.activeSegmentStart, isNull);
    });

    test('is a no-op when already active and stays active', () {
      final start = DateTime(2026, 9, 15, 12, 0, 0);
      final current = ListenedAccumulator(
        total: const Duration(seconds: 2),
        activeSegmentStart: start,
      );
      final result = updateListenedAccumulator(
        current: current,
        active: true,
        now: start.add(const Duration(seconds: 3)),
      );

      expect(result.total, const Duration(seconds: 2));
      expect(result.activeSegmentStart, start);
    });

    test('is a no-op when already inactive and stays inactive', () {
      const current = ListenedAccumulator(total: Duration(seconds: 2));
      final result = updateListenedAccumulator(
        current: current,
        active: false,
        now: DateTime(2026, 9, 15, 12, 0, 0),
      );

      expect(result.total, const Duration(seconds: 2));
      expect(result.activeSegmentStart, isNull);
    });
  });

  group('consumeListenedDuration', () {
    test('returns zero and an empty remainder when nothing was accumulated', () {
      final result = consumeListenedDuration(
        current: const ListenedAccumulator(),
        now: DateTime(2026, 9, 15, 12, 0, 0),
      );

      expect(result.duration, Duration.zero);
      expect(result.remainder.total, Duration.zero);
      expect(result.remainder.activeSegmentStart, isNull);
    });

    test('returns the accumulated total when no segment is open', () {
      final result = consumeListenedDuration(
        current: const ListenedAccumulator(total: Duration(seconds: 90)),
        now: DateTime(2026, 9, 15, 12, 0, 0),
      );

      expect(result.duration, const Duration(seconds: 90));
      expect(result.remainder.total, Duration.zero);
      expect(result.remainder.activeSegmentStart, isNull);
    });

    test(
      'flushes an open segment into the total and restarts it at now, '
      'instead of closing it, since a track transition does not itself '
      'pause playback',
      () {
        final start = DateTime(2026, 9, 15, 12, 0, 0);
        final now = start.add(const Duration(seconds: 4));
        final result = consumeListenedDuration(
          current: ListenedAccumulator(
            total: const Duration(seconds: 10),
            activeSegmentStart: start,
          ),
          now: now,
        );

        expect(result.duration, const Duration(seconds: 14));
        expect(result.remainder.total, Duration.zero);
        expect(result.remainder.activeSegmentStart, now);
      },
    );

    test(
      'seek then transition within a few seconds: listened reflects only '
      'the active playback time, not the seeked position',
      () {
        // A seek does not itself change player state, so the active segment
        // that started at play-begin is still open when the transition
        // happens - only the wall-clock time since then is counted,
        // regardless of where the seek landed in the track.
        final playStarted = DateTime(2026, 9, 15, 12, 0, 0);
        final transitionedAfterSeek = playStarted.add(
          const Duration(seconds: 5),
        );
        final result = consumeListenedDuration(
          current: ListenedAccumulator(activeSegmentStart: playStarted),
          now: transitionedAfterSeek,
        );

        expect(result.duration, const Duration(seconds: 5));
      },
    );
  });
}
