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

Trenutno app ob zagonu odpre zaslon **"Knjižnica"**
(`lib/features/library/library_screen.dart`) s tremi zavihki (Vse pesmi /
Izvajalci / Albumi), ki bere pravo glasbeno knjižnico z naprave preko
`on_audio_query` (Android MediaStore). Ročni test:

1. `flutter run` na telefonu/emulatorju
2. Ob prvem zagonu app zahteva dovoljenje za dostop do glasbe (`READ_MEDIA_AUDIO`
   na Android 13+) — potrdi
3. **"Vse pesmi"** prikaže ploski seznam vseh pesmi na napravi; **"Izvajalci"**/
   **"Albumi"** prikažeta grupirane sezname (tap odpre pesmi znotraj skupine)
4. Tap na pesem naloži *celoten trenutno prikazan seznam* (vse pesmi / pesmi
   izbranega izvajalca ali albuma) v queue, začne predvajati od tapnjene pesmi
   naprej in preusmeri na now-playing zaslon (`lib/features/player/player_screen.dart`),
   kjer testiraš play/pause, next/prev, shuffle, repeat (none → all → one) in
   tapanje na pesem v queue-u
5. Ikona z notami (queue_music) v app baru odpre **"Playliste"**
   (`lib/features/playlists/playlists_screen.dart`, glej Faza 4) — CRUD nad
   lokalno shranjenimi playlistami (drift/SQLite)
6. Ikona mape v zgornjem desnem kotu (`Knjižnica` app bar) odpre alternativni
   ročni **folder-scan** zaslon (`lib/features/library/library_test_screen.dart`,
   glej Faza 2.5) — uporabno za datoteke, ki jih MediaStore še ni indeksiral
   (npr. ravnokar prekopirane preko `adb push`, dokler ne sproži-š
   `MEDIA_SCANNER_SCAN_FILE` broadcasta ali se naprava ne ponovno zažene)

Za playliste: v katerikoli pesmi v knjižnici tapni ikono **"Dodaj v playlisto"**
(desno od pesmi) — odpre bottom sheet z obstoječimi playlistami + možnostjo
"Nova playlista...". V zaslonu "Playliste" lahko playlisto preimenuješ/izbrišeš
(tri pikice), znotraj playliste pa pesem odstraniš (ikona minus) ali tapneš
pesem za predvajanje cele playliste od tiste pesmi naprej.

Za testiranje **background playback**-a (lock-screen kontrole, notifikacija):
zaženi predvajanje, pojdi iz app-a (home button) in preveri, da notifikacija
s kontrolami ostane vidna in da lock-screen kaže media kontrole.