import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/errors.dart';
import '../domain/models.dart';
import 'magnet_builder.dart';
import 'release_parser.dart';

/// Data source for the YTS movie API, hosted on several mirrors with
/// automatic fail-over (verified live 2026-09: `yts.mx` is DNS-blocked in
/// some regions while `.am/.lt/.ag` redirect to a working host).
class YtsProvider {
  YtsProvider({http.Client? client, List<String>? baseUrls})
      : _client = client ?? http.Client(),
        _baseUrls = baseUrls ?? AppConstants.ytsBaseUrls;

  final http.Client _client;
  final List<String> _baseUrls;

  Future<dynamic> _get(String path, Map<String, String> query) async {
    Object? lastError;
    for (final String base in _baseUrls) {
      try {
        final Uri uri =
            Uri.parse('$base/api/v2$path').replace(queryParameters: query);
        final http.Response response = await _client.get(uri,
            headers: <String, String>{
              'accept': 'application/json'
            }).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = NetworkException('YTS HTTP ${response.statusCode}');
          continue;
        }
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == 'ok') {
          return decoded;
        }
        lastError = const NetworkException('YTS returned a failure status');
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    throw NetworkException('All YTS mirrors failed', cause: lastError);
  }

  /// Search by free text or IMDb id (`tt…`).
  Future<List<TorrentInfo>> search({
    String? queryTerm,
    String? imdbId,
    int limit = 50,
  }) async {
    final Map<String, String> query = <String, String>{
      'limit': '$limit',
      if (imdbId != null && imdbId.isNotEmpty) 'query_term': imdbId,
      if ((imdbId == null || imdbId.isEmpty) && queryTerm != null)
        'query_term': queryTerm,
    };
    final dynamic data = await _get('/list_movies.json', query);
    final Map<String, dynamic> payload =
        (data['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> movies =
        (payload['movies'] as List<dynamic>?) ?? const <dynamic>[];
    final List<TorrentInfo> results = <TorrentInfo>[];
    for (final dynamic movieJson in movies) {
      results.addAll(_parseMovie(movieJson as Map<String, dynamic>));
    }
    return results;
  }

  List<TorrentInfo> _parseMovie(Map<String, dynamic> movie) {
    final String title = (movie['title'] as String?) ?? '';
    final String titleLong = (movie['title_long'] as String?) ?? title;
    final String imdb = (movie['imdb_code'] as String?) ?? '';
    final List<dynamic> torrents =
        (movie['torrents'] as List<dynamic>?) ?? const <dynamic>[];

    return torrents
        .map((dynamic t) {
          final Map<String, dynamic> json = t as Map<String, dynamic>;
          final String hash = (json['hash'] as String?)?.toUpperCase() ?? '';
          if (hash.isEmpty) {
            return null;
          }
          final String name = '$titleLong.${json['quality']}.YTS.$hash';
          return TorrentInfo(
            infoHash: hash,
            name: name,
            sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
            seeders: (json['seeds'] as num?)?.toInt() ?? 0,
            leechers: (json['peers'] as num?)?.toInt() ?? 0,
            source: TorrentSource.yts,
            magnetUri: buildMagnetUri(infoHash: hash, displayName: titleLong),
            torrentUrl: (json['url'] as String?) ?? '',
            quality: (json['quality'] as String?) ?? detectQuality(name),
            uploadedAt: _parseUploaded(json['date_uploaded_unix']),
            imdbId: imdb.isEmpty ? null : imdb,
          );
        })
        .whereType<TorrentInfo>()
        .toList(growable: false);
  }

  DateTime? _parseUploaded(dynamic seconds) {
    final int? value = (seconds as num?)?.toInt();
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
}
