/// Predstavlja eno pesem v knjižnici, ne glede na to ali je vir
/// lokalna datoteka na napravi ali kasneje prenesena preko downloads feature-ja.
///
/// `genre`/`year`/`trackNumber`/`liked`/`artUri` so lahko iz MediaStore
/// metadata (kjer na voljo) ali uporabniško ročno urejeni preko
/// "Uredi metapodatke" (glej `lib/core/db/app_database.dart` - `SongOverrides`
/// tabela hrani te ročne popravke lokalno, brez pisanja nazaj v ID3 tage).
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    this.duration,
    this.artUri,
    this.genre,
    this.year,
    this.trackNumber,
    this.liked = false,
    this.dateAdded,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration? duration;
  final Uri? artUri;
  final String? genre;
  final int? year;

  /// Kdaj je bila pesem dodana v MediaStore (za sortiranje "Nedavno dodano"
  /// v knjižnici, glej Faza 6.4). `null` za pesmi brez znanega datuma
  /// (npr. ročni folder-scan).
  final DateTime? dateAdded;

  /// Zaporedna številka na albumu (1., 2. ...) - uporabljena za sortiranje
  /// pesmi znotraj albuma po pravem vrstnem redu namesto po abecedi.
  final int? trackNumber;
  final bool liked;

  /// Normalizirana polja za pogosto iskanje in sortiranje. Ker je [Song]
  /// nespremenljiv, jih Expando izračuna največ enkrat na instanco namesto ob
  /// vsaki primerjavi med filtriranjem/sortiranjem velike knjižnice. Expando
  /// ohrani tudi `const Song` konstruktor, ki ga uporabljajo testi in UI.
  _SongSearchFields get _searchFields =>
      _songSearchFields[this] ??= _SongSearchFields(this);

  String get normalizedTitle => _searchFields.title;
  String get normalizedArtist => _searchFields.artist;
  String get normalizedAlbum => _searchFields.album;

  bool matchesLibraryQuery(String normalizedQuery) =>
      normalizedTitle.contains(normalizedQuery) ||
      normalizedArtist.contains(normalizedQuery) ||
      normalizedAlbum.contains(normalizedQuery);

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    Uri? artUri,
    String? genre,
    int? year,
    int? trackNumber,
    bool? liked,
    DateTime? dateAdded,
  }) {
    return Song(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      filePath: filePath,
      duration: duration ?? this.duration,
      artUri: artUri ?? this.artUri,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      liked: liked ?? this.liked,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final Expando<_SongSearchFields> _songSearchFields = Expando();

class _SongSearchFields {
  _SongSearchFields(Song song)
    : title = song.title.toLowerCase(),
      artist = song.artist.toLowerCase(),
      album = song.album.toLowerCase();

  final String title;
  final String artist;
  final String album;
}
