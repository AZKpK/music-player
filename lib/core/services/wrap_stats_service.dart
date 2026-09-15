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

/// Kriterij razvrščanja `WrapStats.topSongs` (glej
/// `docs/faza2-wrap/spec-wrap2.md` "Wrap song ordering") - vpliva samo na
/// pesmi, `topArtists`/`topAlbums` ostajata vedno razvrščena po `playCount`.
enum WrapSongSortOption { playCount, listeningTime }

/// Kriterij razvrščanja skupin (izvajalci/playliste) izven wrap_screen.dart
/// (glej docs/faza2-wrap/intent3.md) - `alphabetical` je privzeta vrednost za
/// oba klicatelja (library_screen.dart/playlists_screen.dart).
enum GroupSortOption { alphabetical, playCount, listeningTime }

/// All-time (ne omejeno na eno wrap obdobje) play count in `listenedMs` za
/// eno pesem - glej [computeSongPlayStats]. Ista oblika kot `WrapSongStat`,
/// a brez `song` reference, ker se uporablja tudi za agregacijo izvajalcev/
/// playlist (kjer je potrebna samo metrika, ne posamezna pesem).
class SongPlayStat {
  const SongPlayStat({required this.playCount, required this.listenedMs});

  final int playCount;
  final int listenedMs;
}

/// `songId -> SongPlayStat` čez CEL `entries` (brez omejitve na wrap obdobje)
/// - uporabljeno za "sortiraj po št. predvajanj/času poslušanja" izven
/// wrap_screen.dart (library_screen.dart/playlists_screen.dart, glej
/// docs/faza2-wrap/intent3.md). Isti [isCountedPlay] filter kot
/// `computeWrapStats`, da obe mesti rangirata isti nabor "resničnih" plays.
Map<String, SongPlayStat> computeSongPlayStats(List<PlayHistoryEntry> entries) {
  final playCounts = <String, int>{};
  final listenedMs = <String, int>{};
  for (final entry in entries) {
    if (!isCountedPlay(entry.msListened, entry.trackDurationMs)) continue;
    playCounts.update(entry.songId, (count) => count + 1, ifAbsent: () => 1);
    listenedMs.update(
      entry.songId,
      (total) => total + entry.msListened,
      ifAbsent: () => entry.msListened,
    );
  }
  return {
    for (final id in playCounts.keys)
      id: SongPlayStat(playCount: playCounts[id]!, listenedMs: listenedMs[id]!),
  };
}

class WrapSongStat {
  const WrapSongStat({
    required this.song,
    required this.playCount,
    required this.listenedMs,
  });

  final Song song;
  final int playCount;

  /// Vsota `msListened` čez šteti plays (glej [isCountedPlay]) te pesmi -
  /// isti filter kot `playCount`, zato oba metrika rangirata isti nabor
  /// "resničnih" predvajanj. Ločeno od `WrapStats.totalListened`, ki je
  /// nefiltriran seštevek čez vse vnose.
  final int listenedMs;
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

  /// Padajoče po `playCount` (ali `listenedMs`, glej `songSortOption`) -
  /// dolžina je odvisna od `maxTopEntries`, ki ga je klicatelj podal
  /// `computeWrapStats`-u (privzeto neomejeno).
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
  WrapSongSortOption songSortOption = WrapSongSortOption.playCount,

  /// Omeji `topSongs`/`topArtists`/`topAlbums` na prvih `maxTopEntries`
  /// (po sortiranju) - `null` (privzeto) pomeni neomejeno, kar potrebuje
  /// npr. `WrapPlaylistGenerator` (Top-100 playlists, glej
  /// wrap_playlist_service.dart), medtem ko wrap_screen.dart za prikaz poda
  /// manjšo vrednost (glej docs/faza2-wrap/intent3.md).
  int? maxTopEntries,
}) {
  final totalListenedMs = entries.fold<int>(
    0,
    (sum, entry) => sum + entry.msListened,
  );

  final songPlayCounts = <String, int>{};
  final songListenedMs = <String, int>{};
  final artistPlayCounts = <String, int>{};
  final albumPlayCounts = <String, int>{};
  final genrePlayCounts = <String, int>{};

  for (final entry in entries) {
    if (!isCountedPlay(entry.msListened, entry.trackDurationMs)) continue;
    final song = libraryById[entry.songId];
    if (song == null) continue;

    songPlayCounts.update(song.id, (count) => count + 1, ifAbsent: () => 1);
    songListenedMs.update(
      song.id,
      (total) => total + entry.msListened,
      ifAbsent: () => entry.msListened,
    );
    artistPlayCounts.update(
      song.artist,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    albumPlayCounts.update(song.album, (count) => count + 1, ifAbsent: () => 1);
    if (genreEnabled && song.genre != null) {
      genrePlayCounts.update(
        song.genre!,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  final topSongs =
      songPlayCounts.entries
          .map(
            (e) => WrapSongStat(
              song: libraryById[e.key]!,
              playCount: e.value,
              listenedMs: songListenedMs[e.key]!,
            ),
          )
          .toList()
        ..sort(
          (a, b) => _compareStats(
            songSortOption == WrapSongSortOption.listeningTime
                ? a.listenedMs
                : a.playCount,
            songSortOption == WrapSongSortOption.listeningTime
                ? b.listenedMs
                : b.playCount,
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
    topSongs: _limited(topSongs, maxTopEntries),
    topArtists: _limited(topArtists, maxTopEntries),
    topAlbums: _limited(topAlbums, maxTopEntries),
    totalListened: Duration(milliseconds: totalListenedMs),
    topGenre: topGenre,
  );
}

List<T> _limited<T>(List<T> list, int? max) =>
    max == null || list.length <= max ? list : list.sublist(0, max);

/// Meje trenutnega (odprtega, "live") in prejšnjega (ravnokar zaprtega,
/// za letno snapshot playlisto) Wrap obdobja glede na
/// `WrapSettings.resetMonth`/`resetDay` (glej docs/intent-wrap.md "Year
/// boundary" - spreminjanje reset datuma vpliva le na prihodnje bucketiranje,
/// zato meje vedno računamo iz trenutnega nastavitve, nikoli shranjeno).
class WrapPeriodBounds {
  const WrapPeriodBounds({
    required this.currentPeriodStart,
    required this.previousPeriodStart,
  });

  /// Začetek odprtega obdobja (vključno) - konec je "zdaj", ni shranjen.
  final DateTime currentPeriodStart;

  /// Začetek prejšnjega, zaprtega obdobja (vključno) - konec je
  /// [currentPeriodStart] (izključno). Uporabljeno za letno snapshot
  /// playlisto; `previousPeriodStart.year` je oznaka leta te playliste.
  final DateTime previousPeriodStart;
}

WrapPeriodBounds computeWrapPeriodBounds({
  required DateTime now,
  required int resetMonth,
  required int resetDay,
}) {
  final currentPeriodStart = mostRecentWrapBoundary(
    now: now,
    resetMonth: resetMonth,
    resetDay: resetDay,
  );
  final previousPeriodStart = DateTime(
    currentPeriodStart.year - 1,
    resetMonth,
    resetDay,
  );
  return WrapPeriodBounds(
    currentPeriodStart: currentPeriodStart,
    previousPeriodStart: previousPeriodStart,
  );
}

/// Najnovejša reset-meja, ki je `<= now` - t.j. začetek trenutnega odprtega
/// obdobja.
DateTime mostRecentWrapBoundary({
  required DateTime now,
  required int resetMonth,
  required int resetDay,
}) {
  final thisYearBoundary = DateTime(now.year, resetMonth, resetDay);
  if (!now.isBefore(thisYearBoundary)) return thisYearBoundary;
  return DateTime(now.year - 1, resetMonth, resetDay);
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
