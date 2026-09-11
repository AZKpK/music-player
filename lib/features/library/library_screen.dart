import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../shared/widgets/song_artwork.dart';
import '../player/player_screen.dart';
import '../playlists/playlists_screen.dart';
import 'library_test_screen.dart';
import 'song_actions.dart';

/// Prava glasbena knjižnica z naprave (MediaStore preko `on_audio_query`),
/// z zavihki za vse pesmi ter grupiranjem po izvajalcu/albumu.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _stopSearching() {
    _searchController.clear();
    ref.read(librarySearchQueryProvider.notifier).state = '';
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(librarySongsProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Išči po naslovu/izvajalcu/albumu...',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) =>
                      ref.read(librarySearchQueryProvider.notifier).state =
                          value,
                )
              : const Text('Knjižnica'),
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              tooltip: _searching ? 'Prekliči iskanje' : 'Išči',
              onPressed: () {
                if (_searching) {
                  _stopSearching();
                } else {
                  setState(() => _searching = true);
                }
              },
            ),
            if (!_searching) ...[
              PopupMenuButton<SongSortOption>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sortiraj "Vse pesmi"',
                initialValue: ref.watch(librarySortProvider),
                onSelected: (option) =>
                    ref.read(librarySortProvider.notifier).state = option,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: SongSortOption.title,
                    child: Text('Naslov (A-Ž)'),
                  ),
                  PopupMenuItem(
                    value: SongSortOption.artist,
                    child: Text('Izvajalec'),
                  ),
                  PopupMenuItem(
                    value: SongSortOption.album,
                    child: Text('Album'),
                  ),
                  PopupMenuItem(
                    value: SongSortOption.dateAddedDesc,
                    child: Text('Nedavno dodano'),
                  ),
                  PopupMenuItem(
                    value: SongSortOption.duration,
                    child: Text('Trajanje'),
                  ),
                ],
              ),
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
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Vse pesmi'),
              Tab(text: 'Izvajalci'),
              Tab(text: 'Albumi'),
              Tab(text: 'Priljubljene'),
            ],
          ),
        ),
        body: songsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(rawLibrarySongsProvider),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return const Center(child: Text('Na napravi ni najdenih pesmi'));
            }
            return TabBarView(
              children: [
                const _AllSongsTab(),
                _GroupedTab(groupsProvider: songsByArtistProvider),
                _GroupedTab(
                  groupsProvider: songsByAlbumProvider,
                  sortByTrack: true,
                ),
                const _LikedSongsTab(),
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
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Poskusi znova'),
          ),
        ],
      ),
    );
  }
}

/// Zavihek "Vse pesmi" - bere [displayedLibrarySongsProvider] (namesto
/// direktno [librarySongsProvider]), da nanj vplivata iskalno polje in sort
/// meni v app baru.
class _AllSongsTab extends ConsumerWidget {
  const _AllSongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs =
        ref.watch(displayedLibrarySongsProvider).valueOrNull ?? const [];
    if (songs.isEmpty) {
      return const Center(child: Text('Ni zadetkov'));
    }
    return _SongListView(songs: songs);
  }
}

/// Zavihek "Priljubljene" - bere [likedSongsProvider].
class _LikedSongsTab extends ConsumerWidget {
  const _LikedSongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(likedSongsProvider).valueOrNull ?? const [];
    if (songs.isEmpty) {
      return const Center(child: Text('Ni priljubljenih pesmi'));
    }
    return _SongListView(songs: songs);
  }
}

/// Seznam pesmi z naslovnico/naslovom/izvajalcem/priljubljena-ikono/akcijami -
/// skupna implementacija za "Vse pesmi", "Priljubljene" in `_GroupSongsScreen`
/// (izvajalec/album podseznam).
class _SongListView extends ConsumerWidget {
  const _SongListView({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          leading: SongArtwork(song: song),
          title: Text(song.title),
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
            ],
          ),
        );
      },
    );
  }
}

/// Zavihek "Izvajalci"/"Albumi" - najprej seznam skupin, tap odpre pesmi
/// znotraj izbrane skupine.
class _GroupedTab extends ConsumerWidget {
  const _GroupedTab({required this.groupsProvider, this.sortByTrack = false});

  final ProviderListenable<AsyncValue<Map<String, List<Song>>>> groupsProvider;

  /// Za "Albumi" razvrsti pesmi znotraj skupine po `trackNumber` (mesto na
  /// albumu) namesto po abecedi - glej `_sortGroupSongs`.
  final bool sortByTrack;

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
                  builder: (_) => _GroupSongsScreen(
                    title: name,
                    songs: sortByTrack
                        ? _sortGroupSongs(groupSongs)
                        : groupSongs,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Sortira pesmi po `trackNumber` naraščajoče (brez trackNumber-ja gredo na
/// konec), nato po naslovu - da album prikaže pesmi v pravem vrstnem redu
/// (1., 2. ...) namesto po abecedi.
List<Song> _sortGroupSongs(List<Song> songs) {
  final sorted = [...songs];
  sorted.sort((a, b) {
    final trackA = a.trackNumber;
    final trackB = b.trackNumber;
    if (trackA == null && trackB == null) return a.title.compareTo(b.title);
    if (trackA == null) return 1;
    if (trackB == null) return -1;
    return trackA.compareTo(trackB);
  });
  return sorted;
}

class _GroupSongsScreen extends ConsumerWidget {
  const _GroupSongsScreen({required this.title, required this.songs});

  final String title;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _SongListView(songs: songs),
    );
  }
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

  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
}
