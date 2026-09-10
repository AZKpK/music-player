import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'media_library_service.dart';

final mediaLibraryServiceProvider = Provider<MediaLibraryService>((ref) {
  return MediaLibraryService();
});

/// Zahteva dovoljenje za branje glasbe in nato prebere vse pesmi z naprave
/// preko MediaStore. `false` znotraj [AsyncValue] ni mogoč - zavrnjeno
/// dovoljenje vrže izjemo, ki jo UI ujame preko `.when(error: ...)`.
final librarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.watch(mediaLibraryServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) {
    throw Exception('Dovoljenje za dostop do glasbe je zavrnjeno');
  }
  return service.querySongs();
});

/// Pesmi grupirane po izvajalcu, izpeljano iz [librarySongsProvider].
final songsByArtistProvider = Provider<AsyncValue<Map<String, List<Song>>>>((ref) {
  final service = ref.watch(mediaLibraryServiceProvider);
  return ref.watch(librarySongsProvider).whenData(service.groupByArtist);
});

/// Pesmi grupirane po albumu, izpeljano iz [librarySongsProvider].
final songsByAlbumProvider = Provider<AsyncValue<Map<String, List<Song>>>>((ref) {
  final service = ref.watch(mediaLibraryServiceProvider);
  return ref.watch(librarySongsProvider).whenData(service.groupByAlbum);
});
