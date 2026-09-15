import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../shared/widgets/alphabet_scroll_bar.dart';
import '../../shared/widgets/app_select_menu.dart';
import '../../shared/widgets/group_artwork.dart';
import '../../shared/widgets/song_artwork.dart';
import '../player/player_screen.dart';
import '../playlists/playlists_screen.dart';
import '../wrap/wrap_screen.dart';
import 'library_test_screen.dart';
import 'group_artwork_actions.dart';
import 'song_actions.dart';

/// Akcije v knjižnici navigacijskem meniju (glej docs/spec-wrap.md "UI" -
/// nadomesti prejšnji samostojni folder-scan `IconButton`).
enum LibraryMenuAction { settings, playFromFolder, wrap }

/// Prava glasbena knjižnica z naprave (MediaStore preko `on_audio_query`),
/// z zavihki za vse pesmi ter grupiranjem po izvajalcu/albumu.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _searchDebounce = Duration(milliseconds: 250);

  bool _searching = false;
  bool _exitDialogOpen = false;
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _stopSearching() {
    _searchTimer?.cancel();
    _searchController.clear();
    ref.read(librarySearchQueryProvider.notifier).state = '';
    setState(() => _searching = false);
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(librarySearchQueryProvider.notifier).state = value;
    });
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zapusti aplikacijo?'),
        content: const Text(
          'Ali ste prepričani, da želite zapustiti aplikacijo? Predvajanje se bo ustavilo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Zapusti'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _exitDialogOpen = false;
    if (exit != true) return;

    await ref.read(audioHandlerProvider).stop();
    if (mounted) await SystemNavigator.pop();
  }

  void _onMenuAction(BuildContext context, LibraryMenuAction action) {
    switch (action) {
      case LibraryMenuAction.settings:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kmalu na voljo')));
      case LibraryMenuAction.playFromFolder:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LibraryTestScreen()));
      case LibraryMenuAction.wrap:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WrapScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(librarySongsProvider);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: DefaultTabController(
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
                    onChanged: _onSearchChanged,
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
                AppSelectMenu<SongSortOption>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sortiraj "Vse pesmi"',
                  value: ref.watch(librarySortProvider),
                  onSelected: (option) =>
                      ref.read(librarySortProvider.notifier).state = option,
                  options: const [
                    AppSelectOption(
                      value: SongSortOption.title,
                      label: 'Naslov (A-Ž)',
                    ),
                    AppSelectOption(
                      value: SongSortOption.artist,
                      label: 'Izvajalec',
                    ),
                    AppSelectOption(
                      value: SongSortOption.album,
                      label: 'Album',
                    ),
                    AppSelectOption(
                      value: SongSortOption.dateAddedDesc,
                      label: 'Nedavno dodano',
                    ),
                    AppSelectOption(
                      value: SongSortOption.duration,
                      label: 'Trajanje',
                    ),
                  ],
                ),
                const _PlayLibraryButton(),
                AppSelectMenu<LibraryMenuAction>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Več',
                  value: null,
                  onSelected: (action) => _onMenuAction(context, action),
                  options: const [
                    AppSelectOption(
                      value: LibraryMenuAction.settings,
                      label: 'Nastavitve',
                      icon: Icons.settings_outlined,
                    ),
                    AppSelectOption(
                      value: LibraryMenuAction.playFromFolder,
                      label: 'Predvajaj iz mape',
                      icon: Icons.folder_outlined,
                    ),
                    AppSelectOption(
                      value: LibraryMenuAction.wrap,
                      label: 'Wrap',
                      icon: Icons.auto_awesome_outlined,
                    ),
                  ],
                ),
              ],
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Vse pesmi'),
                Tab(text: 'Izvajalci'),
                Tab(text: 'Albumi'),
                Tab(text: 'Playliste'),
              ],
            ),
          ),
          body: songsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorView(
              message: '$error',
              onRetry: () => ref.invalidate(rawLibrarySongsProvider),
            ),
            data: (_) => TabBarView(
              children: [
                const _AllSongsTab(),
                _GroupedTab(groupsProvider: songsByArtistProvider),
                _GroupedTab(
                  groupsProvider: songsByAlbumProvider,
                  sortByTrack: true,
                ),
                const PlaylistsTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Samo gumb za predvajanje opazuje filtriran/sortiran seznam. Tako sprememba
/// iskanja ne prezgradi celotnega `DefaultTabController` in vseh zavihkov.
class _PlayLibraryButton extends ConsumerWidget {
  const _PlayLibraryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs =
        ref.watch(displayedLibrarySongsProvider).valueOrNull ?? const <Song>[];
    return AppSelectMenu<bool>(
      tooltip: 'Predvajaj',
      value: null,
      enabled: songs.isNotEmpty,
      icon: const Icon(Icons.play_arrow),
      options: const [
        AppSelectOption(
          value: false,
          label: 'Po vrstnem redu',
          icon: Icons.play_arrow,
        ),
        AppSelectOption(
          value: true,
          label: 'Naključno predvajaj',
          icon: Icons.shuffle,
        ),
      ],
      onSelected: (shuffle) => _playAll(context, ref, songs, shuffle: shuffle),
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

/// Seznam pesmi z naslovnico/naslovom/izvajalcem/priljubljena-ikono/akcijami -
/// skupna implementacija za "Vse pesmi" in `_GroupSongsScreen`
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
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final alphabetIndex = alphabetKeyOf == null
        ? const <String, int>{}
        : buildAlphabetIndex(songs, alphabetKeyOf);
    final listWithAlphabetBar = alphabetKeyOf == null
        ? list
        : Stack(
            children: [
              list,
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: AlphabetScrollBar(
                  availableLetters: alphabetIndex.keys.toSet(),
                  onLetterSelected: (letter) =>
                      _jumpToLetter(letter, alphabetIndex),
                ),
              ),
            ],
          );

    return listWithAlphabetBar;
  }
}

/// Zavihek "Izvajalci"/"Albumi" - najprej seznam skupin, tap odpre pesmi
/// znotraj izbrane skupine. Iskalno polje filtrira imena skupin, A-Z trak pa
/// skoči do prve skupine z izbrano začetnico.
class _GroupedTab extends ConsumerStatefulWidget {
  const _GroupedTab({required this.groupsProvider, this.sortByTrack = false});

  final ProviderListenable<AsyncValue<Map<String, List<Song>>>> groupsProvider;

  /// Za "Albumi" razvrsti pesmi znotraj skupine po `trackNumber` (mesto na
  /// albumu) namesto po abecedi - glej `_sortGroupSongs`.
  final bool sortByTrack;

  @override
  ConsumerState<_GroupedTab> createState() => _GroupedTabState();
}

class _GroupedTabState extends ConsumerState<_GroupedTab> {
  static const _itemExtent = 72.0;
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
    final groupsAsync = ref.watch(widget.groupsProvider);
    final query = ref.watch(librarySearchQueryProvider);
    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (groups) {
        final filteredGroups = filterLibraryGroups(groups, query);
        final names = filteredGroups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (names.isEmpty) return const Center(child: Text('Ni zadetkov'));

        final groupType = widget.sortByTrack
            ? GroupArtworkType.album
            : GroupArtworkType.artist;
        final alphabetIndex = buildAlphabetIndex(names, (name) => name);
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              itemExtent: _itemExtent,
              itemCount: names.length,
              itemBuilder: (context, index) {
                final name = names[index];
                final groupSongs = filteredGroups[name]!;
                return ListTile(
                  leading: GroupArtwork(
                    groupType: groupType,
                    groupKey: name,
                    songs: groupSongs,
                  ),
                  // Seznam ima fiksno višino; brez omejitve se dolg naslov
                  // prelomi v drugo vrstico in se prekrije z naslednjim.
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                    itemBuilder: (_) => [
                      PopupMenuItem<_GroupArtworkAction>(
                        enabled: false,
                        child: Text(name),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _GroupArtworkAction.change,
                        child: Text('Spremeni sliko'),
                      ),
                      const PopupMenuItem(
                        value: _GroupArtworkAction.remove,
                        child: Text('Odstrani sliko'),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _GroupSongsScreen(
                        title: name,
                        songs: widget.sortByTrack
                            ? _sortGroupSongs(groupSongs)
                            : sortLibrarySongs(
                                groupSongs,
                                SongSortOption.title,
                              ),
                        sortedByTrack: widget.sortByTrack,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: AlphabetScrollBar(
                availableLetters: alphabetIndex.keys.toSet(),
                onLetterSelected: (letter) =>
                    _jumpToLetter(letter, alphabetIndex),
              ),
            ),
          ],
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
      body: Column(
        children: [
          _PlayAllActions(songs: songs),
          Expanded(
            child: _SongListView(
              songs: songs,
              alphabetKeyOf: sortedByTrack ? null : (song) => song.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// Akciji za celoten trenutno prikazan seznam. "Predvajaj vse" vedno
/// ponastavi shuffle, "Naključno predvajaj" pa ga vklopi pred nalaganjem
/// vrste, zato rezultat ni odvisen od prejšnjega stanja predvajalnika.
class _PlayAllActions extends ConsumerWidget {
  const _PlayAllActions({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: AppSelectMenu<bool>(
          key: const Key('play-all-options'),
          value: null,
          tooltip: 'Predvajaj vse',
          onSelected: (shuffle) =>
              _playAll(context, ref, songs, shuffle: shuffle),
          options: const [
            AppSelectOption(
              value: false,
              label: 'Predvajaj vse po vrstnem redu',
              icon: Icons.play_arrow,
            ),
            AppSelectOption(
              value: true,
              label: 'Predvajaj vse naključno',
              icon: Icons.shuffle,
            ),
          ],
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Predvajaj vse',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
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

/// Naloži celoten prikazani seznam in odpre now-playing zaslon. Pri velikih
/// seznamih [AudioPlayerHandler.loadQueue] sam uporabi omejeno queue okno.
Future<void> _playAll(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  required bool shuffle,
}) async {
  final handler = ref.read(audioHandlerProvider);
  await handler.setShuffleMode(
    shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
  );
  // Naključna je tudi začetna pesem; prej je bil začetni indeks vedno 0,
  // premešan pa je bil le preostanek vrste.
  final initialIndex = shuffle ? Random().nextInt(songs.length) : 0;
  await handler.loadQueue(songs, initialIndex: initialIndex);
  if (!context.mounted) return;

  unawaited(handler.play());
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
}
