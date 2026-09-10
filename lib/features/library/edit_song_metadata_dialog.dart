import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/song.dart';
import '../../core/services/playlist_providers.dart';

/// Dialog za ročno urejanje metapodatkov ene pesmi (naslov, album, izvajalec,
/// žanr, leto, mesto na albumu). Shrani se lokalno preko `SongOverrides`
/// tabele - ne piše nazaj v ID3 tag datoteke.
Future<void> showEditSongMetadataDialog(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final titleController = TextEditingController(text: song.title);
  final artistController = TextEditingController(text: song.artist);
  final albumController = TextEditingController(text: song.album);
  final genreController = TextEditingController(text: song.genre ?? '');
  final yearController = TextEditingController(text: song.year?.toString() ?? '');
  final trackController =
      TextEditingController(text: song.trackNumber?.toString() ?? '');
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Uredi metapodatke'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Naslov'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obvezno' : null,
              ),
              TextFormField(
                controller: artistController,
                decoration: const InputDecoration(labelText: 'Izvajalec'),
              ),
              TextFormField(
                controller: albumController,
                decoration: const InputDecoration(labelText: 'Album'),
              ),
              TextFormField(
                controller: genreController,
                decoration: const InputDecoration(labelText: 'Žanr'),
              ),
              TextFormField(
                controller: yearController,
                decoration: const InputDecoration(labelText: 'Leto'),
                keyboardType: TextInputType.number,
                validator: (v) => _validateOptionalInt(v, 'Leto'),
              ),
              TextFormField(
                controller: trackController,
                decoration:
                    const InputDecoration(labelText: 'Mesto na albumu (1., 2. ...)'),
                keyboardType: TextInputType.number,
                validator: (v) => _validateOptionalInt(v, 'Mesto na albumu'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Prekliči'),
        ),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(dialogContext).pop(true);
            }
          },
          child: const Text('Shrani'),
        ),
      ],
    ),
  );

  if (saved != true) return;

  await ref.read(appDatabaseProvider).upsertOverride(
        SongOverridesCompanion(
          songId: Value(song.id),
          title: Value(titleController.text.trim()),
          artist: Value(artistController.text.trim()),
          album: Value(albumController.text.trim()),
          genre: Value(
            genreController.text.trim().isEmpty ? null : genreController.text.trim(),
          ),
          year: Value(int.tryParse(yearController.text.trim())),
          trackNumber: Value(int.tryParse(trackController.text.trim())),
        ),
      );
}

String? _validateOptionalInt(String? value, String fieldLabel) {
  if (value == null || value.trim().isEmpty) return null;
  return int.tryParse(value.trim()) == null ? '$fieldLabel mora biti število' : null;
}
