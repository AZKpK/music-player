import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/services/playlist_providers.dart';
import '../../core/services/artwork_import_service.dart';

/// Izbere in trajno shrani ročno naslovnico skupine.
Future<void> changeGroupArtwork(
  WidgetRef ref, {
  required String groupType,
  required String groupKey,
}) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final pickedPath = result?.files.single.path;
  if (pickedPath == null) return;

  final artworkDir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'group_artwork'),
  );
  final destinationPath = await ArtworkImportService().importArtwork(
    sourcePath: pickedPath,
    destinationDirectory: artworkDir.path,
    fileStem: _safeFileName('$groupType-$groupKey'),
  );

  await ref
      .read(appDatabaseProvider)
      .upsertGroupArtwork(
        groupType: groupType,
        groupKey: groupKey,
        artworkPath: destinationPath,
      );
}

/// Odstrani povezavo in lokalno kopijo ročno izbrane naslovnice skupine.
Future<void> removeGroupArtwork(
  WidgetRef ref, {
  required String groupType,
  required String groupKey,
}) async {
  final db = ref.read(appDatabaseProvider);
  final artwork =
      await (db.select(db.groupArtworks)..where(
            (row) =>
                row.groupType.equals(groupType) & row.groupKey.equals(groupKey),
          ))
          .getSingleOrNull();
  await db.removeGroupArtwork(groupType: groupType, groupKey: groupKey);
  if (artwork == null) return;
  try {
    final file = File(artwork.artworkPath);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Povezava je že odstranjena; stara kopija ne bo več uporabljena.
  }
}

String _safeFileName(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
