import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../core/services/playlist_providers.dart';
import '../player/player_screen.dart';
import '../playlists/playlists_screen.dart';
import 'library_test_screen.dart';

/// Prava glasbena knjižnica z naprave (MediaStore preko `on_audio_query`),
/// z zavihki za vse pesmi ter grupiranjem po izvajalcu/albumu.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(librarySongsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Knjižnica'),
          actions: [
            IconButton(
              icon: const Icon(Icons.queue_music),
              tooltip: 'Playliste',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
              ),
            ),
            // Folder-scan ostaja kot alternativa: koristen za datoteke, ki jih
            // MediaStore še ni indeksiral (npr. ravnokar prekopirane preko adb).
            IconButton(
              icon: const Icon(Icons.snippet_folder_outlined),
              tooltip: 'Izberi mapo ročno (folder-scan)',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryTestScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Vse pesmi'),
              Tab(text: 'Izvajalci'),
              Tab(text: 'Albumi'),
            ],
          ),
        ),
        body: songsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(librarySongsProvider),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return const Center(child: Text('Na napravi ni najdenih pesmi'));
            }
            return TabBarView(
              children: [
                _AllSongsTab(songs: songs),
                _GroupedTab(groupsProvider: songsByArtistProvider),
                _GroupedTab(groupsProvider: songsByAlbumProvider),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Poskusi znova')),
        ],
      ),
    );
  }
}

class _AllSongsTab extends ConsumerWidget {
  const _AllSongsTab({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(song.title),
          subtitle: Text(song.artist),
          onTap: () => _playFrom(context, ref, songs, index),
          trailing: IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Dodaj v playlisto',
            onPressed: () => _showAddToPlaylistSheet(context, ref, song),
          ),
        );
      },
    );
  }
}

/// Zavihek "Izvajalci"/"Albumi" - najprej seznam skupin, tap odpre pesmi
/// znotraj izbrane skupine.
class _GroupedTab extends ConsumerWidget {
  const _GroupedTab({required this.groupsProvider});

  final ProviderListenable<AsyncValue<Map<String, List<Song>>>> groupsProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (groups) {
        final names = groups.keys.toList()..sort();
        return ListView.builder(
          itemCount: names.length,
          itemBuilder: (context, index) {
            final name = names[index];
            final groupSongs = groups[name]!;
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(name),
              subtitle: Text('${groupSongs.length} pesmi'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _GroupSongsScreen(title: name, songs: groupSongs),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupSongsScreen extends ConsumerWidget {
  const _GroupSongsScreen({required this.title, required this.songs});

  final String title;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(song.title),
            subtitle: Text(song.artist),
            onTap: () => _playFrom(context, ref, songs, index),
            trailing: IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Dodaj v playlisto',
              onPressed: () => _showAddToPlaylistSheet(context, ref, song),
            ),
          );
        },
      ),
    );
  }
}

/// Prikaže bottom sheet z obstoječimi playlistami (+ možnost ustvarjanja
/// nove) in dodane `song` v izbrano.
Future<void> _showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final playlists = await ref.read(playlistsProvider.future);
  if (!context.mounted) return;

  final db = ref.read(appDatabaseProvider);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nova playlista...'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final controller = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Nova playlista'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Ime playliste'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Prekliči'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text.trim()),
                      child: const Text('Ustvari'),
                    ),
                  ],
                ),
              );
              if (name == null || name.isEmpty) return;
              final id = await db.createPlaylist(name);
              await db.addSongToPlaylist(id, song);
            },
          ),
          if (playlists.isNotEmpty) const Divider(height: 1),
          for (final playlist in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(playlist.name),
              onTap: () {
                Navigator.of(sheetContext).pop();
                db.addSongToPlaylist(playlist.id, song);
              },
            ),
        ],
      ),
    ),
  );
}

/// Naloži `songs` v queue in začne predvajati od `startIndex`, nato odpre
/// `PlayerScreen`. Namerno brez `await` na `play()` - glej razlago v
/// `library_test_screen.dart`/README (just_audio `play()` Future se razreši
/// šele ko se predvajanje ustavi, ne ko se začne).
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

  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PlayerScreen()),
  );
}
