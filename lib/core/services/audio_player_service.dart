import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'media_library_service.dart';

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
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen(_handleCurrentIndexChanged);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleCompleted();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final MediaLibraryService _libraryService = MediaLibraryService();

  /// Trenutni repeat mode (none / one / all).
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  /// Ali je shuffle vklopljen.
  bool get shuffleEnabled => _player.shuffleModeEnabled;

  /// Nastavi novo vrsto predvajanja (queue) in začne predvajati od `initialIndex`.
  Future<void> loadQueue(List<Song> songs, {int initialIndex = 0}) async {
    queue.add(await Future.wait(songs.map(_resolveMediaItem)));
    await _playlist.clear();
    await _playlist.addAll(songs.map(_songToAudioSource).toList());
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);
  }

  Future<void> addToQueue(Song song) async {
    queue.add([...queue.value, await _resolveMediaItem(song)]);
    await _playlist.add(_songToAudioSource(song));
  }

  /// Vstavi pesem takoj za trenutno predvajano ("predvajaj naslednje"). Če
  /// queue trenutno prazen, se obnaša enako kot [loadQueue] z eno pesmijo.
  Future<void> insertNext(Song song) async {
    if (queue.value.isEmpty) {
      await loadQueue([song]);
      return;
    }
    final insertIndex = (_player.currentIndex ?? 0) + 1;
    final updatedQueue = [...queue.value]
      ..insert(insertIndex, await _resolveMediaItem(song));
    queue.add(updatedQueue);
    await _playlist.insert(insertIndex, _songToAudioSource(song));
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
  Future<void> skipToQueueItem(int index) => _player.seek(Duration.zero, index: index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    if (enabled) await _player.shuffle();
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    });
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

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
      ),
    );
  }

  MediaItem _songToMediaItem(Song song) => MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        duration: song.duration,
        artUri: song.artUri,
      );

  /// Kot [_songToMediaItem], a doda `artUri` iz MediaStore artworka, če
  /// `song.artUri` še ni nastavljen (ročna naslovnica iz "Uredi metapodatke"
  /// ima prednost - glej `applyOverride()` v `media_library_providers.dart`).
  /// Uporabljeno pri nalaganju v queue, da notifikacija/lock-screen in
  /// `PlayerScreen` dobita pravo albumsko naslovnico brez ročnega urejanja.
  Future<MediaItem> _resolveMediaItem(Song song) async {
    final artUri = song.artUri ?? await _libraryService.resolveArtwork(song.id);
    return _songToMediaItem(song).copyWith(artUri: artUri);
  }

  AudioSource _songToAudioSource(Song song) =>
      AudioSource.uri(Uri.file(song.filePath), tag: _songToMediaItem(song));
}
