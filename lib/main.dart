import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_navigation.dart';
import 'core/services/audio_player_providers.dart';
import 'core/services/audio_player_service.dart';
import 'features/library/library_screen.dart';
import 'features/player/mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await initAudioService();

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
      child: const MusicPlayerApp(),
    ),
  );
}

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Napake pri predvajanju (glej `AudioPlayerHandler.playbackErrors`) se
    // prikažejo kot snackbar ne glede na to, kateri zaslon je trenutno
    // odprt - `scaffoldMessengerKey` ni vezan na en določen `Scaffold`.
    ref.listen(playbackErrorProvider, (previous, next) {
      next.whenData((message) {
        scaffoldMessengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
    });

    return MaterialApp(
      title: 'Music Player',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Sledi sistemski nastavitvi (svetlo/temno) - ni ločenega stikala v
      // app-u, ker se noben "pravi" music player v Fazi 6 obsegu ne sprašuje
      // za to ročno.
      themeMode: ThemeMode.system,
      builder: (context, child) => Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                const SafeArea(top: false, child: MiniPlayer()),
              ],
            ),
          ),
        ],
      ),
      home: const LibraryScreen(),
    );
  }
}
