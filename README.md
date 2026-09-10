# music_player

Osebni music player za Android (Flutter), z osnovnimi predvajalniškimi funkcijami
in kasneje planiranimi naprednimi funkcijami (yearly wrap, auto-download preko
YouTube, bulk tagging po mapah). Celoten plan projekta po fazah je v
`/home/andra/.claude/plans/kako-te-ko-bi-bilo-ethereal-muffin.md`.

## Zagon okolja

Okolje (Faza 0) je že pripravljeno na tem stroju:

- **Flutter SDK** je nameščen v `~/development/flutter` in dodan v PATH preko `~/.bashrc`.
  V novem terminalu je `flutter`/`dart` na voljo takoj; v tej seji je bilo treba PATH nastaviti ročno.
- **Android SDK** je v `~/Android/Sdk` (`cmdline-tools`, `platform-tools`, `ndk;27.0.12077973`), vse licence sprejete.
- **VS Code** razširitvi `Dart-Code.dart-code` in `Dart-Code.flutter` nameščeni.

Preveri stanje okolja:

```bash
flutter doctor -v
```

Pričakovano: `Flutter` in `Android toolchain` ✓. `Chrome` in `Linux desktop toolchain` sta ✗,
kar je v redu — nista potrebna za razvoj Android app-a (samo za web/Linux-desktop target).

## Kako zagnati projekt

```bash
cd ~/vaje/git/music-player
flutter pub get          # namesti/osveži dependency-je
flutter run               # zažene app na priklopljenem device-u/emulatorju
```

Za zagon na fizičnem Android telefonu: omogoči USB debugging (Nastavitve → O telefonu →
tapni 7x na "Številka builda" → Developer options → USB debugging), priklopi preko USB
in potrdi "Allow USB debugging" prompt na telefonu. Preveri, da je naprava vidna:

```bash
adb devices
```

Za zagon na emulatorju (če telefona nimaš pri roki):

```bash
avdmanager create avd -n test -k "system-images;android-35;google_apis;x86_64"  # enkratno
emulator -avd test
```

### Build APK (brez zagona, samo za preverbo da vse kompajlira)

```bash
flutter build apk --debug
# rezultat: build/app/outputs/flutter-apk/app-debug.apk
```

## Kako testirati

```bash
flutter analyze     # statična analiza - mora biti brez napak
flutter test         # unit/widget testi
```

Trenutno app ob zagonu odpre zaslon **"Izberi pesmi za test predvajanja"**
(`lib/features/library/library_test_screen.dart`) — to je začasen file-picker,
ki nadomešča pravi library scan dokler ta ni implementiran (faza 3). Ročni test:

1. `flutter run` na telefonu/emulatorju
2. Klikni gumb, izberi eno ali več lokalnih audio datotek (mp3/m4a/...)
3. App bi moral začeti predvajati in te preusmeriti na now-playing zaslon
   (`lib/features/player/player_screen.dart`), kjer testiraš play/pause, next/prev,
   shuffle, repeat (none → all → one) in tapanje na pesem v queue-u

Za testiranje **background playback**-a (lock-screen kontrole, notifikacija):
zaženi predvajanje, pojdi iz app-a (home button) in preveri, da notifikacija
s kontrolami ostane vidna in da lock-screen kaže media kontrole.

## Kaj je narejeno do sedaj

### Faza 0 — Priprava okolja ✅
Flutter SDK, Android SDK (cmdline-tools, NDK, licence), VS Code razširitvi. Podrobnosti zgoraj.

### Faza 1 — Setup projekta ✅
- `flutter create` osnovni Flutter projekt (Android/iOS/desktop targets)
- `pubspec.yaml` dopolnjen s ključnimi paketi: `just_audio`, `audio_service`,
  `drift` + `sqlite3_flutter_libs`, `permission_handler`, `file_picker`,
  `youtube_explode_dart`, `flutter_riverpod`, `fl_chart`
  (`on_audio_query` je začasno izvzet — glej opozorilo spodaj)
- Mapna struktura:
  ```
  lib/
  ├── main.dart
  ├── core/
  │   ├── db/            # (prazno - drift schema pride v fazi 4/7)
  │   ├── services/       # audio_player_service.dart, audio_player_providers.dart
  │   └── models/         # song.dart
  ├── features/
  │   ├── player/          # player_screen.dart
  │   ├── library/         # library_test_screen.dart (začasen)
  │   ├── playlists/       # (prazno - faza 4)
  │   ├── downloads/        # (prazno - faza 9)
  │   ├── tagging/          # (prazno - faza 5)
  │   └── wrap/             # (prazno - faza 8)
  └── shared/               # (prazno - widgets/theme/utils po potrebi)
  ```
- Git repo inicializiran, branch `main`

### Faza 2 — Core player MVP ✅
- `Song` model (`lib/core/models/song.dart`)
- `AudioPlayerHandler` (`lib/core/services/audio_player_service.dart`) — ovija
  `just_audio` in ga izpostavi preko `audio_service`: background predvajanje,
  lock-screen/notification kontrole, media buttons. Podpira `loadQueue`,
  `addToQueue`, play/pause/seek/skipToNext/skipToPrevious/skipToQueueItem,
  shuffle mode, repeat mode (none/one/all)
- Riverpod providerji (`audio_player_providers.dart`) za dostop do handlerja,
  trenutnega `MediaItem`-a, `PlaybackState`-a in queue-a v UI
- `PlayerScreen` — now-playing UI s queue prikazom
- `LibraryTestScreen` — začasen file-picker zaslon za ročno testiranje
  (glej "Kako testirati" zgoraj)
- Android setup: `MainActivity` deduje od `AudioServiceActivity`, manifest ima
  foreground service + media button receiver + dovoljenja (`WAKE_LOCK`,
  `FOREGROUND_SERVICE*`, `READ_MEDIA_AUDIO`)
- Preverjeno: `flutter analyze`, `flutter test` in `flutter build apk --debug`
  vsi prehajajo (`app-debug.apk`, 147MB)

**Znano odprto vprašanje:** `on_audio_query` (paket za branje glasbene knjižnice
z naprave, potreben za fazo 3) je začasno odstranjen iz `pubspec.yaml`, ker
verzija 2.9.0 ni kompatibilna z novejšim Android Gradle Plugin (manjka
`namespace` v `on_audio_query_android`). Pred fazo 3 je treba preveriti
`3.0.0-beta.0` ali poiskati alternativo.

### Faza 3+ — še ni začeto
Library scanning (auto-sort by artist/album), playlists, play-history tracking,
yearly wrap, bulk tagging, YouTube auto-download. Glej celoten plan v
`/home/andra/.claude/plans/kako-te-ko-bi-bilo-ethereal-muffin.md`.
