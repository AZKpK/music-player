import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

/// Pretvori uporabnikovo naslovnico v omejen JPEG v ločenem isolatu. Tako
/// velika fotografija ne zaseda trajnega prostora niti ne blokira UI-ja med
/// izbiro slike.
class ArtworkImportService {
  static const maxDimension = 1600;
  static const jpegQuality = 85;

  Future<String> importArtwork({
    required String sourcePath,
    required String destinationDirectory,
    required String fileStem,
  }) async {
    final source = await File(sourcePath).readAsBytes();
    final encoded = await compute(encodeArtworkBytes, source);
    final directory = Directory(destinationDirectory);
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, '$fileStem.jpg'));
    await destination.writeAsBytes(encoded);
    return destination.path;
  }
}

/// Čista pretvorba, ločena od I/O-ja, da lahko preverimo omejitev dimenzij
/// brez platform-channelov ali izbirnika datotek.
Uint8List encodeArtworkBytes(Uint8List source) {
  final decoded = image.decodeImage(source);
  if (decoded == null) {
    throw const FormatException('Izbrane slike ni mogoče prebrati');
  }
  final oriented = image.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final resized = longestSide <= ArtworkImportService.maxDimension
      ? oriented
      : image.copyResize(
          oriented,
          width: oriented.width >= oriented.height
              ? ArtworkImportService.maxDimension
              : null,
          height: oriented.height > oriented.width
              ? ArtworkImportService.maxDimension
              : null,
          interpolation: image.Interpolation.average,
        );
  return Uint8List.fromList(
    image.encodeJpg(resized, quality: ArtworkImportService.jpegQuality),
  );
}
