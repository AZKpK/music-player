import 'dart:io';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// Prefiks ID-jev pesmi, ki prihajajo iz MediaStore-a (glej [_toSong]).
const _mediaStoreIdPrefix = 'media_store:';

/// Bere lokalno glasbeno knjižnico z naprave preko Android MediaStore
/// (`on_audio_query`). Za razliko od [scanFolderForSongs] (ročni folder-scan
/// v `library_scanner.dart`) tu dobimo prave metadata (artist/album/duration),
/// ker jih MediaStore že ekstrahira iz ID3/Vorbis tagov ob indeksiranju.
class MediaLibraryService {
  final OnAudioQuery _query = OnAudioQuery();

  /// Preveri in po potrebi zahteva dovoljenje za branje glasbe
  /// (`READ_MEDIA_AUDIO` na Android 13+, `READ_EXTERNAL_STORAGE` prej).
  Future<bool> requestPermission() => _query.checkAndRequest();

  /// Vse pesmi na napravi, sortirane po naslovu.
  Future<List<Song>> querySongs() async {
    final songs = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return songs.map(_toSong).toList();
  }

  /// Grupira pesmi po izvajalcu (`artist`). Pesmi brez znanega izvajalca
  /// pristanejo pod "Neznan izvajalec".
  Map<String, List<Song>> groupByArtist(List<Song> songs) {
    final grouped = <String, List<Song>>{};
    for (final song in songs) {
      grouped.putIfAbsent(song.artist, () => []).add(song);
    }
    return grouped;
  }

  /// Grupira pesmi po albumu (`album`). Pesmi brez znanega albuma pristanejo
  /// pod "Neznan album".
  Map<String, List<Song>> groupByAlbum(List<Song> songs) {
    final grouped = <String, List<Song>>{};
    for (final song in songs) {
      grouped.putIfAbsent(song.album, () => []).add(song);
    }
    return grouped;
  }

  /// Razreši MediaStore artwork za pesem z ID-jem `media_store:<int>` v
  /// datoteko na disku in vrne `file://` [Uri] primeren za `MediaItem.artUri`
  /// (notifikacija/lock-screen zahtevata dejansko datoteko/Uri, ne Flutter
  /// widget kot `QueryArtworkWidget`). `null` če pesem ni iz MediaStore-a ali
  /// artworka ni (na voljo). Rezultat je cache-iran na disk
  /// (`<temp>/artwork_cache/<id>.jpg`), zato se isti artwork ne bere iz
  /// MediaStore-a ob vsakem `loadQueue`.
  Future<Uri?> resolveArtwork(String songId) async {
    if (!songId.startsWith(_mediaStoreIdPrefix)) return null;
    final mediaStoreId = int.tryParse(
      songId.substring(_mediaStoreIdPrefix.length),
    );
    if (mediaStoreId == null) return null;

    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}/artwork_cache',
    );
    final cacheFile = File('${cacheDir.path}/$mediaStoreId.jpg');
    if (await cacheFile.exists()) return cacheFile.uri;

    final bytes = await _query.queryArtwork(
      mediaStoreId,
      ArtworkType.AUDIO,
      format: ArtworkFormat.JPEG,
    );
    if (bytes == null || bytes.isEmpty) return null;

    await cacheDir.create(recursive: true);
    await cacheFile.writeAsBytes(bytes, flush: true);
    return cacheFile.uri;
  }

  Song _toSong(SongModel song) => Song(
        id: '$_mediaStoreIdPrefix${song.id}',
        title: song.title,
        artist: song.artist ?? 'Neznan izvajalec',
        album: song.album ?? 'Neznan album',
        filePath: song.data,
        duration:
            song.duration != null ? Duration(milliseconds: song.duration!) : null,
        // Artwork se ne razreši tu (dražje, gl. `resolveArtwork` doc) - polni
        // se šele ob predvajanju (`AudioPlayerHandler`, glej Faza 6.1),
        // seznami pa artwork prikažejo preko `QueryArtworkWidget` (`SongArtwork`
        // widget), ki ga bere direktno iz MediaStore-a brez te cache datoteke.
      );
}
