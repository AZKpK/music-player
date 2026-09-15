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
@TableIndex(
  name: 'playlist_songs_playlist_position',
  columns: {#playlistId, #position},
)
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

/// Uporabniško ročno urejeni podatki o eni pesmi (naslov/album/artist/genre/
/// leto/track number/liked/naslovnica), ki nadgradijo/prepišejo osnovne
/// podatke iz MediaStore (glej `media_library_providers.dart` -
/// `librarySongsProvider` združi to tabelo z rezultati `on_audio_query`-ja).
/// Vsa polja razen `songId` so nullable - `null` pomeni "ni ročno urejeno,
/// uporabi original".
class SongOverrides extends Table {
  TextColumn get songId => text()();
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  BoolColumn get liked => boolean().withDefault(const Constant(false))();
  TextColumn get artworkPath => text().nullable()();

  /// Pesem je bila izbrisana preko app-a (glej `hideSong`) - filtriramo jo
  /// iz knjižnice ne glede na to, ali MediaStore še vrača (stale) zapis
  /// zanjo (indeks se osveži šele ob naslednjem media scan-u).
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {songId};
}

/// Ročno določena slika izvajalca ali albuma.
class GroupArtworks extends Table {
  TextColumn get groupType => text()();
  TextColumn get groupKey => text()();
  TextColumn get artworkPath => text()();

  @override
  Set<Column> get primaryKey => {groupType, groupKey};
}

/// One recorded play of a song. Deliberately thin — unlike `PlaylistSongs`,
/// which duplicates title/artist/album because MediaStore ids aren't a
/// stable long-term reference, play events are far more numerous than
/// playlist rows, so metadata is resolved by joining the current library
/// at read time instead of being copied per row.
@TableIndex(name: 'play_history_played_at', columns: {#playedAt})
class PlayHistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get msListened => integer()();
  // Captured at play time (not re-read from the library later), so the
  // "was this a countable play" rule stays correct even if a file is later
  // deleted/replaced.
  IntColumn get trackDurationMs => integer()();
}

/// Single-row table for wrap-related settings. Reuses drift (already a
/// dependency, already the pattern for local app state) instead of adding
/// `shared_preferences` for two small values.
class WrapSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get genreEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get resetMonth => integer().withDefault(const Constant(1))();
  IntColumn get resetDay => integer().withDefault(const Constant(1))();
  // Last time the yearly snapshot/all-time playlists were (re)generated -
  // compared against the reset-date boundary to decide whether opening the
  // wrap screen should trigger regeneration.
  DateTimeColumn get lastGeneratedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Playlists,
    PlaylistSongs,
    SongOverrides,
    GroupArtworks,
    PlayHistoryEntries,
    WrapSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(songOverrides);
      }
      if (from < 3) {
        await m.createTable(groupArtworks);
      }
      if (from < 4) {
        await customStatement(
          'CREATE INDEX playlist_songs_playlist_position '
          'ON playlist_songs (playlist_id, position)',
        );
      }
      if (from < 5) {
        await m.createTable(playHistoryEntries);
        await m.createTable(wrapSettings);
      }
    },
  );

  /// Vse playliste, sortirane po imenu.
  Stream<List<Playlist>> watchAllPlaylists() {
    return (select(
      playlists,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
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
    return (update(playlists)..where((t) => t.id.equals(id))).write(
      PlaylistsCompanion(name: Value(newName)),
    );
  }

  Future<void> deletePlaylist(int id) {
    return (delete(playlists)..where((t) => t.id.equals(id))).go();
  }

  /// Doda pesem na konec playliste.
  Future<void> addSongToPlaylist(int playlistId, Song song) async {
    final lastSong =
        await (select(playlistSongs)
              ..where((song) => song.playlistId.equals(playlistId))
              ..orderBy([
                (song) => OrderingTerm(
                  expression: song.position,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    await into(playlistSongs).insert(
      PlaylistSongsCompanion.insert(
        playlistId: playlistId,
        position: (lastSong?.position ?? -1) + 1,
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
    return (delete(
      playlistSongs,
    )..where((t) => t.id.equals(playlistSongRowId))).go();
  }

  /// Vsi ročni popravki metapodatkov, ključani po `songId` - za reaktivno
  /// spajanje z osnovno MediaStore knjižnico v `librarySongsProvider`.
  Stream<Map<String, SongOverride>> watchAllOverrides() {
    return select(
      songOverrides,
    ).watch().map((rows) => {for (final row in rows) row.songId: row});
  }

  /// Delno posodobi (ali ustvari) popravek za eno pesem - polja, ki niso
  /// podana v `companion`, ostanejo nespremenjena (ali `null`/`false` privzeto
  /// ob prvem ustvarjanju vrstice).
  Future<void> upsertOverride(SongOverridesCompanion companion) {
    return into(songOverrides).insertOnConflictUpdate(companion);
  }

  Stream<Map<GroupArtworkKey, GroupArtwork>> watchAllGroupArtworks() {
    return select(groupArtworks).watch().map(
      (rows) => {
        for (final row in rows)
          GroupArtworkKey(row.groupType, row.groupKey): row,
      },
    );
  }

  Future<void> upsertGroupArtwork({
    required String groupType,
    required String groupKey,
    required String artworkPath,
  }) {
    return into(groupArtworks).insertOnConflictUpdate(
      GroupArtworksCompanion.insert(
        groupType: groupType,
        groupKey: groupKey,
        artworkPath: artworkPath,
      ),
    );
  }

  Future<void> removeGroupArtwork({
    required String groupType,
    required String groupKey,
  }) {
    return (delete(groupArtworks)..where(
          (row) =>
              row.groupType.equals(groupType) & row.groupKey.equals(groupKey),
        ))
        .go();
  }

  Future<void> setLiked(String songId, bool liked) {
    return upsertOverride(
      SongOverridesCompanion(songId: Value(songId), liked: Value(liked)),
    );
  }

  /// Označi pesem kot izbrisano (filtrirana iz knjižnice) in jo odstrani iz
  /// vseh playlist. Dejansko brisanje datoteke z diska se zgodi ločeno v
  /// UI plasti (glej `library_screen.dart` - `_deleteSong`), ker DB razred
  /// namerno ne dostopa do datotečnega sistema.
  Future<void> hideSongEverywhere(String songId) async {
    await upsertOverride(
      SongOverridesCompanion(songId: Value(songId), hidden: const Value(true)),
    );
    await (delete(playlistSongs)..where((t) => t.songId.equals(songId))).go();
  }

  /// Zabeleži en play (glej `AudioPlayerHandler._recordPlay` -
  /// `audio_player_service.dart`) - fire-and-forget klic z vira, ne sme
  /// blokirati predvajanja.
  Future<void> recordPlay(PlayHistoryEntriesCompanion entry) {
    return into(playHistoryEntries).insert(entry);
  }
}

/// Sestavljen ključ za reaktivni zemljevid [GroupArtworks].
class GroupArtworkKey {
  const GroupArtworkKey(this.groupType, this.groupKey);

  final String groupType;
  final String groupKey;

  @override
  bool operator ==(Object other) =>
      other is GroupArtworkKey &&
      other.groupType == groupType &&
      other.groupKey == groupKey;

  @override
  int get hashCode => Object.hash(groupType, groupKey);
}

/// Pretvori shranjeno vrstico playliste nazaj v [Song] za predvajanje.
Song playlistSongToSong(PlaylistSong row) => Song(
  id: row.songId,
  title: row.title,
  artist: row.artist,
  album: row.album,
  filePath: row.filePath,
  duration: row.durationMs != null
      ? Duration(milliseconds: row.durationMs!)
      : null,
);

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'music_player.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
