import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../core/services/playlist_providers.dart';
import '../../shared/widgets/song_artwork.dart';
import '../library/song_actions.dart';
import '../player/player_screen.dart';

/// Zavihek s playlistami v knjižnici. "Priljubljene pesmi" je sistemska
/// playlista in je zato vedno prvi element, pred uporabniškimi playlistami.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Stack(
      children: [
        playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (playlists) {
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: playlists.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.favorite),
                    title: const Text('Priljubljene pesmi'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LikedSongsPlaylistScreen(),
                      ),
                    ),
                  );
                }
                final playlist = playlists[index - 1];
                return ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlist: playlist),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'rename') {
                        _renamePlaylist(context, ref, playlist);
                      } else if (action == 'delete') {
                        _deletePlaylist(context, ref, playlist);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(playlist.name),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Preimenuj'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Izbriši'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            tooltip: 'Nova playlista',
            onPressed: () => _createPlaylist(context, ref),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = await _askForName(context, title: 'Nova playlista');
    if (name == null || name.isEmpty) return;
    await ref.read(appDatabaseProvider).createPlaylist(name);
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final name = await _askForName(
      context,
      title: 'Preimenuj playlisto',
      initialValue: playlist.name,
    );
    if (name == null || name.isEmpty) return;
    await ref.read(appDatabaseProvider).renamePlaylist(playlist.id, name);
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši playlisto?'),
        content: Text('"${playlist.name}" bo trajno izbrisana.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Prekliči'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Izbriši'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appDatabaseProvider).deletePlaylist(playlist.id);
    }
  }

  Future<String?> _askForName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ime playliste'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Prekliči'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Shrani'),
          ),
        ],
      ),
    );
  }
}

/// Sistem­ska playlista priljubljenih pesmi. Ni shranjena v tabeli playlist,
/// saj jo določa oznaka `liked` na posamezni pesmi.
class LikedSongsPlaylistScreen extends ConsumerWidget {
  const LikedSongsPlaylistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(likedSongsProvider).valueOrNull ?? const <Song>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Priljubljene pesmi')),
      body: songs.isEmpty
          ? const Center(child: Text('Ni priljubljenih pesmi'))
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  leading: SongArtwork(song: song),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(song.artist),
                  onTap: () => _playFrom(context, ref, songs, index),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Dejanja',
                    onPressed: () => showSongActionsSheet(context, ref, song),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _playFrom(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    int startIndex,
  ) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.loadQueue(songs, initialIndex: startIndex);
    if (!context.mounted) return;
    unawaited(handler.play());
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }
}

/// Pesmi znotraj ene playliste: predvajanje in odstranjevanje.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(playlistSongsProvider(playlist.id));
    final overrides = ref.watch(songOverridesProvider).valueOrNull ?? const {};
    final pendingLikes = ref.watch(pendingSongLikesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Text('Playlista je prazna - dodaj pesmi iz knjižnice'),
            );
          }
          // Popravki (liked/naslovnica/ime...) so shranjeni po `songId`, ne
          // po `PlaylistSong.id`, zato jih tu spojimo enako kot v
          // `librarySongsProvider` - `applyOverride`.
          final songs = rows
              .map(
                (row) => applyOverride(
                  playlistSongToSong(row),
                  overrides[row.songId],
                  optimisticLiked: pendingLikes[row.songId],
                ),
              )
              .toList();
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final song = songs[index];
              return ListTile(
                leading: SongArtwork(song: song),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(song.artist),
                onTap: () => _playFrom(context, ref, songs, index),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (song.liked)
                      Icon(
                        Icons.favorite,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'Dejanja',
                      onPressed: () => showSongActionsSheet(context, ref, song),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Odstrani iz playliste',
                      onPressed: () => ref
                          .read(appDatabaseProvider)
                          .removeSongFromPlaylist(row.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _playFrom(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    int startIndex,
  ) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.loadQueue(songs, initialIndex: startIndex);
    if (!context.mounted) return;

    // Glej razlago v library_screen.dart/README: `play()` se namerno ne
    // await-a, da ne blokira takojšnje navigacije na now-playing zaslon.
    unawaited(handler.play());

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }
}
