import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_player_service.dart';

/// Overriden v main() z dejansko instanco, ustvarjeno preko [initAudioService].
final audioHandlerProvider = Provider<AudioPlayerHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider mora biti overriden v main()');
});

/// Trenutno predvajan MediaItem (naslov, artist, album, art...).
final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

/// Trenutno playback stanje (playing/paused, pozicija, shuffle/repeat...).
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

/// Trenutna queue (vrsta predvajanja).
final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

/// Trenutna pozicija predvajanja, ki redno "tika" med predvajanjem (za
/// animiran seek slider) - `audio_service`-ova vgrajena pomožna implementacija
/// (glej `AudioService.position`), namesto da bi si sami postavljali `Timer`.
final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return AudioService.position;
});
