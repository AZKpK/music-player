import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/audio_player_providers.dart';
import '../../core/services/audio_player_service.dart';

/// Ločen zaslon za vrsto predvajanja (queue), ločen od `PlayerScreen`
/// ("kaj igra zdaj"). Prikazuje dejanski play order (glej
/// `AudioPlayerHandler`/`buildPlayOrder` - shuffle model v
/// `audio_player_service.dart`), z reorder-om, odstranitvijo posameznega
/// vnosa, "počisti vrsto" in tapom za skok na poljuben vnos.
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
      appBar: AppBar(
        title: const Text('Vrsta predvajanja'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_remove),
            tooltip: 'Počisti vrsto',
            onPressed: queue.length <= 1 ? null : handler.clearQueue,
          ),
        ],
      ),
      body: queue.isEmpty
          ? const Center(child: Text('Vrsta predvajanja je prazna'))
          : ReorderableListView.builder(
              itemCount: queue.length,
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
                  leading: isCurrent
                      ? const Icon(Icons.volume_up)
                      : Text('${index + 1}'),
                  title: Text(item.title),
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
