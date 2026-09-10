import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/song.dart';

/// Pripone datotek, ki jih obravnavamo kot glasbo.
const _audioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.wav',
  '.flac',
  '.ogg',
  '.opus',
  '.wma',
};

/// Rekurzivno poišče vse audio datoteke v `rootPath` (vključno z vsemi
/// podmapami) in jih pretvori v [Song]-e. Uporabi to za "izberi mapo, predvajaj
/// vse pesmi znotraj" (npr. celoten album/artist folder, ali kar celoten
/// `Music`/`Internal storage` root za "vso glasbo na napravi").
///
/// Pesmi so sortirane po celotni poti (mapa, nato ime datoteke), da se
/// albumi/mape predvajajo v smiselnem vrstnem redu.
Future<List<Song>> scanFolderForSongs(String rootPath) async {
  final root = Directory(rootPath);
  if (!await root.exists()) return [];

  final files = <File>[];
  try {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          _audioExtensions.contains(p.extension(entity.path).toLowerCase())) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    // Nekatere podmape (npr. .thumbnails, permission-denied sistemske mape)
    // vržejo izjemo pri branju - preskočimo, kar je do zdaj že bilo najdeno.
  }

  files.sort((a, b) => a.path.compareTo(b.path));

  return files
      .map((f) => Song(
            id: f.path,
            title: p.basenameWithoutExtension(f.path),
            artist: p.basename(p.dirname(f.path)),
            album: p.basename(p.dirname(f.path)),
            filePath: f.path,
          ))
      .toList();
}
