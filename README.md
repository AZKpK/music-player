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
  │   ├── db/            # app_database.dart (drift schema, Faza 4)
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

**Znano odprto vprašanje (rešeno v Fazi 3):** `on_audio_query` 2.9.0 sprva ni
šel zgraditi z novejšim Android Gradle Plugin (manjka `namespace` v
`on_audio_query_android`) — glej Faza 3 spodaj za rešitev. Do takrat je
knjižnico nadomeščal ročni folder-scan (glej Faza 2.5 spodaj).

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

### Faza 3 — Pravi library scan preko on_audio_query ✅
- **Gradle fix za `on_audio_query_android` 1.1.0** (`android/build.gradle.kts`):
  starejši plugin ne nastavi `namespace` (novejši AGP to zahteva) niti
  usklajen Java/Kotlin compile target (javac privzeto 1.8, Kotlin novejši JDK
  → "Inconsistent JVM-target compatibility"). Namesto čakanja na upstream
  popravek, `subprojects { plugins.withId("com.android.library") { ... } }`
  blok ob apply-ju plugina: namespace naknadno prebere iz
  `AndroidManifest.xml` `package` atributa (`groovy.xml.XmlParser()`), in
  nastavi `compileOptions.sourceCompatibility/targetCompatibility` ter
  Kotlin `jvmTarget` na 11 (enako kot `app/build.gradle.kts`). Nastavljeno
  direktno na `LibraryExtension` (ne na `JavaCompile` task), ker AGP kasneje
  prepiše task-level nastavitve iz `android.compileOptions`.
  `plugins.withId` (namesto `afterEvaluate`) se izognemo napaki
  "already evaluated", ki bi nastala zaradi obstoječega
  `subprojects { evaluationDependsOn(":app") }` bloka.
- `lib/core/services/media_library_service.dart` — `MediaLibraryService`
  ovija `OnAudioQuery`: `requestPermission()` (`checkAndRequest()`),
  `querySongs()` (MediaStore → `List<Song>` s pravim artist/album/duration
  metadata), `groupByArtist()`/`groupByAlbum()` za ročno grupiranje
  (`Map<String, List<Song>>`)
- `lib/core/services/media_library_providers.dart` — Riverpod providerji:
  `librarySongsProvider` (`FutureProvider<List<Song>>`, zahteva dovoljenje in
  prebere knjižnico), `songsByArtistProvider`/`songsByAlbumProvider`
  (izpeljana grupiranja)
- `lib/features/library/library_screen.dart` — nov glavni zaslon
  **"Knjižnica"** z zavihki *Vse pesmi* / *Izvajalci* / *Albumi*. Tap na
  izvajalca/album odpre podseznam pesmi znotraj skupine; tap na pesem naloži
  prikazan seznam v queue in začne predvajati od tapnjene pesmi (isti
  `unawaited(handler.play())` + takojšen `Navigator.push` vzorec kot v Fazi
  2.5, glej razlago tam). Cover art namerno izpuščen (glej TODO v
  `media_library_service.dart` — `on_audio_query` ponuja artwork le kot
  `QueryArtworkWidget`, ne kot `Uri`, primeren za `MediaItem.artUri`)
- `library_test_screen.dart` (Faza 2.5 folder-scan) ostane dosegljiv preko
  ikone mape v app baru — uporaben kot fallback za datoteke, ki jih
  MediaStore še ni indeksiral
- Preverjeno ročno na emulatorju: "Vse pesmi" prikaže vseh 5 prej prenesenih
  mp3-jev s pravim naslovom/izvajalcem (npr. "Mr. Brightside" / "The
  Killers", namesto imena mape kot prej); "Izvajalci" pravilno grupira (tudi
  robni primer - pesem s featured artistom v ID3 tagu dobi svojo skupino,
  ker je grupiranje po točnem ujemanju `artist` stringa); tap na pesem naloži
  queue in začne predvajati, `flutter analyze`/`flutter test`/
  `flutter build apk --debug` vsi prehajajo

### Faza 4 — Playlists preko drift (SQLite) ✅
- `lib/core/db/app_database.dart` — `AppDatabase` (`drift`, `NativeDatabase`
  preko `sqlite3_flutter_libs`, datoteka `music_player.sqlite` v
  `getApplicationDocumentsDirectory()`). Dve tabeli:
  - `Playlists` (`id`, `name`, `createdAt`)
  - `PlaylistSongs` (`id`, `playlistId` → FK na `Playlists` z
    `onDelete: cascade`, `position`, ter podatki o pesmi podvojeni direktno v
    vrstico: `songId`, `title`, `artist`, `album`, `filePath`, `durationMs`).
    Podatki o pesmi so namerno denormalizirani (ne FK na knjižnico), ker
    `on_audio_query`-jevi MediaStore ID-ji niso stabilna trajna referenca —
    playlista mora ostati uporabna tudi če se knjižnica kasneje spremeni/
    reindeksira.
  - `AppDatabase` metode: `watchAllPlaylists()`/`watchPlaylistSongs(id)`
    (Stream, za reaktiven UI), `createPlaylist`/`renamePlaylist`/
    `deletePlaylist`, `addSongToPlaylist` (doda na konec, `position` iz
    trenutnega count-a), `removeSongFromPlaylist`. Prosta funkcija
    `playlistSongToSong()` pretvori shranjeno vrstico nazaj v `Song` za
    predvajanje.
  - Generirano preko `build_runner` (`part 'app_database.g.dart'`,
    `flutter pub run build_runner build`)
- `lib/core/services/playlist_providers.dart` — `appDatabaseProvider`
  (singleton `AppDatabase`, `ref.onDispose(db.close)`),
  `playlistsProvider`/`playlistSongsProvider` (`StreamProvider`/
  `StreamProvider.family` nad zgornjimi `watch*` metodami)
- `lib/features/playlists/playlists_screen.dart`:
  - `PlaylistsScreen` — seznam playlist, FAB za ustvarjanje (dialog z imenom),
    per-playlista meni (tri pikice) za preimenovanje/brisanje (z
    confirm dialogom)
  - `PlaylistDetailScreen` — seznam pesmi znotraj playliste, tap predvaja
    celo playlisto od tiste pesmi naprej (isti `unawaited(play())` +
    takojšen `Navigator.push` vzorec kot povsod), gumb za odstranitev pesmi
- `lib/features/library/library_screen.dart` dopolnjen: vsaka pesem (v "Vse
  pesmi" in znotraj skupine izvajalca/albuma) ima ikono **"Dodaj v
  playlisto"**, ki odpre bottom sheet z obstoječimi playlistami + "Nova
  playlista..."; nova ikona v app baru odpre `PlaylistsScreen`
- Preverjeno ročno na emulatorju: ustvarjena playlista "Favoriti", dodana
  pesem "Mr. Brightside" preko bottom sheet-a, playlista pravilno prikaže
  dodano pesem, tap nanjo naloži queue in začne predvajati (potrjeno na
  now-playing zaslonu). `flutter analyze`/`flutter test`/
  `flutter build apk --debug` vsi prehajajo.

### Faza 5 — MVP polish: album art, akcije nad pesmijo, ročni popravki metapodatkov ✅
- `lib/core/models/song.dart` razširjen z `genre`, `year`, `trackNumber`
  (mesto na albumu, za sortiranje), `liked` + `copyWith()` (vsi parametri
  privzeto `null` → ohrani obstoječo vrednost preko `??`).
- `lib/core/db/app_database.dart` — nova tabela `SongOverrides` (`songId` PK,
  vsa ostala polja nullable — `null` pomeni "ni ročno urejeno, uporabi
  MediaStore original"): `title`/`artist`/`album`/`genre`/`year`/
  `trackNumber`/`liked`/`artworkPath`/`hidden`. `schemaVersion` 1 → 2 z
  migracijo (`m.createTable(songOverrides)`). Nove metode: `watchAllOverrides()`
  (Stream, ključan po `songId`), `upsertOverride()` (partial upsert preko
  `insertOnConflictUpdate` — v companion podana polja se posodobijo, ostala
  ostanejo nespremenjena), `setLiked()`, `hideSongEverywhere()` (nastavi
  `hidden = true` + odstrani iz vseh playlist; dejansko brisanje datoteke z
  diska je ločeno v UI plasti, DB razred namerno ne dostopa do datotečnega
  sistema).
- `lib/core/services/media_library_providers.dart` — `librarySongsProvider`
  preimenovan v `rawLibrarySongsProvider` (drag MediaStore-scan, `FutureProvider`),
  novi `songOverridesProvider` (`StreamProvider` nad `watchAllOverrides()`) in
  `librarySongsProvider` (zdaj `Provider<AsyncValue<List<Song>>>`) — reaktivno
  spoji raw knjižnico s popravki preko javne `applyOverride()` funkcije, brez
  ponovnega MediaStore-scan-a ob vsakem uporabnikovem popravku. Skrite pesmi
  (`hidden == true`) so izločene. Dodan `likedSongsProvider`.
- `lib/core/services/audio_player_service.dart` — `AudioPlayerHandler.insertNext()`
  vstavi pesem takoj za trenutno predvajano ("predvajaj naslednje"; prazen
  queue → obnaša se kot `loadQueue`). `_songToMediaItem` zdaj propagira `genre`.
- `lib/shared/widgets/song_artwork.dart` — `SongArtwork` widget: prednost ima
  uporabniško nastavljena naslovnica (`song.artUri`, lokalna datoteka),
  sicer `QueryArtworkWidget` (MediaStore artwork preko `on_audio_query`, samo
  za pesmi z `id` oblike `media_store:<int>`), sicer privzeta ikona.
- `lib/features/library/edit_song_metadata_dialog.dart` — `showEditSongMetadataDialog()`,
  `Form` z naslov/izvajalec/album/žanr/leto/mesto-na-albumu, validacija
  (naslov obvezen, leto/mesto morata biti število), shrani preko `upsertOverride()`.
- `lib/features/library/song_actions.dart` — `showSongActionsSheet()`, bottom
  sheet z vsemi akcijami nad eno pesmijo:
  - **Predvajaj naslednje** — `handler.insertNext(song)`
  - **Dodaj v playlisto** — `showAddToPlaylistSheet()` (premaknjeno sem iz
    `library_screen.dart`, zdaj javno/deljeno tudi za playliste)
  - **Priljubljena** — `setLiked(song.id, !song.liked)`, srček prikazan v
    trailing-u vsake vrstice, ko je `song.liked == true`
  - **Spremeni naslovnico** — `file_picker` (`FileType.image`), datoteka se
    skopira v `getApplicationDocumentsDirectory()/artwork/` (trajna lokacija,
    ne cache), pot shranjena preko `upsertOverride(artworkPath: ...)`
  - **Uredi metapodatke** — odpre `showEditSongMetadataDialog()`
  - **Izbriši** — confirm dialog, nato best-effort `File(song.filePath).delete()`
    (scoped storage lahko brisanje zavrne za datoteke, ki jih app ni ustvaril —
    v tem primeru se pesem vseeno skrije iz knjižnice, uporabnik dobi
    opozorilo v snackbar-u) + `hideSongEverywhere(song.id)`
- `lib/features/library/library_screen.dart` in
  `lib/features/playlists/playlists_screen.dart` posodobljena: `SongArtwork`
  kot leading v vseh seznamih pesmi (namesto generične ikone), srček za
  priljubljene, tri-pikice gumb odpre `showSongActionsSheet()`. Albumi
  (`_GroupedTab(sortByTrack: true)`) sortirajo pesmi po `trackNumber`
  naraščajoče (brez track-a na konec, nato po naslovu) namesto po abecedi.
  `PlaylistDetailScreen` spoji shranjeno `PlaylistSong` vrstico s trenutnimi
  popravki preko iste `applyOverride()` funkcije (popravki so ključani po
  `songId`, ne po `PlaylistSong.id`).
- Preverjeno ročno na emulatorju: album art se prikaže v "Vse pesmi" (pravi
  MediaStore artwork), akcijski meni se odpre in prikaže vseh 6 akcij,
  "Priljubljena" takoj doda srček v seznam, "Uredi metapodatke" pravilno
  predizpolni obstoječe vrednosti in shrani spremembo (mesto na albumu = 1),
  "Albumi" zavihek se naloži brez napak. `flutter analyze`/`flutter test`/
  `flutter build apk --debug` vsi prehajajo.

### Faza 6 — Konkurenčen core MVP ✅
Krovni milestone (ni v izvirnem master planu, ampak dodan naknadno): dvig
app-a na raven uveljavljenih Android music playerjev (Musicolet, Retro Music,
Vanilla Music) po funkcionalnosti in občutku. Celoten plan v
`/home/andra/.claude/plans/analyze-the-current-state-cozy-aho.md`.

- **6.1 Album art povsod** — `media_library_service.dart`:
  `resolveArtwork(songId)` prebere MediaStore artwork (`queryArtwork`), ga
  cache-ira na disk (`<temp>/artwork_cache/<id>.jpg`) in vrne `file://` `Uri`.
  `audio_player_service.dart`: `_resolveMediaItem()` ga uporabi za
  `MediaItem.artUri` v `loadQueue`/`addToQueue`/`insertNext` (ročna naslovnica
  ima prednost). `player_screen.dart` dobi veliko naslovnico (`SongArtwork`,
  240px) nad naslovom/izvajalcem.
- **6.2 Audio focus, interruption, auto-skip** — dodan `audio_session` paket;
  `AudioPlayerHandler` konfigurira `AudioSessionConfiguration.music()` in
  pavzira ob prekinitvi (klic/druga app) ter ob izklopu slušalk
  (`becomingNoisyEventStream`). Napaka pri predvajanju ene pesmi (pokvarjena/
  izbrisana datoteka) avtomatsko preskoči na naslednjo in prikaže snackbar
  (`playbackErrors` stream → `scaffoldMessengerKey` v `main.dart`).
- **6.3 Iskanje po knjižnici** — `librarySearchQueryProvider` +
  `filteredLibrarySongsProvider` (čista funkcija `filterLibrarySongs`, naslov/
  izvajalec/album, case-insensitive); search ikona v `library_screen.dart`
  app baru preklopi naslov v `TextField`.
- **6.4 Sortiranje "Vse pesmi"** — `Song.dateAdded` (iz MediaStore
  `DATE_ADDED`, v sekundah → pretvorjeno v `DateTime`), `SongSortOption` enum
  + `librarySortProvider` + `displayedLibrarySongsProvider` (čista funkcija
  `sortLibrarySongs`: naslov/izvajalec/album/nedavno dodano/trajanje), izbira
  preko `PopupMenuButton` v app baru.
- **6.5 "Priljubljene" zavihek** — 4. zavihek v `library_screen.dart`, vezan na
  obstoječi `likedSongsProvider`. Izločen skupen `_SongListView` widget
  (naslovnica/naslov/izvajalec/priljubljena-ikona/akcije), uporabljen v vseh
  treh mestih namesto podvojene `ListView.builder` logike.
- **6.6 Queue reorder + remove** — `AudioPlayerHandler.moveQueueItem()` in
  `removeQueueItemAt()` (override obstoječega `BaseAudioHandler` hook-a)
  posodobita `just_audio` `ConcatenatingAudioSource` in `queue`. Queue na
  `player_screen.dart` je zdaj `ReorderableListView.builder` (drag reorder) z
  gumbom za brisanje posamezne vrstice.
- **6.7 Sleep timer** — nov `sleep_timer_provider.dart`
  (`SleepTimerController`, `StateNotifier<Duration?>`) z `start(duration)`/
  `cancel()`; bedtime ikona v `player_screen.dart` app baru odpre dialog
  (15/30/45/60 min), aktiven timer prikaže odštevanje v tooltipu.
- **6.8 Hitrost predvajanja** — `AudioPlayerHandler.setSpeed()` (override
  obstoječega hook-a), `PopupMenuButton` v `player_screen.dart` app baru
  (0.75x–2.0x).
- **6.9 Dark mode** — `main.dart`: `darkTheme` + `themeMode:
  ThemeMode.system`, app samodejno sledi sistemski nastavitvi.

Namerno izpuščeno iz Faze 6 (stretch, ni blocker): resume zadnje seje po
ponovnem zagonu app-a (persist queue+pozicija čez app-kill), home-screen
widget, equalizer, lyrics.

Preverjeno ročno na emulatorju za vse zgornje UI tokove (iskanje, sortiranje,
priljubljene, queue reorder/remove, sleep timer, hitrost, dark mode preklop).
Interruption/becoming-noisy/auto-skip (6.2) preverjeno kolikor se da simulirati
na emulatorju (audio-route change, namerno pokvarjena pot do datoteke v
queue-u); dejanski dohodni klic na fizični napravi ni bil posebej testiran.
`flutter analyze`/`flutter test`/`flutter build apk --debug` vsi prehajajo po
vsakem od 6.1–6.9.

### Faza 7+ — še ni začeto
Play-history tracking, yearly wrap, bulk tagging (dejansko pisanje ID3 tagov
nazaj v datoteke), YouTube auto-download. Glej celoten plan v
`/home/andra/.claude/plans/kako-te-ko-bi-bilo-ethereal-muffin.md`.
