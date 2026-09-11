# Plan: napisati `docs/plan1.md` (Faza 7 — parity s konkurenčnimi playerji)

## Context

Uporabnik je po testiranju MVP_v1 APK-ja na telefonu zapisal 7 konkretnih napak/želja v
`docs/napake.md`. Naloga: pregledati kodo, diagnosticirati vsako točko in napisati
`docs/plan1.md` — izvedbeni dokument, ki opiše, kaj je treba popraviti in izboljšati, da bo
MVP izgledal in deloval enako dobro kot uveljavljeni Android playerji (Musicolet, Retro
Music, Vanilla Music).

Odločitve, potrjene z uporabnikom:
- Dokument pokrije **7 točk iz `napake.md` (P0)** + **ločeno sekcijo konkurenčnih vrzeli
  (P1)**, najdenih med pregledom kode.
- Shuffle se rešuje z **lastnim vrstnim redom predvajanja** (brez internega shuffla v
  just_audio), da je prikazana vrsta identična dejanskemu vrstnemu redu in drag & drop
  deluje brez preslikave indeksov.

**Edini deliverable te naloge je nova datoteka `docs/plan1.md`** (v slovenščini, enak stil
kot README in `napake.md`). Koda se v tem koraku NE spreminja — plan1.md je načrt za
naslednjo sejo. Spodaj je vsebina, ki gre v ta dokument.

---

## Diagnoze (preverjeno v kodi — to je jedro dokumenta)

### N1 — vizualni timer skoči nazaj ob kliku na shuffle/repeat
**Vzrok najden.** `AudioService.position` računa pozicijo kot
`updatePosition + (now - updateTime)` (`audio_service-0.18.19/lib/audio_service.dart:266-278`).
`PlaybackState.copyWith` prenese **star** `value.updatePosition`
(`audio_service.dart:411-413`), konstruktor pa nastavi `updateTime = clock.now()`
(`audio_service.dart:256`). Vsak ročni `playbackState.add(...copyWith(...))` torej zavrti
uro nazaj na zadnje sidro iz `_broadcastState`.
Edini dve taki mesti: `setShuffleMode` (`audio_player_service.dart:176`) in `setRepeatMode`
(`audio_player_service.dart:187`) — natanko gumba, ki ju uporabnik navaja.

**Popravek:** eno samo mesto za oddajanje stanja. Shrani `_repeatMode`/`_shuffleMode` v
polji, vključi ju v `_broadcastState`, setterja pa po spremembi pokličeta
`_broadcastState(_player.playbackEvent)` (getter obstaja: `just_audio.dart:379`). Nikjer
drugje ne kličemo `playbackState.add` ročno. Isti popravek pokrije tudi `setSpeed`.

### N2 — ločen zaslon "Naslednje v vrsti" + drag & drop v dejanskem vrstnem redu
Danes je queue prilepljen pod kontrolami v `player_screen.dart:223-256` in prikazuje
`queue.value`, torej **originalni** vrstni red — v shuffle načinu to ni vrstni red
predvajanja (`_player` uporablja svoj `shuffleIndices`).

**Popravek (izbrana arhitektura — lasten vrstni red):**
- `AudioPlayerHandler` hrani `List<Song> _sourceOrder` (posnetek ob `loadQueue`).
- `setShuffleMode(all)`: nov vrstni red = trenutna pesem + premešane ostale. Uporabi
  **3 klice** na `ConcatenatingAudioSource`: `removeRange(cur+1, len)`, `removeRange(0, cur)`,
  `addAll(rest)` — trenutna pesem se nikoli ne odstrani, zato predvajanje ne prekine.
- `setShuffleMode(none)`: enako oklesti na trenutno pesem, nato `insertAll(0, prejšnje)` +
  `addAll(naslednje)` iz `_sourceOrder`.
- `queue` (MediaItem-i) se posodobi enako → **prikaz == play order**; `_player.shuffleModeEnabled`
  ostane `false`, `playbackState.shuffleMode` pa nosi UI/notifikacijsko stanje.
- `moveQueueItem` (`audio_player_service.dart:132`) in `removeQueueItemAt` ostaneta
  nespremenjena in zdaj pravilno delujeta tudi v shuffle načinu; posodabljati je treba še
  `_sourceOrder`.
- Nov `lib/features/player/queue_screen.dart`, odprt z `Icons.queue_music` gumbom v AppBar
  `PlayerScreen`; queue se iz `player_screen.dart` odstrani (zaslon dobi prostor za večjo
  naslovnico → tudi vizualno bližje konkurenci). Na zaslonu: trenutna pesem označena,
  `ReorderableListView`, odstrani vrstico, "Počisti vrsto", tap = skoči na pesem.
- **Robni primer:** `ValueKey(item.id)` (`player_screen.dart:241`) se podvoji, če je ista
  pesem dvakrat v vrsti (možno prek "Predvajaj naslednje") → drag se poruši. Vsakemu vnosu
  dodeli unikaten `queueItemId` v `MediaItem.extras` in ga uporabi kot ključ.

### N3 — A–Z hitro drsenje (3000 pesmi)
**Popravek brez novega paketa:**
- `_SongListView` (`library_screen.dart:208`) dobi `ScrollController` in **`itemExtent: 64`**
  (vse vrstice so enako visoke) → `offset = index * 64` je točen, mogoč je `jumpTo`.
- Nova čista funkcija `buildAlphabetIndex(List<Song>, SongSortOption) -> List<(String label,
  int index)>` (prva črka naslova/izvajalca/albuma glede na aktiven sort; ne-črka → `#`) —
  izločena zaradi testabilnosti, enak vzorec kot `filterLibrarySongs`/`sortLibrarySongs`
  (`media_library_providers.dart:121,156`).
- Nov `lib/shared/widgets/alphabet_scroll_bar.dart`: navpičen trak oznak desno,
  `onTapDown` + `onVerticalDragUpdate` → oznaka iz `localPosition.dy` → `jumpTo(min(index *
  extent, maxScrollExtent))` + kratek overlay z veliko črko (kot Musicolet).
- Dodatno `Scrollbar(controller:, interactive: true, thumbVisibility: true)` za klasično
  vlečenje palca.
- Trak skrit pri sortiranju "Nedavno dodano"/"Trajanje" (abecedni indeks tam ni smiseln).

### N4 — vizualna indikacija shuffla
`player_screen.dart:176`: `Icon(Icons.shuffle)` → `Icon(shuffleOn ? Icons.shuffle_on :
Icons.shuffle)`. Oba ikona-koda obstajata v Material setu (`shuffle_on = 0xe5a2`,
`repeat_on = 0xe520`), torej natanko isti vzorec kot `_repeatIcon`
(`player_screen.dart:268`). Enako v novem queue zaslonu.

### N5 — lag spike ob predvajanju iz 3000-pesemske knjižnice
**Dva vzroka v `loadQueue` (`audio_player_service.dart:101-106`):**
1. `Future.wait(songs.map(_resolveMediaItem))` sproži **eno MediaStore `queryArtwork` +
   zapis JPEG datoteke na pesem** (3000 platform klicev + 3000 zapisov) *preden* se sploh
   začne predvajanje. To je glavni krivec, ne dolžina vrste.
2. `_playlist.addAll` s 3000 viri.

**Popravek 1 (lazy artwork):** `loadQueue` gradi `MediaItem`-e sinhrono
(`_songToMediaItem`) in queue objavi takoj; artwork se dorazreši samo za trenutno (in
naslednjo) pesem v `_handleCurrentIndexChanged`, nato posodobi `mediaItem` + vnos v `queue`.
Diskovni cache v `resolveArtwork` (`media_library_service.dart:60`) ostane nespremenjen.
**Popravek 2 (okno vrste):** `const kMaxQueueLength = 250;` + čista funkcija
`buildQueueWindow(List<Song> songs, int startIndex, {int maxLength})`, ki vrne okno, ki se
začne pri izbrani pesmi in se ovije (wrap) na začetek seznama. Klicna mesta:
`library_screen.dart:_playFrom` (:321), `library_test_screen.dart:_loadAndOpenPlayer` (:106)
in predvajanje playliste. Vrednost kasneje v nastavitve (V6).

### N6 — folder-scan: mrtev/siv seek slider
**Vzrok najden.** `scanFolderForSongs` (`library_scanner.dart:46-53`) in `_pickFilesAndPlay`
(`library_test_screen.dart:92-98`) ustvarita `Song` **brez `duration`** → `MediaItem.duration
== null` → `_SeekBar` dobi `maxMs <= 0` → `onChanged: null` (siv, onemogočen slider)
in prikaz stoji na `00:00` (`player_screen.dart:305-321`).

**Popravek (splošen):** `AudioPlayerHandler` naroči na `_player.durationStream`; ko
just_audio prebere pravo dolžino iz datoteke, posodobi `mediaItem` in ustrezen vnos v
`queue` z `copyWith(duration: ...)`. Pokrije tudi MediaStore pesmi z manjkajočim `DURATION`.
Dodatno: `_SeekBar` naj do prihoda dolžine kaže `--:--` namesto `00:00`.
Nizka cena, isti popravek: folder-scan naj `dateAdded` napolni iz `File.statSync().modified`,
da "Nedavno dodano" deluje tudi za te pesmi.

### N7 — slike izvajalcev in albumov
- **DB:** nova drift tabela `GroupArtworks(groupType, groupKey, artworkPath)`,
  `PK(groupType, groupKey)`; `schemaVersion: 2 → 3` in migracija
  `if (from < 3) await m.createTable(groupArtworks);` — točno obstoječi vzorec
  (`app_database.dart:69-79`). Metode `watchAllGroupArtworks()`, `setGroupArtwork()`,
  `clearGroupArtwork()`.
- **Provider:** `groupArtworksProvider` (StreamProvider), enak vzorec kot
  `songOverridesProvider` (`media_library_providers.dart:33`).
- **Widget:** nov `GroupArtwork(groupType, groupKey, fallbackSong, size)` — ročna slika ima
  prednost, sicer `SongArtwork(song: fallbackSong)`, torej **privzeto naslovnica prve pesmi
  v skupini**, kot je uporabnik zahteval.
- **UI:** `_GroupedTab` (`library_screen.dart:266`) zamenja `Icon(Icons.folder)` z
  `GroupArtwork`; long-press / `trailing` meni → "Spremeni sliko" / "Odstrani sliko".
- **Brez podvajanja:** obstoječi `_changeArtwork` (`song_actions.dart:93-117`) refaktoriraj v
  skupno `pickAndStoreArtwork(String safeKey) -> Future<String?>` (file_picker → kopija v
  `<docs>/artwork/<key>.<ext>`), ki jo uporabita pesem in skupina.

---

## P1 — konkurenčne vrzeli, najdene med pregledom kode

| # | Vrzel | Dokaz v kodi |
|---|---|---|
| V1 | **Manjka `POST_NOTIFICATIONS`** → na Android 13+ je media notifikacija/lock-screen kontrola tiho blokirana | `AndroidManifest.xml` (ima le WAKE_LOCK/FOREGROUND_SERVICE/READ_MEDIA_AUDIO) |
| V2 | Ni nadaljevanja seje po ponovnem zagonu (queue + pozicija + shuffle/repeat) | namerno izpuščeno v Fazi 6 (README) |
| V3 | Iskanje deluje samo v "Vse pesmi"; polje ostane odprto na ostalih zavihkih, kjer ne naredi nič | `filteredLibrarySongsProvider` veže samo `_AllSongsTab` |
| V4 | Ni "Predvajaj vse"/"Premešaj vse" na vrhu seznamov; ni album/artist header-ja (naslovnica, št. pesmi, skupno trajanje) | `_SongListView`, `_GroupSongsScreen:302` |
| V5 | Trajanje pesmi ni prikazano v seznamih, čeprav `Song.duration` obstaja | `library_screen.dart:219-236` |
| V6 | Ni zaslona z nastavitvami (dolžina vrste, tema, privzet sort) | tema je trdo `ThemeMode.system` (`main.dart:56`) |
| V7 | `Image.file` brez `cacheWidth` dekodira polno ločljivost za 48 px vrstico → poraba pomnilnika / janky scroll pri 3000 vrsticah | `song_artwork.dart:28` |
| V8 | Mini player: "naslednja" onemogočena na zadnjem indeksu tudi pri repeat-all; ni swipe za menjavo pesmi | `mini_player.dart:165` |
| V9 | `_handlePlaybackError` → `skipToNext()` brez varovala: pokvarjena mapa zavrti cel queue s snackbarjem na vsako pesem | `audio_player_service.dart:79-87` |
| V10 | `Song.copyWith` z `??` ne more počistiti polja → praznjenje npr. `genre` v "Uredi metapodatke" se ne odrazi | `song.dart:44-70` |
| V11 | `currentSongProvider` gradi `Song` s `filePath: ''` — past ob širjenju akcij na player zaslon; `filePath` naj gre v `MediaItem.extras` | `media_library_providers.dart:203` |
| V12 | Branding: `android:label="music_player"`, privzeta Flutter ikona | `AndroidManifest.xml` |
| V13 | Playliste: ni predvajanja cele playliste z enim tapom, ni reorder-ja (`position` obstaja, update metode ni), ni dodajanja več pesmi hkrati | `app_database.dart:109-132` |
| V14 | Prazno stanje ob zavrnjenem dovoljenju kaže samo besedilo izjeme; manjka "Odpri nastavitve" (`openAppSettings()`) | `library_screen.dart:131-134` |
| V15 | TabBarView ne ohranja pozicije drsenja med zavihki (`AutomaticKeepAliveClientMixin`) | `library_screen.dart:139-146` |
| V16 | Ni "Nedavno predvajano"/"Največkrat predvajano" — konkurenca to ima; sodi v Fazo 7 play-history, samo omenjeno kot naslednji milestone | README "Faza 7+" |

---

## Struktura dokumenta `docs/plan1.md`

1. **Namen in kontekst** — izhodišče (MVP_v1 APK, testiran na telefonu), kaj pomeni
   "enako dobro kot konkurenca", povezava na `docs/napake.md` in README Fazo 6.
2. **P0 — napake iz `napake.md`**, po ena podsekcija N1–N7, vsaka z: *Simptom* (dobesedno iz
   napake.md) → *Vzrok* (z `datoteka:vrstica`) → *Popravek* → *Merilo sprejemljivosti*.
3. **P1 — konkurenčne vrzeli** (tabela V1–V16 zgoraj, razširjena z opisom popravka).
4. **Vrstni red izvedbe** — predlagane podfaze 7.1–7.9 z odvisnostmi:
   - 7.1 N1 (timer desync) + N4 (shuffle ikona) — najmanjši popravek, takoj opazen
   - 7.2 N5 (lazy artwork + okno 250) — odpravi lag, pogoj za dobro počutje pri 3000 pesmih
   - 7.3 N2 (lasten play order + queue zaslon) — gradi na 7.2
   - 7.4 N6 (durationStream) + V9 (varovalo napak)
   - 7.5 N3 (A–Z scroll)
   - 7.6 N7 (slike skupin, DB v3) + V4 (header s play/shuffle)
   - 7.7 V1 + V12 (notifikacije, branding) — pogoj za "deluje kot pravi player"
   - 7.8 V2 (resume seje) + V6 (nastavitve, kjer pristane dolžina vrste)
   - 7.9 preostale drobne vrzeli (V3, V5, V7, V8, V10, V11, V13, V14, V15)
5. **Novi/spremenjeni fajli** — pregledna tabela.
6. **Testiranje in verifikacija** (glej spodaj).
7. **Namerno izven obsega** — equalizer, lyrics, home-screen widget, crossfade, ID3
   write-back, YouTube download (Faza 8+/9).

## Datoteke

Ustvari: `docs/plan1.md`. Nič drugega se v tem koraku ne spreminja.

## Verifikacija

Ker je deliverable dokument, verifikacija je pregled vsebine:
- Vsaka od 7 točk v `docs/napake.md` ima v `plan1.md` svojo podsekcijo z vzrokom in popravkom
  (1:1 pokritost, preveri s primerjavo obeh datotek).
- Vsaka navedena referenca `datoteka:vrstica` se ujema z dejansko kodo (`grep`/`Read`
  vzorčno na N1, N5, N6, N7 — te so bile med pisanjem plana že preverjene v izvorni kodi
  `audio_service`/`just_audio` v `~/.pub-cache`).
- Dokument je v slovenščini, v enakem stilu kot README (podfaze, `koda` reference, merila).

Za naslednjo sejo (izvedba plana) velja standardna zanka projekta: `flutter analyze`,
`flutter test` (novi unit testi za `buildQueueWindow`, `buildAlphabetIndex` in za gradnjo
shuffle vrstnega reda — enak vzorec kot `test/media_library_filter_test.dart`),
`flutter build apk --debug`, nato ročni scenariji na emulatorju/napravi.
