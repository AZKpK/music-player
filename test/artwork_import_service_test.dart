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
}
