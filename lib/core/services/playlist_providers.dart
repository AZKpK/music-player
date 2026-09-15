import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import 'wrap_stats_service.dart';

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

final playlistSongsProvider = StreamProvider.family<List<PlaylistSong>, int>((
  ref,
  playlistId,
) {
  return ref.watch(appDatabaseProvider).watchPlaylistSongs(playlistId);
});

/// Vsi zapisi predvajanja, brez omejitve na wrap obdobje - podlaga za
/// "sortiraj po št. predvajanj/času poslušanja" izven wrap_screen.dart (glej
/// docs/faza2-wrap/intent3.md). Ločeno od `currentPeriodPlayHistoryProvider`
/// (wrap_providers.dart), ki je namerno omejen na trenutno wrap obdobje.
final allTimePlayHistoryProvider = StreamProvider<List<PlayHistoryEntry>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).watchPlayHistoryEntries();
});

/// `songId -> SongPlayStat` čez celotno zgodovino - glej [computeSongPlayStats].
final songPlayStatsProvider = Provider<Map<String, SongPlayStat>>((ref) {
  final entries = ref.watch(allTimePlayHistoryProvider).valueOrNull ?? const [];
  return computeSongPlayStats(entries);
});

/// `playlist.id -> SongPlayStat`, agregirano čez playlistine pesmi (vsota
/// [songPlayStatsProvider] za vsak `songId` v playlisti) - za sortiranje
/// zavihka "Playliste" po št. predvajanj/času poslušanja (glej
/// docs/faza2-wrap/intent3.md). Sistemska "Priljubljene pesmi" playlista ni
/// vključena, ker ni `Playlist` vrstica (glej playlists_screen.dart).
final playlistPlayStatsProvider = Provider<Map<int, SongPlayStat>>((ref) {
  final playlists = ref.watch(playlistsProvider).valueOrNull ?? const [];
  final songStats = ref.watch(songPlayStatsProvider);

  return {
    for (final playlist in playlists)
      playlist.id: _aggregatePlaylistStat(
        ref.watch(playlistSongsProvider(playlist.id)).valueOrNull ?? const [],
        songStats,
      ),
  };
});

SongPlayStat _aggregatePlaylistStat(
  List<PlaylistSong> songs,
  Map<String, SongPlayStat> songStats,
) {
  var playCount = 0;
  var listenedMs = 0;
  for (final song in songs) {
    final stat = songStats[song.songId];
    if (stat == null) continue;
    playCount += stat.playCount;
    listenedMs += stat.listenedMs;
  }
  return SongPlayStat(playCount: playCount, listenedMs: listenedMs);
}

/// Izbrani kriterij razvrščanja zavihka "Playliste" (glej `sortPlaylists`),
/// privzeto abecedno.
final playlistSortProvider = StateProvider<GroupSortOption>(
  (ref) => GroupSortOption.alphabetical,
);

/// Čista sort funkcija za zavihek "Playliste" - ločena od providerja, da je
/// testabilna brez platform-channel/DB odvisnosti (isti razlog kot
/// `sortLibrarySongs`/`sortGroupNames` v media_library_providers.dart).
List<Playlist> sortPlaylists(
  List<Playlist> playlists,
  GroupSortOption option,
  Map<int, SongPlayStat> stats,
) {
  final sorted = [...playlists];
  switch (option) {
    case GroupSortOption.alphabetical:
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case GroupSortOption.playCount:
    case GroupSortOption.listeningTime:
      int metricFor(Playlist playlist) {
        final stat = stats[playlist.id];
        if (stat == null) return 0;
        return option == GroupSortOption.listeningTime
            ? stat.listenedMs
            : stat.playCount;
      }

      sorted.sort((a, b) {
        final cmp = metricFor(b).compareTo(metricFor(a));
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }
  return sorted;
}
