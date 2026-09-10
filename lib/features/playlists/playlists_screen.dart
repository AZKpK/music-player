import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/playlist_providers.dart';
import '../player/player_screen.dart';

/// Seznam uporabniških playlist (CRUD: ustvari/preimenuj/izbriši).
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Playliste')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPlaylist(context, ref),
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (playlists) {
          if (playlists.isEmpty) {
            return const Center(
              child: Text('Ni playlist - dodaj eno z gumbom spodaj desno'),
            );
          }
          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
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
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Preimenuj')),
                    PopupMenuItem(value: 'delete', child: Text('Izbriši')),
                  ],
                ),
              );
            },
          );
        },
      ),
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

/// Pesmi znotraj ene playliste: predvajanje in odstranjevanje.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(playlistSongsProvider(playlist.id));

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
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(row.title),
                subtitle: Text(row.artist),
                onTap: () => _playFrom(context, ref, rows, index),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Odstrani iz playliste',
                  onPressed: () => ref
                      .read(appDatabaseProvider)
                      .removeSongFromPlaylist(row.id),
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
    List<PlaylistSong> rows,
    int startIndex,
  ) async {
    final handler = ref.read(audioHandlerProvider);
    final songs = rows.map(playlistSongToSong).toList();
    await handler.loadQueue(songs, initialIndex: startIndex);
    if (!context.mounted) return;

    // Glej razlago v library_screen.dart/README: `play()` se namerno ne
    // await-a, da ne blokira takojšnje navigacije na now-playing zaslon.
    unawaited(handler.play());

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
}
