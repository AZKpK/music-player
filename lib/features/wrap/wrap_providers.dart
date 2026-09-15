// Riverpod wiring za Yearly Wrap (glej docs/spec-wrap.md) - poveže
// AppDatabase (WrapSettings + PlayHistoryEntries), wrap_stats_service.dart in
// wrap_playlist_service.dart za wrap_screen.dart. Vsa dejanska agregacijska/
// datumska logika je čista (glej wrap_stats_service.dart) - ta datoteka je
// samo reaktivno lepilo, brez lastnih pravil.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';
import '../../core/services/media_library_providers.dart';
import '../../core/services/playlist_providers.dart';
import '../../core/services/wrap_stats_service.dart';
import 'wrap_playlist_service.dart';

/// Wrap nastavitve (žanr toggle, reset datum, zadnja generacija) - `null`
/// dokler uporabnik ni še ničesar spremenil; ostali providerji spodaj takrat
/// uporabijo privzete vrednosti iz `WrapSettings` tabele.
final wrapSettingsProvider = StreamProvider<WrapSetting?>((ref) {
  return ref.watch(appDatabaseProvider).watchWrapSettings();
});

/// [WrapSettings.genreEnabled], privzeto `false`.
final wrapGenreEnabledProvider = Provider<bool>((ref) {
  return ref.watch(wrapSettingsProvider).valueOrNull?.genreEnabled ?? false;
});

/// Meje trenutnega (odprtega) in prejšnjega (zaprtega) Wrap obdobja, izpeljane
/// iz reset datuma (glej `computeWrapPeriodBounds`). Odvisen od `DateTime.now()`
/// ob branju - ni namenjen `watch`-anju čez daljši čas brez ponovne evalvacije
/// (wrap_screen.dart ga bere ob odprtju zaslona, kar zadostuje spec-u).
final wrapPeriodBoundsProvider = Provider<WrapPeriodBounds>((ref) {
  final settings = ref.watch(wrapSettingsProvider).valueOrNull;
  return computeWrapPeriodBounds(
    now: DateTime.now(),
    resetMonth: settings?.resetMonth ?? 1,
    resetDay: settings?.resetDay ?? 1,
  );
});

/// Zapisi predvajanja znotraj trenutnega (odprtega) obdobja - za "live"
/// prikaz na wrap_screen.dart (glej spec "Trigger": odpiranje zaslona vedno
/// samo prikaže trenutne statistike, brez pisanja).
final currentPeriodPlayHistoryProvider = StreamProvider<List<PlayHistoryEntry>>(
  (ref) {
    final bounds = ref.watch(wrapPeriodBoundsProvider);
    return ref
        .watch(appDatabaseProvider)
        .watchPlayHistoryEntries(from: bounds.currentPeriodStart);
  },
);

/// `songId -> Song` zemljevid iz trenutne knjižnice, za spajanje s
/// `PlayHistoryEntries` v `computeWrapStats` (glej spec "Aggregation").
final wrapLibraryByIdProvider = Provider<Map<String, Song>>((ref) {
  final songs = ref.watch(librarySongsProvider).valueOrNull ?? const [];
  return {for (final song in songs) song.id: song};
});

/// Izbrani kriterij razvrščanja `topSongs` na wrap_screen.dart (glej
/// `WrapSongSortOption`) - session-only (ne shranjen v `WrapSettings`, glej
/// spec-wrap2.md "Sort-option persistence"), zato se ob vsakem zagonu app-a
/// ponastavi na privzeto `playCount`.
final wrapSongSortOptionProvider = StateProvider<WrapSongSortOption>(
  (ref) => WrapSongSortOption.playCount,
);

/// Največ toliko vnosov prikaže wrap_screen.dart v "Top pesmi"/"Top
/// izvajalci"/"Top albumi" (glej docs/faza2-wrap/intent3.md) - namerno samo
/// v [wrapStatsProvider], ne v `WrapPlaylistGenerator`, ki potrebuje do 100
/// pesmi za Top-100 playliste.
const kWrapTopEntriesDisplayLimit = 10;

/// Trenutne (odprto obdobje) Wrap statistike, prikazane na wrap_screen.dart.
final wrapStatsProvider = Provider<AsyncValue<WrapStats>>((ref) {
  final entriesAsync = ref.watch(currentPeriodPlayHistoryProvider);
  final libraryById = ref.watch(wrapLibraryByIdProvider);
  final genreEnabled = ref.watch(wrapGenreEnabledProvider);
  final songSortOption = ref.watch(wrapSongSortOptionProvider);

  return entriesAsync.whenData(
    (entries) => computeWrapStats(
      entries: entries,
      libraryById: libraryById,
      genreEnabled: genreEnabled,
      songSortOption: songSortOption,
      maxTopEntries: kWrapTopEntriesDisplayLimit,
    ),
  );
});

/// Regenerira obe Wrap playlisti (glej spec "Top-100 playlists" in
/// "Trigger"), a samo če je to dejansko potrebno - klicatelj (wrap_screen.dart,
/// korak 7) to kliče ob odprtju zaslona; sama regeneracija se zgodi kvečjemu
/// enkrat na reset-mejo, ne na vsak obisk.
class WrapPlaylistGenerator {
  WrapPlaylistGenerator(this._ref);

  final Ref _ref;

  /// Če `WrapSettings.lastGeneratedAt` predateira najbolj nedavno reset-mejo
  /// (ali sploh še ne obstaja), (re)generira letno snapshot in All-Time
  /// playlisto ter posodobi `lastGeneratedAt`. Sicer ne naredi ničesar.
  Future<void> regenerateIfDue() async {
    final database = _ref.read(appDatabaseProvider);
    final settings = _ref.read(wrapSettingsProvider).valueOrNull;
    final bounds = _ref.read(wrapPeriodBoundsProvider);
    final lastGeneratedAt = settings?.lastGeneratedAt;

    if (lastGeneratedAt != null &&
        !lastGeneratedAt.isBefore(bounds.currentPeriodStart)) {
      return;
    }

    final libraryById = _ref.read(wrapLibraryByIdProvider);
    final genreEnabled = settings?.genreEnabled ?? false;

    final closedYearEntries = await database
        .watchPlayHistoryEntries(
          from: bounds.previousPeriodStart,
          to: bounds.currentPeriodStart,
        )
        .first;
    final closedYearStats = computeWrapStats(
      entries: closedYearEntries,
      libraryById: libraryById,
      genreEnabled: genreEnabled,
    );
    await generateYearlySnapshotPlaylist(
      database: database,
      year: bounds.previousPeriodStart.year,
      topSongs: closedYearStats.topSongs.map((s) => s.song).toList(),
    );

    final allTimeEntries = await database.watchPlayHistoryEntries().first;
    final allTimeStats = computeWrapStats(
      entries: allTimeEntries,
      libraryById: libraryById,
      genreEnabled: genreEnabled,
    );
    await generateAllTimePlaylist(
      database: database,
      topSongs: allTimeStats.topSongs.map((s) => s.song).toList(),
    );

    await database.markWrapPlaylistsGenerated(DateTime.now());
  }
}

final wrapPlaylistGeneratorProvider = Provider<WrapPlaylistGenerator>((ref) {
  return WrapPlaylistGenerator(ref);
});
