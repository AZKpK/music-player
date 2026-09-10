import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../player/player_screen.dart';

/// Začasen zaslon za fazo 2 (core player MVP): omogoča ročno izbiro
/// lokalnih audio datotek za testiranje predvajalnika, dokler faza 3
/// ne doda pravega library scanning-a preko `on_audio_query`.
class LibraryTestScreen extends ConsumerWidget {
  const LibraryTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Player')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Izberi pesmi za test predvajanja'),
          onPressed: () => _pickAndPlay(context, ref),
        ),
      ),
    );
  }

  Future<void> _pickAndPlay(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final songs = result.files
        .where((f) => f.path != null)
        .map((f) => Song(
              id: f.path!,
              title: p.basenameWithoutExtension(f.path!),
              artist: 'Neznan izvajalec',
              album: 'Neznan album',
              filePath: f.path!,
            ))
        .toList();

    if (songs.isEmpty || !context.mounted) return;

    await ref.read(audioHandlerProvider).loadQueue(songs);
    await ref.read(audioHandlerProvider).play();

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
}
