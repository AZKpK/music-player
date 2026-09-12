import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/audio_player_service.dart';
import '../../shared/widgets/song_artwork.dart';

/// Ločen zaslon za vrsto predvajanja (queue), ločen od `PlayerScreen`
/// ("kaj igra zdaj"). Prikazuje dejanski play order (glej
/// `AudioPlayerHandler`/`buildPlayOrder` - shuffle model v
/// `audio_player_service.dart`), z reorder-om, odstranitvijo posameznega
/// vnosa in tapom za skok na poljuben vnos.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final queue = ref.watch(queueProvider).valueOrNull ?? const [];
    final currentQueueItemId = ref
        .watch(currentMediaItemProvider)
        .valueOrNull
        ?.extras?[queueItemIdExtraKey];

    return Scaffold(
      appBar: AppBar(title: const Text('Vrsta predvajanja')),
      body: queue.isEmpty
          ? const Center(child: Text('Vrsta predvajanja je prazna'))
          : ReorderableListView.builder(
              itemCount: queue.length,
              // Med vlečenjem uporabimo isti Material kot pri navadni vrstici.
              // Privzeti proxy doda ločen, animiran overlay, zaradi katerega so
              // se ob spustu premaknjene vrstice vidno "prižigale".
              proxyDecorator: (child, index, animation) => AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  child: child,
                ),
                child: child,
              ),
              onReorder: (oldIndex, newIndex) {
                // ReorderableListView poda `newIndex` v smislu vstavljanja
                // pred odstranitvijo elementa - pri premiku navzdol ga je
                // zato treba popraviti za 1 (standardna Flutter konvencija).
                if (newIndex > oldIndex) newIndex -= 1;
                handler.moveQueueItem(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final item = queue[index];
                final queueItemId = item.extras?[queueItemIdExtraKey];
                final isCurrent =
                    queueItemId != null && queueItemId == currentQueueItemId;
                return ListTile(
                  // `queueItemId` je unikaten tudi če je ista pesem v
                  // queue-u večkrat (`item.id` v tem primeru ni edinstven).
                  key: ValueKey(queueItemId ?? item.id),
                  selected: isCurrent,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      SongArtwork(song: _songFromQueueItem(item)),
                    ],
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.artist ?? ''),
                  onTap: () => handler.skipToQueueItem(index),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Odstrani iz vrste',
                    onPressed: () => handler.removeQueueItemAt(index),
                  ),
                );
              },
            ),
    );
  }
}

/// [MediaItem] ne vsebuje poti do zvočne datoteke, vendar [SongArtwork] za
/// prikaz naslovnice potrebuje le ID in `artUri`; prazna pot zato tu zadošča.
Song _songFromQueueItem(MediaItem item) => Song(
  id: item.id,
  title: item.title,
  artist: item.artist ?? '',
  album: item.album ?? '',
  filePath: '',
  duration: item.duration,
  artUri: item.artUri,
);
