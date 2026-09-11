import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/audio_player_providers.dart';
import '../../core/services/media_library_providers.dart';
import '../../core/services/sleep_timer_provider.dart';
import '../../core/navigation/player_screen_visibility.dart';
import '../../shared/widgets/song_artwork.dart';
import '../library/edit_song_metadata_dialog.dart';
import 'queue_screen.dart';

/// Za koliko preskoči gumb "+5s"/"-5s".
const _seekStep = Duration(seconds: 5);

/// Ponujene dolžine sleep timerja v izbirnem dialogu (glej
/// `_showSleepTimerDialog`).
const _sleepTimerOptions = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
  Duration(minutes: 120),
];

/// Ponujene hitrosti predvajanja v AppBar meniju.
const _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

/// Formatira `mm:ss` (ali `h:mm:ss` za daljše trajanje, npr. sleep timer
/// odštevanje) - skupna implementacija za `_SeekBar` in sleep timer badge.
String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Osnovni "now playing" zaslon: naslov/artist trenutne pesmi (+ priljubljena
/// in uredi-metapodatke gumba), seek slider z ročnim nastavljanjem pozicije
/// in +5s/-5s gumbi, play/pause, next/prev, shuffle in repeat toggle, ter
/// gumb za odprtje ločenega `QueueScreen` (vrsta predvajanja - glej
/// `docs/plan1.1.md` #15).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  // Podrobni zaslon mora ob kliku osvežiti srček tudi, ko je predvajanje na
  // premoru (takrat ni periodičnih posodobitev pozicije, ki bi sprožile build).
  String? _locallyUpdatedLikeSongId;
  bool? _locallyUpdatedLiked;

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
    final currentSong = ref.watch(currentSongProvider);
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final duration = mediaItem?.duration;

    final playing = playbackState?.playing ?? false;
    final shuffleOn = playbackState?.shuffleMode == AudioServiceShuffleMode.all;
    final repeatMode = playbackState?.repeatMode ?? AudioServiceRepeatMode.none;
    final sleepRemaining = ref.watch(sleepTimerProvider);
    final speed = playbackState?.speed ?? 1.0;
    final displayedLiked =
        currentSong != null && _locallyUpdatedLikeSongId == currentSong.id
        ? _locallyUpdatedLiked ?? currentSong.liked
        : currentSong?.liked ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Predvajam'),
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Hitrost predvajanja',
            initialValue: speed,
            onSelected: handler.setSpeed,
            itemBuilder: (context) => [
              for (final option in _speedOptions)
                PopupMenuItem(value: option, child: Text('${option}x')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${speed}x',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              sleepRemaining != null ? Icons.bedtime : Icons.bedtime_outlined,
              color: sleepRemaining != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: sleepRemaining != null
                ? 'Sleep timer: ${_formatDuration(sleepRemaining)}'
                : 'Sleep timer',
            onPressed: () =>
                _showSleepTimerDialog(context, ref, sleepRemaining),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Vrsta predvajanja',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const QueueScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          if (currentSong != null)
            Center(child: SongArtwork(song: currentSong, size: 240)),
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
                    displayedLiked ? Icons.favorite : Icons.favorite_border,
                    color: displayedLiked
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: 'Priljubljena',
                  onPressed: () async {
                    final nextLiked = !displayedLiked;
                    setState(() {
                      _locallyUpdatedLikeSongId = currentSong.id;
                      _locallyUpdatedLiked = nextLiked;
                    });

                    try {
                      await ref
                          .read(songLikesControllerProvider)
                          .setLiked(currentSong.id, nextLiked);
                    } catch (_) {
                      if (!mounted) return;
                      setState(() {
                        _locallyUpdatedLikeSongId = null;
                        _locallyUpdatedLiked = null;
                      });
                    }
                  },
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
              if (shuffleOn)
                IconButton.filled(
                  icon: const Icon(Icons.shuffle),
                  style: _toggleOnButtonStyle(context),
                  onPressed: () =>
                      handler.setShuffleMode(AudioServiceShuffleMode.none),
                )
              else
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  onPressed: () =>
                      handler.setShuffleMode(AudioServiceShuffleMode.all),
                ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: handler.skipToPrevious,
              ),
              IconButton(
                icon: const Icon(Icons.replay_5),
                tooltip: '-5s',
                onPressed: duration == null || duration <= Duration.zero
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
                onPressed: duration == null || duration <= Duration.zero
                    ? null
                    : () => handler.seek(
                        _clampSeek(position + _seekStep, duration),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: handler.skipToNext,
              ),
              if (repeatMode == AudioServiceRepeatMode.none)
                IconButton(
                  icon: Icon(_repeatIcon(repeatMode)),
                  onPressed: () =>
                      handler.setRepeatMode(_nextRepeatMode(repeatMode)),
                )
              else
                IconButton.filled(
                  icon: Icon(_repeatIcon(repeatMode)),
                  style: _toggleOnButtonStyle(context),
                  onPressed: () =>
                      handler.setRepeatMode(_nextRepeatMode(repeatMode)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Duration _clampSeek(Duration target, Duration? duration) {
    if (target < Duration.zero) return Duration.zero;
    if (duration != null && duration > Duration.zero && target > duration) {
      return duration;
    }
    return target;
  }

  /// Skupen "vklopljen" izgled za shuffle/repeat toggle gumbe: sivo
  /// zaokroženo kvadratno ozadje (namesto privzetega vijoličnega kroga pri
  /// `IconButton.filled`), da sta oba gumba vizualno usklajena.
  ButtonStyle _toggleOnButtonStyle(BuildContext context) =>
      IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shape: CircleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      );

  IconData _repeatIcon(AudioServiceRepeatMode mode) => switch (mode) {
    AudioServiceRepeatMode.one => Icons.repeat_one,
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
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    final durationKnown = duration != null && duration > Duration.zero;
    final maxMs = duration?.inMilliseconds.toDouble() ?? 0;
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
            onChanged: !durationKnown
                ? null
                : (value) => setState(() => _dragValue = value),
            onChangeEnd: !durationKnown
                ? null
                : (value) {
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
                  durationKnown
                      ? _formatDuration(
                          Duration(milliseconds: sliderValue.round()),
                        )
                      : '--:--',
                ),
                Text(durationKnown ? _formatDuration(duration) : '--:--'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prikaže dialog za izbiro sleep timerja (15/30/45/60 min); če je timer že
/// aktiven, ponudi namesto tega "Prekliči".
Future<void> _showSleepTimerDialog(
  BuildContext context,
  WidgetRef ref,
  Duration? currentRemaining,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Sleep timer'),
      children: [
        if (currentRemaining != null)
          SimpleDialogOption(
            onPressed: () {
              ref.read(sleepTimerProvider.notifier).cancel();
              Navigator.of(context).pop();
            },
            child: const Text('Prekliči timer'),
          ),
        for (final duration in _sleepTimerOptions)
          SimpleDialogOption(
            onPressed: () {
              ref.read(sleepTimerProvider.notifier).start(duration);
              Navigator.of(context).pop();
            },
            child: Text('${duration.inMinutes} min'),
          ),
      ],
    ),
  );
}
