import 'package:on_audio_query/on_audio_query.dart';

import '../models/song.dart';

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

  Song _toSong(SongModel song) => Song(
        id: 'media_store:${song.id}',
        title: song.title,
        artist: song.artist ?? 'Neznan izvajalec',
        album: song.album ?? 'Neznan album',
        filePath: song.data,
        duration:
            song.duration != null ? Duration(milliseconds: song.duration!) : null,
        // TODO: album art preko `content://media/external/audio/albumart/<id>`
        // ni zanesljivo od Android 10 naprej (potrebuje ContentResolver.loadThumbnail
        // preko native kode). `on_audio_query` za to ponuja `QueryArtworkWidget`,
        // ki pa vrača Flutter Widget, ne Uri primeren za MediaItem.artUri/
        // notification art - za zdaj brez artwork-a, glej README.
      );
}
