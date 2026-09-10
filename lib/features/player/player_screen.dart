import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../core/services/playlist_providers.dart';
import '../../core/navigation/player_screen_visibility.dart';
import '../../shared/widgets/song_artwork.dart';
import '../library/edit_song_metadata_dialog.dart';

/// Za koliko preskoči gumb "+5s"/"-5s".
const _seekStep = Duration(seconds: 5);

/// Osnovni "now playing" zaslon: naslov/artist trenutne pesmi (+ priljubljena
/// in uredi-metapodatke gumba), seek slider z ročnim nastavljanjem pozicije
/// in +5s/-5s gumbi, play/pause, next/prev, shuffle in repeat toggle, ter
/// prikaz queue-a spodaj.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    showPlayerScreen();
  }

  @override
  void dispose() {
    hidePlayerScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final queue = ref.watch(queueProvider).valueOrNull ?? const [];
    final currentSong = ref.watch(currentSongProvider);
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final duration = mediaItem?.duration ?? Duration.zero;

    final playing = playbackState?.playing ?? false;
    final shuffleOn = playbackState?.shuffleMode == AudioServiceShuffleMode.all;
    final repeatMode = playbackState?.repeatMode ?? AudioServiceRepeatMode.none;

    return Scaffold(
      appBar: AppBar(title: const Text('Predvajam')),
      body: Column(
        children: [
          const SizedBox(height: 24),
          if (currentSong != null)
            Center(
              child: SongArtwork(song: currentSong, size: 240),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      currentSong?.title ?? 'Ni izbrane pesmi',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      currentSong?.artist ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (currentSong != null) ...[
                IconButton(
                  icon: Icon(
                    currentSong.liked ? Icons.favorite : Icons.favorite_border,
                    color: currentSong.liked
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: 'Priljubljena',
                  onPressed: () => ref
                      .read(appDatabaseProvider)
                      .setLiked(currentSong.id, !currentSong.liked),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Uredi metapodatke',
                  onPressed: () =>
                      showEditSongMetadataDialog(context, ref, currentSong),
                ),
              ] else
                const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 16),
          _SeekBar(
            position: position,
            duration: duration,
            onSeek: handler.seek,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle),
                color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
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
                icon: const Icon(Icons.replay_5),
                tooltip: '-5s',
                onPressed: mediaItem == null
                    ? null
                    : () => handler.seek(
                        _clampSeek(position - _seekStep, duration),
                      ),
              ),
              IconButton(
                iconSize: 48,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: playing ? handler.pause : handler.play,
              ),
              IconButton(
                icon: const Icon(Icons.forward_5),
                tooltip: '+5s',
                onPressed: mediaItem == null
                    ? null
                    : () => handler.seek(
                        _clampSeek(position + _seekStep, duration),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: handler.skipToNext,
              ),
              IconButton(
                icon: Icon(_repeatIcon(repeatMode)),
                onPressed: () =>
                    handler.setRepeatMode(_nextRepeatMode(repeatMode)),
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

  Duration _clampSeek(Duration target, Duration duration) {
    if (target < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && target > duration) return duration;
    return target;
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

/// Slider z oznakama trenutne pozicije/trajanja. Med vlečenjem prikazuje
/// lokalno "draft" vrednost (da se slider ne trza nazaj zaradi tikajočega
/// `position` stream-a), `onSeek` pa pokliče šele ob spustu.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final currentMs = widget.position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs <= 0 ? 0.0 : maxMs,
    );
    final sliderValue = _dragValue ?? currentMs;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Slider(
            value: maxMs <= 0 ? 0 : sliderValue.clamp(0.0, maxMs),
            max: maxMs <= 0 ? 1 : maxMs,
            onChanged: maxMs <= 0
                ? null
                : (value) => setState(() => _dragValue = value),
            onChangeEnd: (value) {
              widget.onSeek(Duration(milliseconds: value.round()));
              setState(() => _dragValue = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: sliderValue.round())),
                ),
                Text(_formatDuration(widget.duration)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
