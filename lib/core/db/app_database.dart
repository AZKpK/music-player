import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

part 'app_database.g.dart';

/// Uporabniško ustvarjene playliste.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Pesmi znotraj posamezne playliste. Podatki o pesmi (naslov/artist/album/
/// pot/trajanje) so namerno podvojeni sem (namesto foreign-key na knjižnico),
/// ker `on_audio_query`-jevi MediaStore ID-ji niso stabilna trajna referenca
/// (album/artist se lahko spremenijo ob ponovnem indeksiranju naprave) -
/// playlista mora ostati uporabna tudi če se knjižnica spremeni.
class PlaylistSongs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get songId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get filePath => text()();
  IntColumn get durationMs => integer().nullable()();
}

@DriftDatabase(tables: [Playlists, PlaylistSongs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 1;

  /// Vse playliste, sortirane po imenu.
  Stream<List<Playlist>> watchAllPlaylists() {
    return (select(playlists)..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  /// Pesmi znotraj playliste, sortirane po vrstnem redu dodajanja.
  Stream<List<PlaylistSong>> watchPlaylistSongs(int playlistId) {
    return (select(playlistSongs)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  }

  Future<int> createPlaylist(String name) {
    return into(playlists).insert(PlaylistsCompanion.insert(name: name));
  }

  Future<void> renamePlaylist(int id, String newName) {
    return (update(playlists)..where((t) => t.id.equals(id)))
        .write(PlaylistsCompanion(name: Value(newName)));
  }

  Future<void> deletePlaylist(int id) {
    return (delete(playlists)..where((t) => t.id.equals(id))).go();
  }

  /// Doda pesem na konec playliste.
  Future<void> addSongToPlaylist(int playlistId, Song song) async {
    final currentCount = await (selectOnly(playlistSongs)
          ..addColumns([playlistSongs.id.count()])
          ..where(playlistSongs.playlistId.equals(playlistId)))
        .map((row) => row.read(playlistSongs.id.count()) ?? 0)
        .getSingle();

    await into(playlistSongs).insert(
      PlaylistSongsCompanion.insert(
        playlistId: playlistId,
        position: currentCount,
        songId: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        filePath: song.filePath,
        durationMs: Value(song.duration?.inMilliseconds),
      ),
    );
  }

  Future<void> removeSongFromPlaylist(int playlistSongRowId) {
    return (delete(playlistSongs)..where((t) => t.id.equals(playlistSongRowId))).go();
  }
}

/// Pretvori shranjeno vrstico playliste nazaj v [Song] za predvajanje.
Song playlistSongToSong(PlaylistSong row) => Song(
      id: row.songId,
      title: row.title,
      artist: row.artist,
      album: row.album,
      filePath: row.filePath,
      duration: row.durationMs != null ? Duration(milliseconds: row.durationMs!) : null,
    );

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'music_player.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
