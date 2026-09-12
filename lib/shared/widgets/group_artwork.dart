import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';
import '../../core/services/media_library_providers.dart';
import 'song_artwork.dart';

abstract final class GroupArtworkType {
  static const artist = 'artist';
  static const album = 'album';
}

/// Ročna slika ima prednost, sicer uporabimo naslovnico prve pesmi skupine.
class GroupArtwork extends ConsumerWidget {
  const GroupArtwork({
    super.key,
    required this.groupType,
    required this.groupKey,
    required this.songs,
    this.size = 48,
  });

  final String groupType;
  final String groupKey;
  final List<Song> songs;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworks = ref.watch(groupArtworksProvider).valueOrNull;
    final artwork = artworks?[GroupArtworkKey(groupType, groupKey)];
    if (artwork != null) {
      final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(artwork.artworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          errorBuilder: (_, __, ___) => _songArtwork(),
        ),
      );
    }
    return _songArtwork();
  }

  Widget _songArtwork() => songs.isNotEmpty
      ? SongArtwork(song: songs.first, size: size)
      : const SizedBox.shrink();
}
