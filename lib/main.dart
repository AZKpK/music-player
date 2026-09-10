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

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
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
