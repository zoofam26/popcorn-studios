import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/errors.dart';
import '../domain/models.dart';

/// OpenSubtitles.com REST client.
///
/// Live-verified gotchas baked into this implementation:
///  * `Api-Key` header is mandatory; `User-Agent` must be present.
///  * Query parameters are sent in alphabetical order (the API 301-redirects
///    otherwise).
///  * Downloads use **POST /download** (the old GET form 404s) and return a
///    time-limited `link`; the daily quota is returned as `remaining`.
class OpenSubtitlesService {
  OpenSubtitlesService({
    http.Client? client,
    String? baseUrl,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConstants.openSubtitlesBaseUrl,
        _apiKey = apiKey ?? AppConstants.openSubtitlesApiKey;

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  int? lastRemainingQuota;

  Map<String, String> get _headers => <String, String>{
        'Api-Key': _apiKey,
        'User-Agent': AppConstants.openSubtitlesUserAgent,
        'Accept': 'application/json',
      };

  Future<dynamic> _get(String path, Map<String, String> sortedQuery) async {
    final List<String> sortedKeys = sortedQuery.keys.toList()..sort();
    final Map<String, String> ordered = <String, String>{
      for (final String key in sortedKeys) key: sortedQuery[key]!,
    };
    final Uri uri =
        Uri.parse('$_baseUrl$path').replace(queryParameters: ordered);
    final http.Response response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) {
      throw const ApiAuthException('OpenSubtitles rejected the API key');
    }
    if (response.statusCode != 200) {
      throw NetworkException(
        'OpenSubtitles search failed (HTTP ${response.statusCode})',
      );
    }
    return jsonDecode(response.body);
  }

  /// Searches subtitles for a movie. Provide any of [tmdbId], [imdbId] or
  /// [movieHash] (OpenSubtitles hash of the video file) plus language codes.
  Future<List<SubtitleSearchResult>> search({
    List<String> languages = const <String>['en'],
    int? tmdbId,
    String? imdbId,
    String? movieHash,
    String? query,
  }) async {
    final Map<String, String> queryMap = <String, String>{
      'languages': languages.join(','),
      if (tmdbId != null) 'tmdb_id': '$tmdbId',
      if (imdbId != null) 'imdb_id': imdbId,
      if (movieHash != null && movieHash.isNotEmpty) 'moviehash': movieHash,
      if (query != null && query.isNotEmpty) 'query': query,
    };
    final dynamic data = await _get('/subtitles', queryMap);
    final List<dynamic> items =
        ((data as Map<String, dynamic>)['data'] as List<dynamic>?) ??
            const <dynamic>[];
    return items
        .map(_parseResult)
        .whereType<SubtitleSearchResult>()
        .toList(growable: false);
  }

  SubtitleSearchResult? _parseResult(dynamic entry) {
    final Map<String, dynamic> json = entry as Map<String, dynamic>;
    final Map<String, dynamic> attributes =
        (json['attributes'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> files =
        (attributes['files'] as List<dynamic>?) ?? const <dynamic>[];
    if (files.isEmpty) return null;
    final Map<String, dynamic> first = files.first as Map<String, dynamic>;
    return SubtitleSearchResult(
      fileId: (first['file_id'] as num?)?.toInt() ?? 0,
      language: (attributes['language'] as String?) ?? '',
      release: attributes['release'] as String?,
      fileName: (first['file_name'] as String?) ??
          (attributes['release'] as String?) ??
          'subtitle',
      format: attributes['format'] as String?,
      hd: attributes['hd'] as bool? ?? false,
      downloadCount: (attributes['download_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Downloads a subtitle to [saveDir]; handles the zip container some
  /// releases use and returns the extracted subtitle file path.
  Future<String> downloadSubtitle(
    SubtitleSearchResult result,
    String saveDir,
  ) async {
    await Directory(saveDir).create(recursive: true);

    final Uri downloadUri = Uri.parse('$_baseUrl/download');
    final http.Response linkResponse = await _client
        .post(
          downloadUri,
          headers: <String, String>{
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'file_id': result.fileId}),
        )
        .timeout(const Duration(seconds: 20));
    if (linkResponse.statusCode != 200) {
      throw NetworkException(
        'Subtitle download failed (HTTP ${linkResponse.statusCode})',
      );
    }
    final Map<String, dynamic> payload =
        jsonDecode(linkResponse.body) as Map<String, dynamic>;
    final String? link = payload['link'] as String?;
    lastRemainingQuota = (payload['remaining'] as num?)?.toInt();
    if (link == null || link.isEmpty) {
      throw const NetworkException('OpenSubtitles returned no download link '
          '(daily quota may be exhausted)');
    }

    final http.Response fileResponse =
        await _client.get(Uri.parse(link)).timeout(const Duration(seconds: 30));
    if (fileResponse.statusCode != 200) {
      throw NetworkException(
        'Subtitle file download failed (HTTP ${fileResponse.statusCode})',
      );
    }
    final List<int> bytes = fileResponse.bodyBytes;

    final String baseName =
        result.fileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    if (bytes.length > 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      // Zip container — extract the first subtitle-ish entry.
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      for (final ArchiveFile file in archive) {
        final String ext = file.name.split('.').last.toLowerCase();
        if (AppConstants.subtitleExtensions.contains(ext)) {
          final String outPath =
              '$saveDir/${result.language}_${baseName.replaceAll('.zip', '')}.$ext';
          await File(outPath)
              .writeAsBytes(file.content as List<int>, flush: true);
          return outPath;
        }
      }
      throw const AppException('Subtitle zip contained no subtitle files');
    }

    final String ext =
        (result.format ?? baseName.split('.').last).toLowerCase();
    final String outPath = '$saveDir/${result.language}_$baseName'
        '${baseName.toLowerCase().endsWith(ext) ? '' : '.$ext'}';
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }
}
