import 'dart:math' as math;

import '../domain/models.dart';
import 'apibay_provider.dart';
import 'release_parser.dart';
import 'yts_provider.dart';

/// Aggregates results from every torrent provider, de-duplicates by info
/// hash and groups them into per-quality options so the details screen can
/// present a clean `480p / 720p / 1080p / 2160p` chooser with sizes and
/// seed counts.
class TorrentSearchService {
  TorrentSearchService({
    YtsProvider? yts,
    ApibayProvider? apibay,
  })  : _yts = yts ?? YtsProvider(),
        _apibay = apibay ?? ApibayProvider();

  final YtsProvider _yts;
  final ApibayProvider _apibay;

  /// Finds every quality option available for a movie.
  ///
  /// [title] is required; [year] and [imdbId] boost matching. Individual
  /// provider failures are tolerated — the UI shows whatever succeeded.
  Future<List<QualityOption>> findOptionsForMovie({
    required String title,
    int? year,
    String? imdbId,
  }) async {
    final List<TorrentInfo> all = <TorrentInfo>[];

    if (imdbId != null && imdbId.isNotEmpty) {
      try {
        all.addAll(await _yts.search(imdbId: imdbId));
      } catch (_) {
        // Provider down or blocked — continue with the others.
      }
    }
    final String query = year == null || year == 0 ? title : '$title $year';
    try {
      all.addAll(await _yts.search(queryTerm: query));
    } catch (_) {}
    try {
      all.addAll(await _apibay.search(query));
    } catch (_) {}

    return groupIntoQualityOptions(all,
        preferredTitle: title, preferredYear: year);
  }

  /// Free-text search across providers (downloads screen "paste magnet" and
  /// fallback flows).
  Future<List<TorrentInfo>> searchAll(String query) async {
    final List<TorrentInfo> all = <TorrentInfo>[];
    try {
      all.addAll(await _apibay.search(query));
    } catch (_) {}
    try {
      all.addAll(await _yts.search(queryTerm: query));
    } catch (_) {}
    return dedupeByHash(all);
  }

  /// Groups raw torrents into quality options, choosing the group that best
  /// matches [preferredTitle]/[preferredYear] and the best-seeded torrent
  /// per quality within that group.
  List<QualityOption> groupIntoQualityOptions(
    Iterable<TorrentInfo> torrents, {
    String? preferredTitle,
    int? preferredYear,
  }) {
    final List<TorrentInfo> deduped = dedupeByHash(torrents);
    if (deduped.isEmpty) return const <QualityOption>[];

    // Score + group.
    final Map<String, List<ScoredTorrent>> groups =
        <String, List<ScoredTorrent>>{};
    for (final TorrentInfo torrent in deduped) {
      final ParsedRelease parsed = parseRelease(torrent.name);
      final double score =
          _scoreTorrent(parsed, torrent, preferredTitle, preferredYear);
      final String key =
          '${parsed.cleanTitle.isEmpty ? torrent.name.toLowerCase() : parsed.cleanTitle}'
          '|${parsed.year ?? 0}';
      groups.putIfAbsent(key, () => <ScoredTorrent>[]).add(
            ScoredTorrent(torrent, parsed, score),
          );
    }

    // Rank groups: relevance score first, total seeders as tie-breaker.
    final List<MapEntry<String, List<ScoredTorrent>>> ranked = groups.entries
        .toList()
      ..sort((MapEntry<String, List<ScoredTorrent>> a,
          MapEntry<String, List<ScoredTorrent>> b) {
        final double scoreA =
            a.value.fold(0, (double s, ScoredTorrent t) => s + t.score);
        final double scoreB =
            b.value.fold(0, (double s, ScoredTorrent t) => s + t.score);
        final int seedA =
            a.value.fold(0, (int s, ScoredTorrent t) => s + t.info.seeders);
        final int seedB =
            b.value.fold(0, (int s, ScoredTorrent t) => s + t.info.seeders);
        int cmp = scoreB.compareTo(scoreA);
        if (cmp == 0) cmp = seedB.compareTo(seedA);
        return cmp;
      });

    final List<ScoredTorrent> bestGroup =
        ranked.isEmpty ? const <ScoredTorrent>[] : ranked.first.value;

    // Best torrent per quality inside the winning group.
    final Map<String, TorrentInfo> bestPerQuality = <String, TorrentInfo>{};
    for (final ScoredTorrent scored in bestGroup) {
      final String label =
          scored.parsed.quality ?? scored.info.quality ?? 'auto';
      final TorrentInfo? current = bestPerQuality[label];
      if (current == null || scored.info.seeders > current.seeders) {
        bestPerQuality[label] = scored.info;
      }
    }

    final List<QualityOption> options = bestPerQuality.entries
        .map((MapEntry<String, TorrentInfo> e) =>
            QualityOption(label: _prettyQuality(e.key), best: e.value))
        .toList(growable: false)
      ..sort((QualityOption a, QualityOption b) =>
          _qualityRank(b.label).compareTo(_qualityRank(a.label)));
    return options;
  }

  /// Removes duplicate info hashes, preferring entries that carry a direct
  /// .torrent URL and, among those, the best seed count.
  List<TorrentInfo> dedupeByHash(Iterable<TorrentInfo> torrents) {
    final Map<String, TorrentInfo> byHash = <String, TorrentInfo>{};
    for (final TorrentInfo torrent in torrents) {
      final String hash = torrent.infoHash.toUpperCase();
      if (hash.length != 40) continue;
      final TorrentInfo? existing = byHash[hash];
      if (existing == null) {
        byHash[hash] = torrent;
        continue;
      }
      byHash[hash] = _prefer(existing, torrent);
    }
    return byHash.values.toList(growable: false)
      ..sort((TorrentInfo a, TorrentInfo b) => b.seeders.compareTo(a.seeders));
  }

  TorrentInfo _prefer(TorrentInfo a, TorrentInfo b) {
    final bool aHasUrl = (a.torrentUrl ?? '').isNotEmpty;
    final bool bHasUrl = (b.torrentUrl ?? '').isNotEmpty;
    if (aHasUrl != bHasUrl) return aHasUrl ? a : b;
    return a.seeders >= b.seeders ? a : b;
  }

  double _scoreTorrent(
    ParsedRelease parsed,
    TorrentInfo torrent,
    String? preferredTitle,
    int? preferredYear,
  ) {
    double score = 0;
    if (preferredTitle != null && preferredTitle.isNotEmpty) {
      score += titleSimilarity(parsed.cleanTitle, preferredTitle) * 10;
    }
    if (preferredYear != null &&
        preferredYear > 0 &&
        parsed.year != null &&
        parsed.year == preferredYear) {
      score += 4;
    }
    score += torrent.seeders > 0
        ? math.log(torrent.seeders + 1) / math.ln2 * 0.6
        : 0;
    if ((torrent.torrentUrl ?? '').isNotEmpty) score += 0.5;
    return score;
  }

  static int _qualityRank(String label) => switch (label) {
        '2160p' => 6,
        '1440p' => 5,
        '1080p' => 4,
        '720p' => 3,
        '480p' => 2,
        '360p' => 1,
        _ => 0,
      };

  static String _prettyQuality(String label) => label == 'auto'
      ? 'Auto'
      : RegExp(r'^\d+p$').hasMatch(label)
          ? label
          : label.toUpperCase();
}

class ScoredTorrent {
  const ScoredTorrent(this.info, this.parsed, this.score);

  final TorrentInfo info;
  final ParsedRelease parsed;
  final double score;
}
