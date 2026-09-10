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

Trenutno app ob zagonu odpre zaslon **"Music Player"**
(`lib/features/library/library_test_screen.dart`) z dvema gumboma — to je
začasen file-picker, ki nadomešča pravi library scan dokler ta ni
implementiran preko `on_audio_query` (glej znano odprto vprašanje spodaj).
Ročni test:

1. `flutter run` na telefonu/emulatorju
2. **"Izberi mapo (vse pesmi iz podmap)"** — izberi mapo (npr. `Music` ali kar
   celoten `Internal storage` root za vso glasbo na napravi); app rekurzivno
   poišče vse audio datoteke v vseh podmapah (`lib/core/services/library_scanner.dart`)
   in jih naloži v queue. Alternativno **"Izberi posamezne datoteke"** za ročno
   (multi-)izbiro posameznih datotek.
3. App začne predvajati in te preusmeri na now-playing zaslon
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
z naprave preko Android MediaStore, s pravim artist/album metadata) je začasno
odstranjen iz `pubspec.yaml`, ker verzija 2.9.0 ni kompatibilna z novejšim
Android Gradle Plugin (manjka `namespace` v `on_audio_query_android`). Do
takrat knjižnico nadomešča ročni folder-scan (glej spodaj) — deluje, a brez
prave metadata (artist/album je samo ime mape).

### Faza 2.5 — Folder-based library scan + bugfix ✅
- `lib/core/services/library_scanner.dart` — `scanFolderForSongs()` rekurzivno
  poišče vse audio datoteke (mp3/m4a/aac/wav/flac/ogg/opus/wma) znotraj izbrane
  mape in vseh podmap, sortirano po poti
- `LibraryTestScreen` dopolnjen: gumb **"Izberi mapo (vse pesmi iz podmap)"**
  (uporabi `FilePicker.getDirectoryPath()` + `permission_handler` za
  `Permission.audio`/`Permission.storage`) poleg obstoječega
  "Izberi posamezne datoteke". Izbira root mape (`Internal storage`) da efektivno
  "vso glasbo na napravi"; izbira podmape (npr. `Music/Album X`) da samo tisto.
- **Bugfix:** `handler.play()` se ni smel `await`-ati pred `Navigator.push` —
  `just_audio`-jev `AudioPlayer.play()` Future se razreši šele ko se
  predvajanje ustavi/konča, ne ko se začne, zato je `await` blokiral
  navigacijo na player zaslon (queue je ostal na eni pesmi, skip/prev sta bila
  brez učinka, ker do `PlayerScreen`-a v praksi ni prišlo dokler se predvajana
  pesem ni iztekla). Popravljeno z `unawaited(handler.play())`.
- Preverjeno ročno na emulatorju: izbira `Music` mape z 5 mp3-ji naloži vseh 5
  v queue, takoj preusmeri na `PlayerScreen`, skip next/previous pravilno
  menjata pesmi v queue-u

### Faza 3+ — še ni začeto
Pravi library scan preko `on_audio_query` (artist/album metadata, cover art),
playlists, play-history tracking, yearly wrap, bulk tagging, YouTube
auto-download. Glej celoten plan v
`/home/andra/.claude/plans/kako-te-ko-bi-bilo-ethereal-muffin.md`.
