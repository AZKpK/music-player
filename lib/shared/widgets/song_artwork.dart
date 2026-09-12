import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/models/song.dart';

/// Album art za eno pesem: uporabniško nastavljena naslovnica
/// (`song.artUri`, glej "Spremeni naslovnico") ima prednost, sicer poskusimo
/// prebrati MediaStore artwork (deluje samo za pesmi, prebrane preko
/// `on_audio_query` - id v obliki `media_store:<int>`), sicer prikažemo
/// privzeto ikono.
class SongArtwork extends StatelessWidget {
  const SongArtwork({super.key, required this.song, this.size = 48});

  final Song song;
  final double size;

  static const _mediaStorePrefix = 'media_store:';

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(6);
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    if (song.artUri != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(song.artUri!.toFilePath()),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          errorBuilder: (_, __, ___) => _fallback(context, borderRadius),
        ),
      );
    }

    final mediaStoreId = _parseMediaStoreId(song.id);
    if (mediaStoreId != null) {
      return QueryArtworkWidget(
        id: mediaStoreId,
        type: ArtworkType.AUDIO,
        artworkWidth: size,
        artworkHeight: size,
        artworkBorder: borderRadius,
        nullArtworkWidget: _fallback(context, borderRadius),
      );
    }

    return _fallback(context, borderRadius);
  }

  Widget _fallback(BuildContext context, BorderRadius borderRadius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
      child: const Icon(Icons.music_note),
    );
  }

  int? _parseMediaStoreId(String songId) {
    if (!songId.startsWith(_mediaStorePrefix)) return null;
    return int.tryParse(songId.substring(_mediaStorePrefix.length));
  }
}
