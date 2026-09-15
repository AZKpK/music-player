// Wrap zaslon (glej docs/spec-wrap.md "UI") - top izvajalci/albumi/pesmi,
// skupne minute in žanr toggle + top žanr za trenutno (odprto) Wrap obdobje,
// ter povezavi do dveh generiranih playlist. Prikazane statistike so vedno
// "žive" (samo branje - glej spec "Trigger"); regeneracija playlist se
// sproži ob odprtju zaslona, a dejansko naredi kaj le, če je reset-meja bila
// prestopljena od zadnje generacije (glej WrapPlaylistGenerator.regenerateIfDue).

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/services/playlist_providers.dart';
import '../../core/services/wrap_stats_service.dart';
import '../playlists/playlists_screen.dart';
import 'wrap_providers.dart';

class WrapScreen extends ConsumerStatefulWidget {
  const WrapScreen({super.key});

  @override
  ConsumerState<WrapScreen> createState() => _WrapScreenState();
}

class _WrapScreenState extends ConsumerState<WrapScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: sama funkcija je no-op, če regeneracija ni potrebna
    // (glej WrapPlaylistGenerator.regenerateIfDue) - ne blokira statistik.
    ref.read(wrapPlaylistGeneratorProvider).regenerateIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(wrapStatsProvider);
    final genreEnabled = ref.watch(wrapGenreEnabledProvider);
    final bounds = ref.watch(wrapPeriodBoundsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Wrap ${bounds.currentPeriodStart.year}')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (stats) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TotalMinutesCard(totalListened: stats.totalListened),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Prikaži top žanr'),
              value: genreEnabled,
              onChanged: (value) => ref
                  .read(appDatabaseProvider)
                  .updateWrapSettings(genreEnabled: value),
            ),
            if (genreEnabled && stats.topGenre != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(label: Text('Top žanr: ${stats.topGenre}')),
              ),
            const SizedBox(height: 8),
            if (stats.topSongs.isNotEmpty) ...[
              const _SectionTitle('Top pesmi'),
              SizedBox(
                height: 220,
                child: _TopSongsChart(
                  topSongs: stats.topSongs.take(5).toList(),
                ),
              ),
            ],
            _RankedList(
              title: null,
              entries: [
                for (final s in stats.topSongs)
                  _RankedEntry(name: s.song.title, playCount: s.playCount),
              ],
            ),
            _RankedList(
              title: 'Top izvajalci',
              entries: [
                for (final a in stats.topArtists)
                  _RankedEntry(name: a.name, playCount: a.playCount),
              ],
            ),
            _RankedList(
              title: 'Top albumi',
              entries: [
                for (final a in stats.topAlbums)
                  _RankedEntry(name: a.name, playCount: a.playCount),
              ],
            ),
            const SizedBox(height: 8),
            const _SectionTitle('Playliste'),
            _WrapPlaylistTile(name: 'Wrap ${bounds.previousPeriodStart.year}'),
            const _WrapPlaylistTile(name: 'Wrap All-Time'),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _TotalMinutesCard extends StatelessWidget {
  const _TotalMinutesCard({required this.totalListened});

  final Duration totalListened;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${totalListened.inMinutes} min',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text('Skupno poslušanega'),
          ],
        ),
      ),
    );
  }
}

class _TopSongsChart extends StatelessWidget {
  const _TopSongsChart({required this.topSongs});

  final List<WrapSongStat> topSongs;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: [
          for (var i = 0; i < topSongs.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(toY: topSongs[i].playCount.toDouble()),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= topSongs.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    topSongs[index].song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RankedEntry {
  const _RankedEntry({required this.name, required this.playCount});

  final String name;
  final int playCount;
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.title, required this.entries});

  final String? title;
  final List<_RankedEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) _SectionTitle(title!),
        for (var i = 0; i < entries.length; i++)
          ListTile(
            dense: true,
            leading: Text('${i + 1}'),
            title: Text(
              entries[i].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text('${entries[i].playCount}x'),
          ),
      ],
    );
  }
}

/// Povezava do ene izmed dveh generiranih Wrap playlist (glej spec "Top-100
/// playlists") - `name` je iskan v [playlistsProvider], ker se te playliste
/// ustvarijo šele ob dejanski regeneraciji (morda še ne obstajajo, npr. prvi
/// zagon brez zgodovine predvajanja).
class _WrapPlaylistTile extends ConsumerWidget {
  const _WrapPlaylistTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? const [];
    Playlist? playlist;
    for (final p in playlists) {
      if (p.name == name) {
        playlist = p;
        break;
      }
    }

    return ListTile(
      leading: const Icon(Icons.queue_music),
      title: Text(name),
      enabled: playlist != null,
      subtitle: playlist == null ? const Text('Še ni na voljo') : null,
      onTap: playlist == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(playlist: playlist!),
              ),
            ),
    );
  }
}
