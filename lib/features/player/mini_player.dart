import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_navigation.dart';
import '../../core/navigation/player_screen_visibility.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/media_library_providers.dart';
import '../../shared/widgets/song_artwork.dart';
import 'player_screen.dart';

/// Kompakten predvajalnik, ki je prikazan na dnu vseh glavnih zaslonov.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: playerScreenDepth,
      builder: (context, depth, _) {
        if (depth > 0) return const SizedBox.shrink();
        return const _MiniPlayerContent();
      },
    );
  }
}

class _MiniPlayerContent extends ConsumerWidget {
  const _MiniPlayerContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final handler = ref.watch(audioHandlerProvider);
    final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
    final queue = ref.watch(queueProvider).valueOrNull ?? const [];
    final duration = mediaItem?.duration ?? song.duration;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 8,
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  // `MiniPlayer` živi globalno nad navigatorjem. Čeprav se
                  // med podrobnim predvajalnikom skrije, s tem varovalom tudi
                  // med prehodom/animacijo nikoli ne odpre druge plasti iste
                  // strani.
                  if (playerScreenDepth.value > 0) return;
                  appNavigatorKey.currentState?.push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    SongArtwork(song: song, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          _MiniPlayerProgress(duration: duration),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    //_MiniPlayerTime(duration: duration),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            _MiniPlayerControls(handler: handler, queue: queue),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerProgress extends ConsumerWidget {
  const _MiniPlayerProgress({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final knownDuration = duration != null && duration! > Duration.zero
        ? duration
        : null;
    return LinearProgressIndicator(
      value: knownDuration != null
          ? (position.inMilliseconds / knownDuration.inMilliseconds).clamp(
              0.0,
              1.0,
            )
          : 0,
    );
  }
}

/*
class _MiniPlayerTime extends ConsumerWidget {
  const _MiniPlayerTime({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final knownDuration = duration != null && duration! > Duration.zero
        ? duration
        : null;
    return Text(
      knownDuration == null
          ? '--:-- / --:--'
          : '${_formatDuration(position)} / ${_formatDuration(knownDuration)}',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
*/

class _MiniPlayerControls extends ConsumerWidget {
  const _MiniPlayerControls({required this.handler, required this.queue});

  final AudioPlayerHandler handler;
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final playing = playbackState?.playing ?? false;
    final queueIndex = playbackState?.queueIndex ?? -1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Prejšnja skladba',
          icon: const Icon(Icons.skip_previous),
          onPressed: queue.length > 1 ? handler.skipToPrevious : null,
        ),
        IconButton(
          tooltip: playing ? 'Premor' : 'Predvajaj',
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: playing ? handler.pause : handler.play,
        ),
        IconButton(
          tooltip: 'Naslednja skladba',
          icon: const Icon(Icons.skip_next),
          onPressed: queue.length > 1 && queueIndex < queue.length - 1
              ? handler.skipToNext
              : null,
        ),
      ],
    );
  }
}

/*
String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
*/
