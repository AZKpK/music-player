// Osnovni smoke test: preveri, da se app zažene brez izjem.
// Note: `librarySongsProvider` v testnem okolju nima platform-channel
// implementacije za `on_audio_query`, zato ostane v error/loading stanju -
// tu preverjamo le, da se app zažene in prikaže osnovni "Knjižnica" zaslon.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_player/core/db/app_database.dart';
import 'package:music_player/core/services/audio_player_providers.dart';
import 'package:music_player/core/services/audio_player_service.dart';
import 'package:music_player/main.dart';

void main() {
  testWidgets('App se zažene in prikaže naslov', (WidgetTester tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(
            AudioPlayerHandler(database: database),
          ),
        ],
        child: const MusicPlayerApp(),
      ),
    );

    expect(find.text('Knjižnica'), findsOneWidget);
  });
}
