import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/library_scanner.dart';
import '../player/player_screen.dart';

/// Začasen zaslon za fazo 2/3: omogoča ročno izbiro lokalnih audio datotek
/// (ali celotne mape, rekurzivno) za predvajanje, dokler ne pride pravi
/// library scanning preko `on_audio_query` (glej README - znano odprto
/// vprašanje).
class LibraryTestScreen extends ConsumerWidget {
  const LibraryTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Player')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.snippet_folder),
              label: const Text('Izberi mapo (vse pesmi iz podmap)'),
              onPressed: () => _pickFolderAndPlay(context, ref),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.audio_file),
              label: const Text('Izberi posamezne datoteke'),
              onPressed: () => _pickFilesAndPlay(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Zahteva dovoljenje za branje audio/storage; vrne `true` če je odobreno.
  Future<bool> _ensureStoragePermission() async {
    final audio = await Permission.audio.status;
    if (audio.isGranted) return true;
    final result = await Permission.audio.request();
    if (result.isGranted) return true;
    // Starejši Android (<13) uporablja Permission.storage namesto audio.
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _pickFolderAndPlay(BuildContext context, WidgetRef ref) async {
    if (!await _ensureStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dovoljenje za dostop do glasbe je zavrnjeno'),
          ),
        );
      }
      return;
    }

    final folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath == null) return;

    final songs = await scanFolderForSongs(folderPath);
    if (!context.mounted) return;

    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('V izbrani mapi ni najdenih audio datotek'),
        ),
      );
      return;
    }

    await _loadAndOpenPlayer(context, ref, songs);
  }

  Future<void> _pickFilesAndPlay(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final songs = result.files
        .where((f) => f.path != null)
        .map(
          (f) => Song(
            id: f.path!,
            title: p.basenameWithoutExtension(f.path!),
            artist: 'Neznan izvajalec',
            album: 'Neznan album',
            filePath: f.path!,
          ),
        )
        .toList();

    if (songs.isEmpty || !context.mounted) return;

    await _loadAndOpenPlayer(context, ref, songs);
  }

  Future<void> _loadAndOpenPlayer(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
  ) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.loadQueue(songs);
    if (!context.mounted) return;

    // Namerno brez await: `just_audio`-jev play() Future se razreši šele,
    // ko se predvajanje ustavi/konča (ne ko se začne), zato bi await tu
    // blokiral navigacijo na player zaslon do konca prve pesmi.
    unawaited(handler.play());

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }
}
