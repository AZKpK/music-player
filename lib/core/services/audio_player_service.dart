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

/// Zgornja meja števila pesmi, ki jih [buildQueueWindow] doda v dejansko
/// predvajalno vrsto - pri knjižnicah 3000+ pesmi bi dodajanje vseh naenkrat
/// v `ConcatenatingAudioSource` pomenilo nepotrebno delo samo zato, da
/// uporabnik začne predvajati eno pesem (glej `docs/plan1.1.md` #18/#24).
const kMaxQueueLength = 250;

/// Zgradi "okno" pesmi za queue: začne pri `startIndex`, doda naslednje
/// pesmi po vrsti do konca seznama. Ne zavije nazaj na začetek: če uporabnik
/// začne pri peti pesmi, predvajanje po zadnji pesmi ne sme spet doseči pete
/// samo zato, ker je bil queue ustvarjen iz krožnega okna.
///
/// Čista funkcija (brez stanja/platform odvisnosti), da je testabilna v
/// izolaciji - glej `test/audio_player_service_test.dart`.
List<Song> buildQueueWindow(
  List<Song> songs,
  int startIndex, {
  int maxLength = kMaxQueueLength,
}) {
  if (songs.isEmpty) return const [];
  if (startIndex < 0 || startIndex >= songs.length) return const [];
  final windowLength = min(maxLength, songs.length - startIndex);
  return [for (var i = 0; i < windowLength; i++) songs[startIndex + i]];
}

/// Zgradi naključno queue okno: izbrana pesem vedno ostane prva, preostanek
/// pa je naključni vzorec iz celotnega seznama (in ne le iz pesmi za njo).
/// To ohrani omejitev [kMaxQueueLength], ne da bi shuffle pri veliki
/// knjižnici favoriziral naslove blizu izbrane pesmi v trenutnem sortiranju.
List<Song> buildShuffledQueueWindow(
  List<Song> songs,
  int startIndex, {
  int maxLength = kMaxQueueLength,
  Random? random,
}) {
  if (maxLength <= 0 ||
      songs.isEmpty ||
      startIndex < 0 ||
      startIndex >= songs.length) {
    return const [];
  }

  final sampleSize = min(maxLength - 1, songs.length - 1);
  if (sampleSize == 0) return [songs[startIndex]];

  // Reservoir sampling ohrani največ `sampleSize` dodatnih pesmi v pomnilniku.
  // Prej smo kopirali in premešali celotno knjižnico samo zato, da smo od nje
  // obdržali največ 249 pesmi v predvajalnem oknu.
  final rng = random ?? Random();
  final sample = <Song>[];
  var seenCandidates = 0;
  for (var index = 0; index < songs.length; index++) {
    if (index == startIndex) continue;
    final song = songs[index];
    seenCandidates++;
    if (sample.length < sampleSize) {
      sample.add(song);
      continue;
    }
    final replacementIndex = rng.nextInt(seenCandidates);
    if (replacementIndex < sampleSize) sample[replacementIndex] = song;
  }
  sample.shuffle(rng);
  return [songs[startIndex], ...sample];
}

/// Vrne kopijo queue-a, v kateri ima vnos z [queueItemId] znano [duration].
///
/// `Song.id` za to ni primeren ključ, ker se lahko ista pesem v queue-u
/// pojavi večkrat. Pomožna funkcija je ločena, da je posodobitev, ki jo
/// sproži `AudioPlayer.durationStream`, preprosto testabilna.
List<MediaItem> updateQueueItemDuration(
  List<MediaItem> items,
  int queueItemId,
  Duration duration,
) {
  final index = items.indexWhere(
    (item) => item.extras?[queueItemIdExtraKey] == queueItemId,
  );
  if (index == -1) return items;

  final updated = [...items];
  updated[index] = updated[index].copyWith(duration: duration);
  return updated;
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
    _player.durationStream.listen(_handleDurationChanged);
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

  /// Celoten seznam, iz katerega je bil naložen trenutni queue. Dejanska
  /// vrsta ima lahko največ [kMaxQueueLength] vnosov, vendar ga potrebujemo,
  /// če uporabnik shuffle vklopi šele po kliku na pesem.
  List<Song> _loadedQueueSongs = [];

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
  ///
  /// `songs` je najprej omejen na [buildQueueWindow] (glej `docs/plan1.1.md`
  /// #18) - pri knjižnicah 3000+ pesmi bi sicer dodajanje vseh naenkrat v
  /// `_playlist` in razreševanje artworka zanje pomenilo nepotrebno delo
  /// samo zato, da uporabnik začne predvajati eno pesem. Queue se objavi
  /// takoj z osnovnimi `MediaItem`-i (brez artworka), artwork za trenutno in
  /// naslednjo pesem pa se razreši asinhrono v ozadju (glej
  /// [_resolveArtworkAround]).
  Future<void> loadQueue(List<Song> songs, {int initialIndex = 0}) async {
    _loadedQueueSongs = List.of(songs);
    final windowed = shuffleEnabled
        ? buildShuffledQueueWindow(songs, initialIndex)
        : buildQueueWindow(songs, initialIndex);
    final entries = [
      for (final song in windowed) QueueEntry(song, _nextQueueItemId++),
    ];
    _sourceOrder = List.of(entries);
    queue.add(entries.map(_songToMediaItem).toList());
    // `currentIndexStream` ne odda nove vrednosti, kadar nova vrsta tako kot
    // prejšnja začne na indeksu 0. Trenutni MediaItem zato objavimo že tu;
    // sicer lahko PlayerScreen ob kliku na drugo pesem še prikazuje prejšnjo,
    // čeprav just_audio že predvaja prvo pesem nove vrste.
    if (entries.isNotEmpty) {
      mediaItem.add(queue.value.first);
    }
    await _playlist.clear();
    await _playlist.addAll(entries.map(_songToAudioSource).toList());
    await _player.setAudioSource(_playlist, initialIndex: 0);
    if (_shuffleMode != AudioServiceShuffleMode.none && entries.isNotEmpty) {
      await _applyShuffleState(current: entries[0]);
    }
    unawaited(_resolveArtworkAround(0));
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
    final currentQueueItemId = _currentQueueItemId();
    await _playlist.move(oldIndex, newIndex);
    final updatedQueue = [...queue.value];
    updatedQueue.insert(newIndex, updatedQueue.removeAt(oldIndex));
    queue.add(updatedQueue);
    _publishCurrentQueueItem(preferredQueueItemId: currentQueueItemId);
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
    final currentQueueItemId = _currentQueueItemId();
    final removedId = queue.value[index].extras?[queueItemIdExtraKey] as int?;
    await _playlist.removeAt(index);
    final updatedQueue = [...queue.value]..removeAt(index);
    queue.add(updatedQueue);
    _sourceOrder = _sourceOrder
        .where((entry) => entry.queueItemId != removedId)
        .toList();
    _publishCurrentQueueItem(
      // Če smo odstranili trenutno pesem, mora UI uporabiti indeks, ki ga je
      // just_audio izbral za naslednjo pesem, ne že odstranjenega vnosa.
      preferredQueueItemId: currentQueueItemId == removedId
          ? null
          : currentQueueItemId,
    );
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
    final enablingShuffle =
        !shuffleEnabled && shuffleMode != AudioServiceShuffleMode.none;
    _shuffleMode = shuffleMode;
    if (enablingShuffle &&
        _loadedQueueSongs.length > kMaxQueueLength &&
        _sourceOrder.length <= kMaxQueueLength) {
      await _replaceQueueWithShuffledWindow(_currentQueueEntry());
    } else {
      await _applyShuffleState(current: _currentQueueEntry());
    }
    _broadcastState(_player.playbackEvent);
  }

  /// Zamenja omejeno zaporedno okno z naključnim oknom iz celotnega vira.
  /// Trenutni [current] vnos obdrži identiteto, zato ostane predvajan prvi
  /// tudi kadar je v izvoru več enakih skladb.
  Future<void> _replaceQueueWithShuffledWindow(QueueEntry? current) async {
    if (current == null) return;
    final sourceIndex = _loadedQueueSongs.indexWhere(
      (song) => identical(song, current.song),
    );
    if (sourceIndex == -1) return;

    final songs = buildShuffledQueueWindow(_loadedQueueSongs, sourceIndex);
    final entries = [
      current,
      for (final song in songs.skip(1)) QueueEntry(song, _nextQueueItemId++),
    ];
    final wasPlaying = _player.playing;
    final position = _player.position;

    _sourceOrder = List.of(entries);
    queue.add(entries.map(_songToMediaItem).toList());
    mediaItem.add(queue.value.first);
    await _playlist.clear();
    await _playlist.addAll(entries.map(_songToAudioSource).toList());
    await _player.setAudioSource(
      _playlist,
      initialIndex: 0,
      initialPosition: position,
    );
    if (wasPlaying) unawaited(_player.play());
    unawaited(_resolveArtworkAround(0));
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
    final currentQueueItemId = _currentQueueItemId();
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
    _publishCurrentQueueItem(preferredQueueItemId: currentQueueItemId);
  }

  /// Identiteta trenutne skladbe je stabilna tudi, kadar se njen indeks v
  /// `ConcatenatingAudioSource` spremeni zaradi shuffle/reorder/remove.
  /// `currentIndexStream` lahko pri takšni spremembi odda dogodek še preden
  /// je nova `queue` objavljena (ali ga sploh ne odda), zato ga po vsaki
  /// strukturni spremembi uskladimo z že objavljeno vrsto.
  int? _currentQueueItemId() {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= queue.value.length) return null;
    return queue.value[index].extras?[queueItemIdExtraKey] as int?;
  }

  void _publishCurrentQueueItem({int? preferredQueueItemId}) {
    final currentQueue = queue.value;
    if (currentQueue.isEmpty) {
      mediaItem.add(null);
      return;
    }

    var index = preferredQueueItemId == null
        ? -1
        : currentQueue.indexWhere(
            (item) => item.extras?[queueItemIdExtraKey] == preferredQueueItemId,
          );
    if (index == -1) {
      index = _player.currentIndex ?? -1;
    }
    if (index < 0 || index >= currentQueue.length) {
      mediaItem.add(null);
      return;
    }

    mediaItem.add(currentQueue[index]);
    unawaited(_resolveArtworkAround(index));
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
    if (index == null || index < 0 || index >= queue.value.length) return;
    mediaItem.add(queue.value[index]);
    unawaited(_resolveArtworkAround(index));
  }

  /// Folder scan ne prebere trajanja iz datoteke. `just_audio` ga sporoči
  /// šele po odprtju trenutnega vira, zato tedaj uskladimo queue in trenutni
  /// MediaItem (notifikacija, lock-screen ter oba predvajalnika v UI).
  void _handleDurationChanged(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return;

    final queueItemId = _currentQueueItemId();
    if (queueItemId == null) return;
    final updated = updateQueueItemDuration(queue.value, queueItemId, duration);
    if (identical(updated, queue.value)) return;

    queue.add(updated);
    if (mediaItem.valueOrNull?.extras?[queueItemIdExtraKey] == queueItemId) {
      final index = updated.indexWhere(
        (item) => item.extras?[queueItemIdExtraKey] == queueItemId,
      );
      if (index != -1) mediaItem.add(updated[index]);
    }
  }

  /// Razreši artwork za pesem na `index` (trenutna) in `index + 1`
  /// (naslednja) - glej [loadQueue] in `docs/plan1.1.md` #18 (lazy artwork).
  /// Pesmi dlje v queue-u dobijo artwork šele, ko postanejo trenutne/
  /// naslednje (prek [_handleCurrentIndexChanged]).
  Future<void> _resolveArtworkAround(int index) async {
    await _resolveArtworkForIndex(index);
    await _resolveArtworkForIndex(index + 1);
  }

  /// Razreši in objavi artwork za queue vnos na `index`, če ga ta še nima.
  Future<void> _resolveArtworkForIndex(int index) async {
    final currentQueue = queue.value;
    if (index < 0 || index >= currentQueue.length) return;
    final item = currentQueue[index];
    if (item.artUri != null) return;
    final queueItemId = item.extras?[queueItemIdExtraKey] as int?;
    if (queueItemId == null) return;

    QueueEntry? entry;
    for (final candidate in _sourceOrder) {
      if (candidate.queueItemId == queueItemId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) return;

    final artUri = await _libraryService.resolveArtwork(entry.song.id);
    if (artUri == null) return;
    _updateQueueItemArtwork(queueItemId, artUri);
  }

  /// Posodobi `artUri` za queue vnos z `queueItemId` v `queue` in - če gre za
  /// trenutno predvajano pesem - tudi v `mediaItem` (notifikacija/lock-screen).
  void _updateQueueItemArtwork(int queueItemId, Uri artUri) {
    final currentQueue = queue.value;
    final index = currentQueue.indexWhere(
      (item) => item.extras?[queueItemIdExtraKey] == queueItemId,
    );
    if (index == -1) return;
    final updated = [...currentQueue];
    updated[index] = updated[index].copyWith(artUri: artUri);
    queue.add(updated);
    if (mediaItem.valueOrNull?.extras?[queueItemIdExtraKey] == queueItemId) {
      mediaItem.add(updated[index]);
    }
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
