import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'media_library_service.dart';

/// Extras ključ, pod katerim je v `MediaItem.extras` shranjen unikaten
/// queue-entry ID (glej [QueueEntry]) - potreben, ker je lahko ista pesem
/// (isti `Song.id`) v queue-u večkrat (npr. "predvajaj naslednje" iste
/// pesmi), zato `MediaItem.id`/`Song.id` sam po sebi ni dovolj unikaten
/// ključ za UI (`ReorderableListView` key, "trenutna pesem" primerjava ipd.).
const queueItemIdExtraKey = 'queueItemId';

/// En vnos v queue-u: pesem + unikaten ID vnosa. Ločeno od `MediaItem`, da
/// je [buildPlayOrder] testabilen brez `just_audio`/platform kanalov.
class QueueEntry {
  const QueueEntry(this.song, this.queueItemId);

  final Song song;
  final int queueItemId;
}

/// Zgradi nov play order, kjer trenutna pesem ostane prva:
///
/// - shuffle vklopljen: trenutna pesem + preostale pesmi iz `sourceOrder`,
///   naključno premešane;
/// - shuffle izklopljen: trenutna pesem + preostale pesmi v `sourceOrder`,
///   začenši takoj za trenutno pesmijo in zavijoč nazaj na začetek.
///
/// Čista funkcija (brez stanja/platform odvisnosti) - namenoma ločena od
/// `AudioPlayerHandler`, da je shuffle model testabilen v izolaciji (glej
/// `test/audio_player_service_test.dart`). Uporablja `sourceOrder`, ne
/// interni shuffle mehanizem `just_audio`, da prikazan queue vedno ustreza
/// dejanskemu vrstnemu redu predvajanja (glej `docs/plan1.1.md` #15).
List<QueueEntry> buildPlayOrder({
  required List<QueueEntry> sourceOrder,
  required QueueEntry current,
  required bool shuffled,
  Random? random,
}) {
  final others = sourceOrder
      .where((entry) => entry.queueItemId != current.queueItemId)
      .toList();
  if (shuffled) {
    others.shuffle(random);
  } else {
    final currentIndex = sourceOrder.indexWhere(
      (entry) => entry.queueItemId == current.queueItemId,
    );
    if (currentIndex != -1) {
      others
        ..clear()
        ..addAll(sourceOrder.skip(currentIndex + 1))
        ..addAll(sourceOrder.take(currentIndex));
    }
  }
  return [current, ...others];
}

/// Inicializira audio_service background handler. Kliči enkrat v main()
/// preden zaženeš runApp().
Future<AudioPlayerHandler> initAudioService() {
  return AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.andraz.music_player.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Glavni audio handler: ovija just_audio player in ga izpostavi
/// preko audio_service (background playback, lock-screen/notification
/// kontrole, media button podpora).
///
/// `QueueHandler` doda queue-management default implementacije,
/// `SeekHandler` pa doda fastForward/rewind na podlagi seek().
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler() {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stackTrace) => _handlePlaybackError(),
    );
    _player.currentIndexStream.listen(_handleCurrentIndexChanged);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleCompleted();
      }
    });
    _configureAudioSession();
  }

  /// Napake pri predvajanju ene pesmi v queue-u (npr. datoteka je bila
  /// medtem izbrisana/premaknjena) - UI (npr. `PlayerScreen`) lahko posluša
  /// in prikaže snackbar, namesto da se player tiho zatakne.
  final playbackErrors = StreamController<String>.broadcast();

  /// Nastavi audio focus (`audio_session`) tako, da se app obnaša kot
  /// "pravi" predvajalnik: pavzira ob dohodnem klicu/drugi audio app-aciji
  /// (interruption) in ob izklopu slušalk/zvočnika (becoming noisy) - brez
  /// tega bi predvajanje neopazno teklo naprej "v nič" ali se prekrivalo z
  /// drugim zvokom.
  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      if (!event.begin) return;
      // Ob koncu prekinitve namerno NE nadaljujemo sami - uporabnik sam
      // pritisne play, enako kot večina music playerjev (izognemo se npr.
      // nenadnemu predvajanju takoj po koncu klica).
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          pause();
      }
    });

    session.becomingNoisyEventStream.listen((_) => pause());
  }

  /// Ko `just_audio` vrže napako (npr. pesem v queue-u je bila izbrisana ali
  /// je datoteka poškodovana), namesto da se predvajanje tiho zatakne,
  /// preskočimo na naslednjo pesem in obvestimo UI.
  void _handlePlaybackError() {
    final failed = mediaItem.valueOrNull?.title;
    playbackErrors.add(
      failed != null
          ? 'Napaka pri predvajanju "$failed" - preskočeno'
          : 'Napaka pri predvajanju - preskočeno',
    );
    skipToNext();
  }

  final AudioPlayer _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final MediaLibraryService _libraryService = MediaLibraryService();

  /// Kanoničen ("un-shuffled") vrstni red queue-a - vedno vsebuje isti nabor
  /// vnosov kot trenutni `queue.value` (posodobljen ob vsakem `loadQueue`/
  /// `addToQueue`/`insertNext`/`removeQueueItemAt`), a ohranja izvirni
  /// vrstni red ne glede na to, kako je bil queue kasneje premešan/reorder-an.
  /// Vir resnice za [buildPlayOrder], ko se shuffle vklopi/izklopi.
  List<QueueEntry> _sourceOrder = [];

  int _nextQueueItemId = 0;

  /// Trenutni repeat mode (none / one / all).
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  /// Trenutni shuffle mode - shranjen ločeno od `_player.shuffleModeEnabled`
  /// (interni shuffle `just_audio` se sploh ne uporablja, glej [buildPlayOrder]),
  /// da ga `_broadcastState` lahko vključi v vsak (tudi samodejni) broadcast
  /// in se izogne ročnemu `playbackState.add(...)`, ki bi zamrznil zastarel
  /// `updatePosition` (glej `_broadcastState`).
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;

  /// Ali je shuffle vklopljen.
  bool get shuffleEnabled => _shuffleMode != AudioServiceShuffleMode.none;

  /// Nastavi novo vrsto predvajanja (queue) in začne predvajati od `initialIndex`.
  Future<void> loadQueue(List<Song> songs, {int initialIndex = 0}) async {
    final entries = [
      for (final song in songs) QueueEntry(song, _nextQueueItemId++),
    ];
    _sourceOrder = List.of(entries);
    queue.add(await Future.wait(entries.map(_resolveMediaItem)));
    await _playlist.clear();
    await _playlist.addAll(entries.map(_songToAudioSource).toList());
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);
    if (_shuffleMode != AudioServiceShuffleMode.none && entries.isNotEmpty) {
      await _applyShuffleState(current: entries[initialIndex]);
    }
  }

  Future<void> addToQueue(Song song) async {
    final entry = QueueEntry(song, _nextQueueItemId++);
    _sourceOrder = [..._sourceOrder, entry];
    queue.add([...queue.value, await _resolveMediaItem(entry)]);
    await _playlist.add(_songToAudioSource(entry));
  }

  /// Vstavi pesem takoj za trenutno predvajano ("predvajaj naslednje"). Če
  /// queue trenutno prazen, se obnaša enako kot [loadQueue] z eno pesmijo.
  Future<void> insertNext(Song song) async {
    if (queue.value.isEmpty) {
      await loadQueue([song]);
      return;
    }
    final entry = QueueEntry(song, _nextQueueItemId++);
    final insertIndex = (_player.currentIndex ?? 0) + 1;
    final updatedQueue = [...queue.value]
      ..insert(insertIndex, await _resolveMediaItem(entry));
    queue.add(updatedQueue);
    await _playlist.insert(insertIndex, _songToAudioSource(entry));

    final currentSourceIndex = _currentSourceIndex();
    final sourceInsertIndex = currentSourceIndex == -1
        ? _sourceOrder.length
        : currentSourceIndex + 1;
    _sourceOrder = [..._sourceOrder]..insert(sourceInsertIndex, entry);
  }

  /// Počisti queue in obdrži samo trenutno predvajano pesem (če obstaja).
  /// Uporabljeno iz "Počisti vrsto" gumba na `QueueScreen`.
  ///
  /// `current` je namerno izpeljan iz `queue.value[currentIndex]` (ne iz
  /// `mediaItem.valueOrNull`) - slednji se posodobi šele asinhrono prek
  /// `currentIndexStream` poslušalca (`_handleCurrentIndexChanged`), zato bi
  /// ob naravnem prehodu na naslednjo pesem (ki se lahko zgodi kadarkoli med
  /// izvajanjem te metode) `_player.currentIndex` in `mediaItem.valueOrNull`
  /// lahko kazala na različni pesmi.
  Future<void> clearQueue() async {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= queue.value.length) {
      await _playlist.clear();
      _sourceOrder = [];
      queue.add([]);
      return;
    }
    final current = queue.value[currentIndex];
    for (var i = _playlist.length - 1; i >= 0; i--) {
      if (i == currentIndex) continue;
      await _playlist.removeAt(i);
    }
    queue.add([current]);
    final currentQueueItemId = current.extras?[queueItemIdExtraKey] as int?;
    _sourceOrder = _sourceOrder
        .where((entry) => entry.queueItemId == currentQueueItemId)
        .toList();
  }

  /// Premakne pesem v queue-u z `oldIndex` na `newIndex` (drag-and-drop
  /// reorder na `player_screen.dart`). Obe pozicionirani sta v smislu
  /// "končnega" stanja seznama (enako kot `List.insert` po `List.removeAt`) -
  /// klicatelj (`ReorderableListView.onReorder`) mora `newIndex` ustrezno
  /// popraviti, če se element premika navzdol (standardna Flutter konvencija).
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    await _playlist.move(oldIndex, newIndex);
    final updatedQueue = [...queue.value];
    updatedQueue.insert(newIndex, updatedQueue.removeAt(oldIndex));
    queue.add(updatedQueue);
  }

  /// Odstrani pesem na `index` iz queue-a. Če je bila trenutno predvajana
  /// pesem odstranjena, just_audio sam premakne predvajanje na naslednjo
  /// (`currentIndexStream`/`_handleCurrentIndexChanged` to samodejno ujameta).
  ///
  /// Poimenovano `removeQueueItemAt` (ne `removeQueueItem`), ker slednje ime
  /// že zaseda `QueueHandler.removeQueueItem(MediaItem)` z drugačnim
  /// argumentom - override bi bil sicer neveljaven.
  @override
  Future<void> removeQueueItemAt(int index) async {
    final removedId = queue.value[index].extras?[queueItemIdExtraKey] as int?;
    await _playlist.removeAt(index);
    final updatedQueue = [...queue.value]..removeAt(index);
    queue.add(updatedQueue);
    _sourceOrder = _sourceOrder
        .where((entry) => entry.queueItemId != removedId)
        .toList();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    await _applyShuffleState(current: _currentQueueEntry());
    _broadcastState(_player.playbackEvent);
  }

  /// Poišče trenutno predvajano [QueueEntry] (prek `_player.currentIndex` +
  /// `queue.value`) - potrebna kot "sidro" za [buildPlayOrder], ki mora ob
  /// shuffle preklopu ostati na prvem mestu.
  QueueEntry? _currentQueueEntry() {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= queue.value.length) {
      return null;
    }
    final queueItemId = queue.value[index].extras?[queueItemIdExtraKey] as int?;
    if (queueItemId == null) return null;
    for (final entry in _sourceOrder) {
      if (entry.queueItemId == queueItemId) return entry;
    }
    return null;
  }

  /// Indeks trenutno predvajanega vnosa znotraj `_sourceOrder` (uporabljeno
  /// pri `insertNext`, da nova pesem konča na smiselnem mestu v kanoničnem
  /// vrstnem redu), ali -1, če ni najden.
  int _currentSourceIndex() {
    final current = _currentQueueEntry();
    if (current == null) return -1;
    return _sourceOrder.indexWhere(
      (entry) => entry.queueItemId == current.queueItemId,
    );
  }

  /// Prezgradi play order glede na trenuten `_shuffleMode` (glej
  /// [buildPlayOrder]) in ga uveljavi v `_playlist`/`queue` prek
  /// [_applyPlayOrder]. Brez učinka, če queue trenutno prazen ali trenutne
  /// pesmi ni mogoče določiti.
  Future<void> _applyShuffleState({required QueueEntry? current}) async {
    if (current == null || _sourceOrder.isEmpty) return;
    final newOrder = buildPlayOrder(
      sourceOrder: _sourceOrder,
      current: current,
      shuffled: _shuffleMode != AudioServiceShuffleMode.none,
    );
    await _applyPlayOrder(newOrder);
  }

  /// Preuredi `_playlist`/`queue` tako, da ustreza `newOrder`, z zaporedjem
  /// `_playlist.move()` klicev (enak mehanizem kot ročni [moveQueueItem]) -
  /// s tem se predvajanje ne prekine/ponovno naloži, ker gre za isto
  /// (samo premaknjeno) `AudioSource` instanco, tudi če se trenutno
  /// predvajana pesem znajde na drugem indeksu.
  Future<void> _applyPlayOrder(List<QueueEntry> newOrder) async {
    final current = [...queue.value];
    for (var i = 0; i < newOrder.length; i++) {
      final fromIndex = current.indexWhere(
        (item) => item.extras?[queueItemIdExtraKey] == newOrder[i].queueItemId,
      );
      if (fromIndex == -1 || fromIndex == i) continue;
      await _playlist.move(fromIndex, i);
      current.insert(i, current.removeAt(fromIndex));
    }
    queue.add(current);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    });
    _broadcastState(_player.playbackEvent);
  }

  /// Nastavi hitrost predvajanja (npr. 1.5x/2.0x) - `speed` v
  /// `_broadcastState` (`_player.speed`) že poroča trenutno vrednost naprej,
  /// zato tu ni potrebno dodatno ročno posodabljanje playback stanja.
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _handleCompleted() {
    // Ko je queue končan (in loop off), pustimo playerja v paused stanju
    // na zadnji poziciji - just_audio + LoopMode.all/one to lovi sam.
  }

  void _handleCurrentIndexChanged(int? index) {
    if (index == null || index >= queue.value.length) return;
    mediaItem.add(queue.value[index]);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        shuffleMode: _shuffleMode,
        repeatMode: _repeatMode,
      ),
    );
  }

  /// `extras[queueItemIdExtraKey]` omogoča UI-ju in [removeQueueItemAt]/
  /// [_applyPlayOrder] ločiti med večimi vnosi iste pesmi v queue-u (glej
  /// razred-level dokumentacijo [QueueEntry]).
  MediaItem _songToMediaItem(QueueEntry entry) => MediaItem(
    id: entry.song.id,
    title: entry.song.title,
    artist: entry.song.artist,
    album: entry.song.album,
    genre: entry.song.genre,
    duration: entry.song.duration,
    artUri: entry.song.artUri,
    extras: {queueItemIdExtraKey: entry.queueItemId},
  );

  /// Kot [_songToMediaItem], a doda `artUri` iz MediaStore artworka, če
  /// `song.artUri` še ni nastavljen (ročna naslovnica iz "Uredi metapodatke"
  /// ima prednost - glej `applyOverride()` v `media_library_providers.dart`).
  /// Uporabljeno pri nalaganju v queue, da notifikacija/lock-screen in
  /// `PlayerScreen` dobita pravo albumsko naslovnico brez ročnega urejanja.
  Future<MediaItem> _resolveMediaItem(QueueEntry entry) async {
    final artUri =
        entry.song.artUri ??
        await _libraryService.resolveArtwork(entry.song.id);
    return _songToMediaItem(entry).copyWith(artUri: artUri);
  }

  AudioSource _songToAudioSource(QueueEntry entry) => AudioSource.uri(
    Uri.file(entry.song.filePath),
    tag: _songToMediaItem(entry),
  );
}
