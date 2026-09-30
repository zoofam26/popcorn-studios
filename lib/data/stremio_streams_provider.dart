import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../domain/models.dart';
import 'magnet_builder.dart';
import 'release_parser.dart';

/// Data source for Stremio-compatible stream addons.
///
/// The primary instance is Torrentio (the addon Stremio users install for
/// maximal coverage — it aggregates ThePirateBay+, YTS+, 1337x+, RARBG and
/// a dozen more providers). One request by IMDb id returns every known
/// release with its info hash, the exact video file index inside the
/// bundle, seed count and size, which lets the app offer the full
/// quality picker without talking to the swarm first.
///
/// Endpoint contract (verified live 2026-09):
///   GET {base}/stream/movie/{imdbId}.json
///   → { "streams": [ { name, title, infoHash, fileIdx?, behaviorHints? } ] }
///   * `name`  — "Torrentio\n4k DV | HDR10+" (provider line + quality line)
///   * `title` — release name line, then a stats line with
///               👤 seeds · 💾 size · ⚙️ provider
///   * `behaviorHints.filename` — the video file inside the bundle
class StremioStreamProvider {
  StremioStreamProvider({http.Client? client, List<String>? baseUrls})
      : _client = client ?? http.Client(),
        _baseUrls = baseUrls ?? AppConstants.stremioBaseUrls;

  final http.Client _client;
  final List<String> _baseUrls;

  static final RegExp _seedExp = RegExp(r'👤\s*([\d.,]+)');
  static final RegExp _sizeExp = RegExp(r'💾\s*([\d.,]+)\s*([KMGT]i?B)');

  Map<String, String> get _headers => <String, String>{
        'User-Agent': AppConstants.apibayUserAgent,
        'accept': 'application/json',
      };

  /// Every known release for a movie IMDb id (e.g. `tt0816692`).
  Future<List<TorrentInfo>> streamsForImdb(String imdbId) async {
    Object? lastError;
    for (final String base in _baseUrls) {
      try {
        final Uri uri = Uri.parse(
            '$base/stream/movie/${imdbId.startsWith('tt') ? imdbId : 'tt$imdbId'}.json');
        final http.Response response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = StateError('HTTP ${response.statusCode}');
          continue;
        }
        final dynamic decoded =
            jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> streams =
            (decoded is Map<String, dynamic>
                    ? decoded['streams'] as List<dynamic>?
                    : null) ??
                const <dynamic>[];
        return streams
            .map(_parseStream)
            .whereType<TorrentInfo>()
            .toList(growable: false);
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    // All mirrors failed — the caller tolerates empty results.
    if (lastError != null) {
      assert(() {
        // ignore: avoid_print
        print('StremioStreamProvider: all bases failed: $lastError');
        return true;
      }());
    }
    return const <TorrentInfo>[];
  }

  TorrentInfo? _parseStream(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final String hash = ((raw['infoHash'] as String?) ?? '').toUpperCase();
    if (hash.length != 40) return null;

    final String name = (raw['name'] as String?) ?? '';
    final String title = (raw['title'] as String?) ?? '';
    final List<String> titleLines =
        title.split('\n').map((String l) => l.trim()).toList();
    final String releaseName =
        titleLines.isNotEmpty && titleLines.first.isNotEmpty
            ? titleLines.first
            : (name.split('\n').last);
    final String statsLine =
        titleLines.length > 1 ? titleLines.sublist(1).join(' ') : name;

    // Seeds.
    int seeds = 0;
    final RegExpMatch? seedMatch = _seedExp.firstMatch(statsLine);
    if (seedMatch != null) {
      seeds =
          int.tryParse(seedMatch.group(1)!.replaceAll(RegExp(r'[.,]'), '')) ??
              0;
    }

    // Size (human readable → bytes).
    int sizeBytes = 0;
    final RegExpMatch? sizeMatch = _sizeExp.firstMatch(statsLine);
    if (sizeMatch != null) {
      final double value =
          double.tryParse(sizeMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      sizeBytes = _unitToBytes(value, sizeMatch.group(2)!);
    }

    // Quality label: prefer Torrentio's own badge ("4k", "1080p"…).
    String? quality;
    final List<String> nameLines =
        name.split('\n').map((String l) => l.trim()).toList();
    if (nameLines.length > 1) {
      final String badge = nameLines.last;
      if (RegExp(r'^\d{3,4}p', caseSensitive: false).hasMatch(badge)) {
        quality = badge.split(RegExp(r'[\s|]')).first.toLowerCase();
      } else if (badge.toLowerCase().startsWith('4k')) {
        quality = '2160p';
      }
    }
    quality ??= detectQuality(releaseName);

    // Exact video file name inside the bundle, when the addon provides it.
    final Map<String, dynamic> hints =
        (raw['behaviorHints'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String? videoFile = hints['filename'] as String?;

    final int? fileIdx = (raw['fileIdx'] as num?)?.toInt();

    return TorrentInfo(
      infoHash: hash,
      name: releaseName,
      sizeBytes: sizeBytes,
      seeders: seeds,
      leechers: 0,
      source: TorrentSource.torrentio,
      magnetUri: buildMagnetUri(infoHash: hash, displayName: releaseName),
      quality: quality,
      imdbId: null,
      fileIdx: fileIdx,
      videoFileName: videoFile,
    );
  }

  static int _unitToBytes(double value, String unit) {
    final String u = unit.toUpperCase().replaceAll('IB', 'B');
    final double factor = switch (u) {
      'KB' => 1000.0,
      'MB' => 1000.0 * 1000,
      'GB' => 1000.0 * 1000 * 1000,
      'TB' => 1000.0 * 1000 * 1000 * 1000,
      _ => 1.0,
    };
    return (value * factor).round();
  }
}
