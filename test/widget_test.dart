// Osnovni smoke test: preveri, da se app zažene brez izjem.
// Note: v tem testu audioHandlerProvider ni overriden z realnim handlerjem,
// zato ostane na "izberi pesmi" zaslonu (main() to normalno naredi v initAudioService()).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/services/audio_player_providers.dart';
import 'package:music_player/core/services/audio_player_service.dart';
import 'package:music_player/main.dart';

void main() {
  testWidgets('App se zažene in prikaže naslov', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(AudioPlayerHandler()),
        ],
        child: const MusicPlayerApp(),
      ),
    );

    expect(find.text('Music Player'), findsOneWidget);
  });
}
