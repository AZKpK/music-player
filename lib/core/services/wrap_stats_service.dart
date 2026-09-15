// Pure aggregation logic za Yearly Wrap (glej docs/spec-wrap.md
// "Aggregation") - brez Riverpod/DB uvozov, isti stil kot buildQueueWindow/
// buildPlayOrder v audio_player_service.dart, testabilno brez platform
// kanalov.

import '../db/app_database.dart';
import '../models/song.dart';

/// `true` = "poslušano vsaj 50% dolžine pesmi" šteje kot play, `false` =
/// "poslušano vsaj 60s" šteje kot play. Odločitev iz build-stage spike-a
/// (glej plan-wrap.md korak 1) - obe veji sta specificirani v
/// docs/spec-wrap.md, ta izbira ne vpliva na `_lastKnownPosition` mehanizem.
const kUseDurationPercentThreshold = true;

bool isCountedPlay(int msListened, int trackDurationMs) {
  if (kUseDurationPercentThreshold) {
    return trackDurationMs > 0 && msListened >= trackDurationMs * 0.5;
  }
  return msListened >= 60000;
}

class WrapSongStat {
  const WrapSongStat({required this.song, required this.playCount});

  final Song song;
  final int playCount;
}

class WrapNamedStat {
  const WrapNamedStat({required this.name, required this.playCount});

  final String name;
  final int playCount;
}

class WrapStats {
  const WrapStats({
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.totalListened,
    this.topGenre,
  });

  /// Padajoče po `playCount`, brez omejitve dolžine - UI (wrap_screen.dart)
  /// izreže toliko, kolikor jih dejansko prikaže.
  final List<WrapSongStat> topSongs;
  final List<WrapNamedStat> topArtists;
  final List<WrapNamedStat> topAlbums;

  /// Vsota `msListened` čez VSE vnose, ne glede na [isCountedPlay] - glej
  /// spec: "Total minutes listened is never gated by this".
  final Duration totalListened;

  /// `null`, če je `genreEnabled` `false` ali če noben šteti play nima
  /// znanega žanra.
  final String? topGenre;
}

/// Agregira `entries` (že filtrirane na eno wrap leto) v [WrapStats].
///
/// Pesmi, ki jih `libraryById` ne razreši (izbrisana datoteka), se štejejo
/// v `totalListened` (ta je nefiltriran seštevek), ne pa tudi v top
/// pesmi/izvajalce/albume/žanr - `PlayHistoryEntries` ne hrani imena
/// izvajalca/albuma/žanra samega, zato brez ujemanja v knjižnici te
/// informacije preprosto ni na voljo.
WrapStats computeWrapStats({
  required List<PlayHistoryEntry> entries,
  required Map<String, Song> libraryById,
  bool genreEnabled = false,
}) {
  final totalListenedMs = entries.fold<int>(
    0,
    (sum, entry) => sum + entry.msListened,
  );

  final songPlayCounts = <String, int>{};
  final artistPlayCounts = <String, int>{};
  final albumPlayCounts = <String, int>{};
  final genrePlayCounts = <String, int>{};

  for (final entry in entries) {
    if (!isCountedPlay(entry.msListened, entry.trackDurationMs)) continue;
    final song = libraryById[entry.songId];
    if (song == null) continue;

    songPlayCounts.update(
      song.id,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    artistPlayCounts.update(
      song.artist,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    albumPlayCounts.update(
      song.album,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (genreEnabled && song.genre != null) {
      genrePlayCounts.update(
        song.genre!,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  final topSongs = songPlayCounts.entries
      .map(
        (e) => WrapSongStat(song: libraryById[e.key]!, playCount: e.value),
      )
      .toList()
    ..sort(
      (a, b) => _compareStats(
        a.playCount,
        b.playCount,
        a.song.title,
        b.song.title,
      ),
    );

  final topArtists = _sortedNamedStats(artistPlayCounts);
  final topAlbums = _sortedNamedStats(albumPlayCounts);

  String? topGenre;
  if (genreEnabled && genrePlayCounts.isNotEmpty) {
    topGenre = _sortedNamedStats(genrePlayCounts).first.name;
  }

  return WrapStats(
    topSongs: topSongs,
    topArtists: topArtists,
    topAlbums: topAlbums,
    totalListened: Duration(milliseconds: totalListenedMs),
    topGenre: topGenre,
  );
}

List<WrapNamedStat> _sortedNamedStats(Map<String, int> counts) {
  return counts.entries
      .map((e) => WrapNamedStat(name: e.key, playCount: e.value))
      .toList()
    ..sort((a, b) => _compareStats(a.playCount, b.playCount, a.name, b.name));
}

/// Padajoče po count-u; ob izenačenju abecedno po imenu za determinističen
/// vrstni red (potreben za teste in stabilen UI).
int _compareStats(int countA, int countB, String nameA, String nameB) {
  final countCompare = countB.compareTo(countA);
  if (countCompare != 0) return countCompare;
  return nameA.compareTo(nameB);
}
