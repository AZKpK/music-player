import 'package:flutter/foundation.dart';

/// Število odprtih podrobnih predvajalnikov. Globalni mini player se med
/// prikazom podrobnega predvajalnika skrije, da ne more odpreti nove plasti
/// istega zaslona.
final playerScreenDepth = ValueNotifier<int>(0);

void showPlayerScreen() => playerScreenDepth.value++;

void hidePlayerScreen() {
  if (playerScreenDepth.value > 0) playerScreenDepth.value--;
}
