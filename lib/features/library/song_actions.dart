import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';
import '../../core/services/audio_player_providers.dart';
import '../../core/services/playlist_providers.dart';
import 'edit_song_metadata_dialog.dart';

/// Prikaže bottom sheet z dejanji za eno pesem: predvajaj naslednje, dodaj v
/// playlisto, priljubljena, spremeni naslovnico, uredi metapodatke, izbriši.
Future<void> showSongActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Predvajaj naslednje'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await ref.read(audioHandlerProvider).insertNext(song);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${song.title}" bo predvajana naslednja'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Dodaj v playlisto'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showAddToPlaylistSheet(context, ref, song);
            },
          ),
          ListTile(
            leading: Icon(song.liked ? Icons.favorite : Icons.favorite_border),
            title: Text(
              song.liked ? 'Odstrani iz priljubljenih' : 'Priljubljena',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              ref.read(appDatabaseProvider).setLiked(song.id, !song.liked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Spremeni naslovnico'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _changeArtwork(context, ref, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Uredi metapodatke'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await showEditSongMetadataDialog(context, ref, song);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Izbriši',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _deleteSong(context, ref, song);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _changeArtwork(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final pickedPath = result?.files.single.path;
  if (pickedPath == null) return;

  final artworkDir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'artwork'),
  );
  await artworkDir.create(recursive: true);

  // Datoteko skopiramo v trajno app-storage lokacijo (ne samo shranimo pot) -
  // izvirna izbrana datoteka je lahko v cache/temp mapi, ki jo OS kadarkoli
  // počisti.
  final destination = File(
    p.join(
      artworkDir.path,
      '${_safeFileName(song.id)}${p.extension(pickedPath)}',
    ),
  );
  await File(pickedPath).copy(destination.path);

  await ref
      .read(appDatabaseProvider)
      .upsertOverride(
        SongOverridesCompanion(
          songId: Value(song.id),
          artworkPath: Value(destination.path),
        ),
      );
}

/// Prikaže bottom sheet z obstoječimi playlistami (+ možnost ustvarjanja
/// nove) in doda `song` v izbrano.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final playlists = await ref.read(playlistsProvider.future);
  if (!context.mounted) return;

  final db = ref.read(appDatabaseProvider);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nova playlista...'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final controller = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Nova playlista'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Ime playliste',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Prekliči'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(controller.text.trim()),
                      child: const Text('Ustvari'),
                    ),
                  ],
                ),
              );
              if (name == null || name.isEmpty) return;
              final id = await db.createPlaylist(name);
              await db.addSongToPlaylist(id, song);
            },
          ),
          if (playlists.isNotEmpty) const Divider(height: 1),
          for (final playlist in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(playlist.name),
              onTap: () {
                Navigator.of(sheetContext).pop();
                db.addSongToPlaylist(playlist.id, song);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _deleteSong(BuildContext context, WidgetRef ref, Song song) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Izbriši pesem?'),
      content: Text(
        '"${song.title}" bo trajno izbrisana z naprave in odstranjena iz vseh playlist.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Prekliči'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Izbriši'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  var fileDeleted = true;
  try {
    final file = File(song.filePath);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Scoped storage lahko zavrne brisanje datotek, ki jih app ni ustvaril
    // (Android 10+). Pesem vseeno skrijemo iz knjižnice spodaj, a
    // uporabnika opozorimo, da je morda ostala na disku.
    fileDeleted = false;
  }

  await ref.read(appDatabaseProvider).hideSongEverywhere(song.id);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        fileDeleted
            ? '"${song.title}" izbrisana'
            : '"${song.title}" odstranjena iz knjižnice, a datoteke ni bilo mogoče izbrisati z diska',
      ),
    ),
  );
}

String _safeFileName(String songId) =>
    songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
