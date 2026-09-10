import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/song.dart';
import 'audio_player_providers.dart';
import 'media_library_service.dart';
import 'playlist_providers.dart';

final mediaLibraryServiceProvider = Provider<MediaLibraryService>((ref) {
  return MediaLibraryService();
});

/// Zahteva dovoljenje za branje glasbe in nato prebere vse pesmi z naprave
/// preko MediaStore. `false` znotraj [AsyncValue] ni mogoč - zavrnjeno
/// dovoljenje vrže izjemo, ki jo UI ujame preko `.when(error: ...)`.
///
/// Namerno ločeno od [librarySongsProvider]: to je "drag" MediaStore-scan
/// (dovoljenje + native query), ki ga nočemo ponavljati ob vsakem uporabnikovem
/// popravku metapodatkov - popravki se namesto tega reaktivno spojijo v
/// [librarySongsProvider] preko [songOverridesProvider], brez ponovnega scan-a.
final rawLibrarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.watch(mediaLibraryServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) {
    throw Exception('Dovoljenje za dostop do glasbe je zavrnjeno');
  }
  return service.querySongs();
});

/// Ročni popravki metapodatkov (glej `SongOverrides` tabelo), ključani po
/// `songId`. Reaktiven (Stream) - takoj se osveži ob "Uredi metapodatke"/
/// "Priljubljena"/"Izbriši".
final songOverridesProvider = StreamProvider<Map<String, SongOverride>>((ref) {
  return ref.watch(appDatabaseProvider).watchAllOverrides();
});

/// Osnovna MediaStore knjižnica, spojena z ročnimi popravki iz
/// [songOverridesProvider]. Pesmi, izbrisane preko app-a
/// (`SongOverride.hidden`), so izločene.
final librarySongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final rawAsync = ref.watch(rawLibrarySongsProvider);
  final overridesAsync = ref.watch(songOverridesProvider);

  if (rawAsync is AsyncError) {
    return AsyncValue.error(rawAsync.error!, rawAsync.stackTrace!);
  }
  if (rawAsync is! AsyncData<List<Song>>) {
    return const AsyncValue.loading();
  }

  final overrides = overridesAsync.valueOrNull ?? const {};
  final merged = rawAsync.value
      .map((song) => applyOverride(song, overrides[song.id]))
      .where((song) => overrides[song.id]?.hidden != true)
      .toList();
  return AsyncValue.data(merged);
});

/// Spoji `song` z ročnim popravkom (`override`), če obstaja. Javno, da ga
/// lahko uporabi tudi npr. `playlists_screen.dart`, kjer so pesmi shranjene
/// kot lasten snapshot v `PlaylistSongs` (ne prihajajo direktno iz
/// [librarySongsProvider]).
Song applyOverride(Song song, SongOverride? override) {
  if (override == null) return song;
  return song.copyWith(
    title: override.title,
    artist: override.artist,
    album: override.album,
    genre: override.genre,
    year: override.year,
    trackNumber: override.trackNumber,
    liked: override.liked,
    artUri: override.artworkPath != null
        ? Uri.file(override.artworkPath!)
        : null,
  );
}

/// Pesmi grupirane po izvajalcu, izpeljano iz [librarySongsProvider].
final songsByArtistProvider = Provider<AsyncValue<Map<String, List<Song>>>>((
  ref,
) {
  final service = ref.watch(mediaLibraryServiceProvider);
  return ref.watch(librarySongsProvider).whenData(service.groupByArtist);
});

/// Pesmi grupirane po albumu, izpeljano iz [librarySongsProvider].
final songsByAlbumProvider = Provider<AsyncValue<Map<String, List<Song>>>>((
  ref,
) {
  final service = ref.watch(mediaLibraryServiceProvider);
  return ref.watch(librarySongsProvider).whenData(service.groupByAlbum);
});

/// Samo priljubljene pesmi, izpeljano iz [librarySongsProvider].
final likedSongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  return ref
      .watch(librarySongsProvider)
      .whenData((songs) => songs.where((s) => s.liked).toList());
});

/// Trenutno vneseno iskalno besedilo v "Vse pesmi" zavihku (glej
/// `library_screen.dart` search-v-app-baru).
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// [librarySongsProvider], filtriran po [librarySearchQueryProvider]
/// (naslov/izvajalec/album, case-insensitive substring match). Prazen query
/// vrne celotno knjižnico nespremenjeno.
final filteredLibrarySongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final query = ref.watch(librarySearchQueryProvider);
  return ref
      .watch(librarySongsProvider)
      .whenData((songs) => filterLibrarySongs(songs, query));
});

/// Čista filter funkcija za [filteredLibrarySongsProvider] - izločena iz
/// providerja, da je testabilna brez platform-channel/DB odvisnosti (glej
/// `test/media_library_filter_test.dart`). Prazen (ali samo presledki) query
/// vrne `songs` nespremenjen; sicer case-insensitive substring match na
/// naslov/izvajalec/album.
List<Song> filterLibrarySongs(List<Song> songs, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return songs;
  return songs
      .where(
        (song) =>
            song.title.toLowerCase().contains(trimmed) ||
            song.artist.toLowerCase().contains(trimmed) ||
            song.album.toLowerCase().contains(trimmed),
      )
      .toList();
}

/// Trenutno predvajana pesem kot [Song] (za "Priljubljena"/"Uredi
/// metapodatke" gumba na `player_screen.dart`) - zgrajena iz trenutnega
/// `MediaItem`-a (naslov/artist/album/genre/artwork so bili že spojeni s
/// popravki ob nalaganju queue-ja) + `liked`/`year`/`trackNumber` neposredno
/// iz [songOverridesProvider] (`MediaItem` teh polj ne nosi).
///
/// `filePath` je namerno prazen - ti dve akciji ga ne potrebujeta, celoten
/// `Song` iz knjižnice/playliste pa tu ni vedno na voljo (queue lahko pride
/// iz playliste, ki ni nujno v trenutni `librarySongsProvider` listi).
final currentSongProvider = Provider<Song?>((ref) {
  final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
  if (mediaItem == null) return null;

  final override = ref.watch(songOverridesProvider).valueOrNull?[mediaItem.id];
  return Song(
    id: mediaItem.id,
    title: override?.title ?? mediaItem.title,
    artist: override?.artist ?? mediaItem.artist ?? '',
    album: override?.album ?? mediaItem.album ?? '',
    filePath: '',
    duration: mediaItem.duration,
    artUri: override?.artworkPath != null
        ? Uri.file(override!.artworkPath!)
        : mediaItem.artUri,
    genre: override?.genre ?? mediaItem.genre,
    year: override?.year,
    trackNumber: override?.trackNumber,
    liked: override?.liked ?? false,
  );
});
