// Generira Yearly Wrap Top-100 playliste (glej docs/spec-wrap.md
// "Top-100 playlists") preko obstoječih AppDatabase.createPlaylist/
// addSongToPlaylist - brez nove sheme. Kdaj se generiranje sproži (glede na
// WrapSettings.lastGeneratedAt) je odgovornost wrap_providers.dart, ne tega
// modula.

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';

const kWrapPlaylistLength = 100;

/// Sufiksira `desired` ime, če že obstaja v `existingNames`, z naraščajočim
/// števcem - "Wrap 2026" -> "Wrap 2026 (1)" -> "Wrap 2026 (2)" itd. Čista
/// funkcija, ločena od DB dostopa, da je testabilna brez `AppDatabase`.
String resolvePlaylistName(String desired, Set<String> existingNames) {
  if (!existingNames.contains(desired)) return desired;
  var counter = 1;
  while (existingNames.contains('$desired ($counter)')) {
    counter++;
  }
  return '$desired ($counter)';
}

/// Ustvari letno "posnetek stanja" playlisto (`Wrap <year>`) - ustvari se
/// enkrat in se je kasneje nikoli več ne dotika (glej spec), zato ob
/// imenskem trku sufiksiramo namesto prepisovanja.
Future<void> generateYearlySnapshotPlaylist({
  required AppDatabase database,
  required int year,
  required List<Song> topSongs,
}) async {
  final existingNames = await database.allPlaylistNames();
  final name = resolvePlaylistName('Wrap $year', existingNames);
  await _createPlaylistWithSongs(database, name, topSongs);
}

/// Ustvari (ali obnovi) "All-Time" playlisto - v nasprotju z letnim
/// posnetkom se ta ob vsaki regeneraciji v celoti izbriše in ustvari na
/// novo (ne inkrementalno posodablja), zato ohranja fiksno ime.
Future<void> generateAllTimePlaylist({
  required AppDatabase database,
  required List<Song> topSongs,
  String name = 'Wrap All-Time',
}) async {
  final existing = await database.findPlaylistByName(name);
  if (existing != null) {
    await database.deletePlaylist(existing.id);
  }
  await _createPlaylistWithSongs(database, name, topSongs);
}

Future<void> _createPlaylistWithSongs(
  AppDatabase database,
  String name,
  List<Song> songs,
) async {
  final playlistId = await database.createPlaylist(name);
  for (final song in songs.take(kWrapPlaylistLength)) {
    await database.addSongToPlaylist(playlistId, song);
  }
}
