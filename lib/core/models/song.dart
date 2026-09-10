/// Predstavlja eno pesem v knjižnici, ne glede na to ali je vir
/// lokalna datoteka na napravi ali kasneje prenesena preko downloads feature-ja.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    this.duration,
    this.artUri,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration? duration;
  final Uri? artUri;

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
