import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:music_player/core/services/artwork_import_service.dart';

void main() {
  test('artwork import bounds the longest side and writes JPEG', () {
    final source = image.Image(width: 2400, height: 1200);
    image.fill(source, color: image.ColorRgb8(40, 80, 120));

    final encoded = encodeArtworkBytes(
      Uint8List.fromList(image.encodePng(source)),
    );
    final decoded = image.decodeJpg(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.width, ArtworkImportService.maxDimension);
    expect(decoded.height, 800);
  });

  test(
    'artwork import uses a fresh path instead of overwriting artwork',
    () async {
      final root = await Directory.systemTemp.createTemp('artwork-import-test');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source.png');
      await source.writeAsBytes(
        image.encodePng(image.Image(width: 4, height: 4)),
      );
      final service = ArtworkImportService(
        clock: () => DateTime.fromMicrosecondsSinceEpoch(123),
      );

      final first = await service.importArtwork(
        sourcePath: source.path,
        destinationDirectory: root.path,
        fileStem: 'artist',
      );
      final second = await service.importArtwork(
        sourcePath: source.path,
        destinationDirectory: root.path,
        fileStem: 'artist',
      );

      expect(first, endsWith('artist-123.jpg'));
      expect(second, endsWith('artist-123-1.jpg'));
      expect(await File(first).exists(), isTrue);
      expect(await File(second).exists(), isTrue);
    },
  );
}
