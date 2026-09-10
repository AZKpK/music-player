import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';

/// Ena instanca [AppDatabase] za celotno app-life-time; zapre povezavo, ko
/// provider ni več v uporabi (v praksi šele ob koncu app-a, ker je overriden
/// v main() in nikoli disposed prej).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  return ref.watch(appDatabaseProvider).watchAllPlaylists();
});

final playlistSongsProvider =
    StreamProvider.family<List<PlaylistSong>, int>((ref, playlistId) {
  return ref.watch(appDatabaseProvider).watchPlaylistSongs(playlistId);
});
