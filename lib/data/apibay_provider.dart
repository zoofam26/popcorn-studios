import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/errors.dart';
import '../domain/models.dart';
import 'magnet_builder.dart';
import 'release_parser.dart';

/// Data source for apibay.org — The Pirate Bay's official JSON API.
///
/// Notes from live verification (2026-09):
///  * Every endpoint requires a browser-like `User-Agent`, otherwise the
///    Cloudflare rule returns 403.
///  * `size` is a byte-count encoded as a *string*.
///  * An empty search returns the sentinel string `"No results"`.
class ApibayProvider {
  ApibayProvider({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConstants.apibayBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Map<String, String> get _headers => <String, String>{
        'User-Agent': AppConstants.apibayUserAgent,
        'accept': 'application/json',
      };

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final http.Response response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw NetworkException('apibay HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  /// Searches torrents by free-text query.
  Future<List<TorrentInfo>> search(String query) async {
    final dynamic data =
        await _get('/q.php', <String, String>{'q': query, 'cat': '0'});
    if (data is String) return const <TorrentInfo>[]; // "No results"
    final List<dynamic> items = data as List<dynamic>;
    return items
        .map(_parseEntry)
        .whereType<TorrentInfo>()
        .toList(growable: false);
  }

  /// Top torrents of the last 48h in a category (0 = all).
  Future<List<TorrentInfo>> top48({int category = 0}) async {
    final dynamic data =
        await _get('/top48h.php', <String, String>{'cat': '$category'});
    if (data is String) return const <TorrentInfo>[];
    final List<dynamic> items = data as List<dynamic>;
    return items
        .map(_parseEntry)
        .whereType<TorrentInfo>()
        .toList(growable: false);
  }

  TorrentInfo? _parseEntry(dynamic entry) {
    final Map<String, dynamic> json = entry as Map<String, dynamic>;
    final String hash = (json['info_hash'] as String?)?.toUpperCase() ?? '';
    final String name = (json['name'] as String?) ?? '';
    if (hash.isEmpty || hash.length != 40 || name.isEmpty) return null;

    return TorrentInfo(
      infoHash: hash,
      name: name,
      sizeBytes: int.tryParse('${json['size']}') ?? 0,
      seeders: int.tryParse('${json['seeders']}') ?? 0,
      leechers: int.tryParse('${json['leechers']}') ?? 0,
      source: TorrentSource.apibay,
      magnetUri: buildMagnetUri(
        infoHash: hash,
        displayName: name,
      ),
      tpbNumericId: int.tryParse('${json['id']}'),
      quality: detectQuality(name),
      uploadedAt: _parseEpoch(json['added']),
      imdbId: _normalizeImdb(json['imdb']),
    );
  }

  DateTime? _parseEpoch(dynamic value) {
    final int? seconds = int.tryParse('$value');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  String? _normalizeImdb(dynamic value) {
    final String raw = '$value';
    if (raw.isEmpty || raw == '0') return null;
    return raw.startsWith('tt') ? raw : 'tt$raw';
  }
}
