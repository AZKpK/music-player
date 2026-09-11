import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../shared/widgets/alphabet_scroll_bar.dart';
import '../../shared/widgets/group_artwork.dart';
import '../../shared/widgets/song_artwork.dart';
import '../player/player_screen.dart';
import '../playlists/playlists_screen.dart';
import 'library_test_screen.dart';
import 'group_artwork_actions.dart';
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
    final sortOption = ref.watch(librarySortProvider);
    return _SongListView(
      songs: songs,
      alphabetKeyOf: _alphabetKeyForSort(sortOption),
    );
  }
}

/// Polje, po katerem naj A-Z trak indeksira seznam za dano sort opcijo - glej
/// `_SongListView.alphabetKeyOf`. `null` skrije trak, ker "nedavno dodano" in
/// "trajanje" nista abecedna vrstna reda (glej Faza 7.5 v `plan1.1.md`).
String Function(Song song)? _alphabetKeyForSort(SongSortOption option) {
  switch (option) {
    case SongSortOption.title:
      return (song) => song.title;
    case SongSortOption.artist:
      return (song) => song.artist;
    case SongSortOption.album:
      return (song) => song.album;
    case SongSortOption.dateAddedDesc:
    case SongSortOption.duration:
      return null;
  }
}

/// Zavihek "Priljubljene" - bere [likedSongsProvider]. Vrstni red je isti kot
/// [librarySongsProvider] (naslov, glej `MediaLibraryService.querySongs`),
/// zato je A-Z trak vedno prikazan in indeksiran po naslovu.
class _LikedSongsTab extends ConsumerWidget {
  const _LikedSongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(likedSongsProvider).valueOrNull ?? const [];
    if (songs.isEmpty) {
      return const Center(child: Text('Ni priljubljenih pesmi'));
    }
    return _SongListView(songs: songs, alphabetKeyOf: (song) => song.title);
  }
}

/// Seznam pesmi z naslovnico/naslovom/izvajalcem/priljubljena-ikono/akcijami -
/// skupna implementacija za "Vse pesmi", "Priljubljene" in `_GroupSongsScreen`
/// (izvajalec/album podseznam).
///
/// Fiksna `itemExtent` (Faza 7.5, P0/N3) omogoča O(1) `jumpTo(index * 64)`
/// za A-Z hitro drsenje pri 3000+ pesmih, brez merjenja dejanskih vrstic.
/// `alphabetKeyOf` (`null` skrije trak) izlušči polje, po katerem je `songs`
/// trenutno sortiran - glej `_alphabetKeyForSort`.
class _SongListView extends ConsumerStatefulWidget {
  const _SongListView({required this.songs, this.alphabetKeyOf});

  final List<Song> songs;
  final String Function(Song song)? alphabetKeyOf;

  @override
  ConsumerState<_SongListView> createState() => _SongListViewState();
}

class _SongListViewState extends ConsumerState<_SongListView> {
  static const _itemExtent = 64.0;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToLetter(String letter, Map<String, int> alphabetIndex) {
    final targetIndex = alphabetIndex[letter];
    if (targetIndex == null || !_scrollController.hasClients) return;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final offset = (targetIndex * _itemExtent).clamp(0.0, maxScrollExtent);
    _scrollController.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    final list = ListView.builder(
      controller: _scrollController,
      itemExtent: _itemExtent,
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

    final alphabetKeyOf = widget.alphabetKeyOf;
    if (alphabetKeyOf == null) return list;

    final alphabetIndex = buildAlphabetIndex(songs, alphabetKeyOf);
    return Stack(
      children: [
        list,
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: AlphabetScrollBar(
            availableLetters: alphabetIndex.keys.toSet(),
            onLetterSelected: (letter) => _jumpToLetter(letter, alphabetIndex),
          ),
        ),
      ],
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
        final names = groups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return ListView.builder(
          itemCount: names.length,
          itemBuilder: (context, index) {
            final name = names[index];
            final groupSongs = groups[name]!;
            final groupType = sortByTrack
                ? GroupArtworkType.album
                : GroupArtworkType.artist;
            return ListTile(
              leading: GroupArtwork(
                groupType: groupType,
                groupKey: name,
                songs: groupSongs,
              ),
              title: Text(name),
              subtitle: Text('${groupSongs.length} pesmi'),
              trailing: PopupMenuButton<_GroupArtworkAction>(
                tooltip: 'Slika skupine',
                onSelected: (action) async {
                  switch (action) {
                    case _GroupArtworkAction.change:
                      await changeGroupArtwork(
                        ref,
                        groupType: groupType,
                        groupKey: name,
                      );
                    case _GroupArtworkAction.remove:
                      await removeGroupArtwork(
                        ref,
                        groupType: groupType,
                        groupKey: name,
                      );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _GroupArtworkAction.change,
                    child: Text('Spremeni sliko'),
                  ),
                  PopupMenuItem(
                    value: _GroupArtworkAction.remove,
                    child: Text('Odstrani sliko'),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _GroupSongsScreen(
                    title: name,
                    songs: sortByTrack
                        ? _sortGroupSongs(groupSongs)
                        : sortLibrarySongs(groupSongs, SongSortOption.title),
                    sortedByTrack: sortByTrack,
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

enum _GroupArtworkAction { change, remove }

/// Sortira pesmi po `trackNumber` naraščajoče (brez trackNumber-ja gredo na
/// konec), nato po naslovu - da album prikaže pesmi v pravem vrstnem redu
/// (1., 2. ...) namesto po abecedi.
List<Song> _sortGroupSongs(List<Song> songs) {
  final sorted = [...songs];
  sorted.sort((a, b) {
    final trackA = a.trackNumber;
    final trackB = b.trackNumber;
    if (trackA == null && trackB == null) {
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
    if (trackA == null) return 1;
    if (trackB == null) return -1;
    return trackA.compareTo(trackB);
  });
  return sorted;
}

class _GroupSongsScreen extends ConsumerWidget {
  const _GroupSongsScreen({
    required this.title,
    required this.songs,
    this.sortedByTrack = false,
  });

  final String title;
  final List<Song> songs;

  /// Ali je `songs` sortiran po `trackNumber` (albumi, glej `_sortGroupSongs`)
  /// namesto po naslovu - v tem primeru vrstni red ni abeceden, zato
  /// `_SongListView` skrije A-Z trak.
  final bool sortedByTrack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _SongListView(
        songs: songs,
        alphabetKeyOf: sortedByTrack ? null : (song) => song.title,
      ),
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
