// Unit testi za wrap_playlist_service.dart (glej docs/spec-wrap.md
// "Top-100 playlists") - name-collision sufiksiranje in dejansko
// ustvarjanje playlist preko in-memory AppDatabase, isti pattern kot
// audio_player_service_test.dart/widget_test.dart uporabljata za DB teste.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/db/app_database.dart';
import 'package:music_player/core/models/song.dart';
import 'package:music_player/features/wrap/wrap_playlist_service.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  filePath: '/music/$id.mp3',
);

void main() {
  group('resolvePlaylistName', () {
    test('no collision returns the desired name unchanged', () {
      expect(resolvePlaylistName('Wrap 2026', {}), 'Wrap 2026');
    });

    test('one collision appends (1)', () {
      expect(resolvePlaylistName('Wrap 2026', {'Wrap 2026'}), 'Wrap 2026 (1)');
    });

    test('multiple collisions pick the first free counter', () {
      expect(
        resolvePlaylistName('Wrap 2026', {
          'Wrap 2026',
          'Wrap 2026 (1)',
          'Wrap 2026 (2)',
        }),
        'Wrap 2026 (3)',
      );
    });
  });

  group('generateYearlySnapshotPlaylist', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => database.close());

    test(
      'creates a playlist named after the year with the given songs',
      () async {
        await generateYearlySnapshotPlaylist(
          database: database,
          year: 2026,
          topSongs: [_song('a'), _song('b')],
        );

        final playlist = await database.findPlaylistByName('Wrap 2026');
        expect(playlist, isNotNull);
        final songs = await database.watchPlaylistSongs(playlist!.id).first;
        expect(songs.map((s) => s.songId).toList(), ['a', 'b']);
      },
    );

    test(
      'suffixes the name when a playlist with that name already exists',
      () async {
        await database.createPlaylist('Wrap 2026');

        await generateYearlySnapshotPlaylist(
          database: database,
          year: 2026,
          topSongs: [_song('a')],
        );

        expect(await database.findPlaylistByName('Wrap 2026 (1)'), isNotNull);
      },
    );

    test('caps the playlist at the top-100 length', () async {
      final songs = [for (var i = 0; i < 150; i++) _song('$i')];

      await generateYearlySnapshotPlaylist(
        database: database,
        year: 2026,
        topSongs: songs,
      );

      final playlist = await database.findPlaylistByName('Wrap 2026');
      final result = await database.watchPlaylistSongs(playlist!.id).first;
      expect(result, hasLength(100));
    });
  });

  group('generateAllTimePlaylist', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('creates the playlist when none exists yet', () async {
      await generateAllTimePlaylist(database: database, topSongs: [_song('a')]);

      expect(await database.findPlaylistByName('Wrap All-Time'), isNotNull);
    });

    test('deletes and recreates an existing All-Time playlist instead of '
        'suffixing', () async {
      final oldId = await database.createPlaylist('Wrap All-Time');
      await database.addSongToPlaylist(oldId, _song('stale'));

      await generateAllTimePlaylist(
        database: database,
        topSongs: [_song('fresh')],
      );

      final names = await database.allPlaylistNames();
      expect(names.where((n) => n == 'Wrap All-Time'), hasLength(1));
      final playlist = await database.findPlaylistByName('Wrap All-Time');
      final songs = await database.watchPlaylistSongs(playlist!.id).first;
      expect(songs.map((s) => s.songId).toList(), ['fresh']);
    });
  });
}
