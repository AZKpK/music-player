import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/audio_player_providers.dart';

/// Osnovni "now playing" zaslon: naslov/artist trenutne pesmi, play/pause,
/// next/prev, shuffle in repeat toggle, ter prikaz queue-a spodaj.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final queue = ref.watch(queueProvider).valueOrNull ?? const [];

    final playing = playbackState?.playing ?? false;
    final shuffleOn =
        playbackState?.shuffleMode == AudioServiceShuffleMode.all;
    final repeatMode =
        playbackState?.repeatMode ?? AudioServiceRepeatMode.none;

    return Scaffold(
      appBar: AppBar(title: const Text('Predvajam')),
      body: Column(
        children: [
          const SizedBox(height: 32),
          Text(
            mediaItem?.title ?? 'Ni izbrane pesmi',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          Text(
            mediaItem?.artist ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
                ),
                onPressed: () => handler.setShuffleMode(
                  shuffleOn
                      ? AudioServiceShuffleMode.none
                      : AudioServiceShuffleMode.all,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: handler.skipToPrevious,
              ),
              IconButton(
                iconSize: 48,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: playing ? handler.pause : handler.play,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: handler.skipToNext,
              ),
              IconButton(
                icon: Icon(_repeatIcon(repeatMode)),
                onPressed: () => handler.setRepeatMode(_nextRepeatMode(repeatMode)),
              ),
            ],
          ),
          const Divider(height: 32),
          Expanded(
            child: ListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final item = queue[index];
                final isCurrent = item.id == mediaItem?.id;
                return ListTile(
                  leading: isCurrent
                      ? const Icon(Icons.volume_up)
                      : Text('${index + 1}'),
                  title: Text(item.title),
                  subtitle: Text(item.artist ?? ''),
                  onTap: () => handler.skipToQueueItem(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _repeatIcon(AudioServiceRepeatMode mode) => switch (mode) {
        AudioServiceRepeatMode.one => Icons.repeat_one,
        AudioServiceRepeatMode.all => Icons.repeat_on,
        _ => Icons.repeat,
      };

  AudioServiceRepeatMode _nextRepeatMode(AudioServiceRepeatMode mode) =>
      switch (mode) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
}
