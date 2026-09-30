import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:popcorn_studio/core/constants.dart';
import 'package:popcorn_studio/data/apibay_provider.dart';

void main() {
  group('ApibayProvider', () {
    test('parses q.php results and builds magnets', () async {
      final http.Client client = MockClient(
        (http.Request request) async {
          expect(request.url.host, 'apibay.org');
          expect(request.url.path, '/q.php');
          expect(request.headers['User-Agent'], AppConstants.apibayUserAgent);
          return http.Response(
            jsonEncode(<dynamic>[
              <String, String>{
                'id': '11756968',
                'name': 'Interstellar (2014) 1080p BrRip x264 - YIFY',
                'info_hash': '89599BF4DC369A3A8ECA26411C5CCF922D78B486',
                'leechers': '163',
                'seeders': '965',
                'size': '2431905867',
                'num_files': '2',
                'username': 'YIFY',
                'added': '1426426450',
                'status': 'vip',
                'category': '207',
                'imdb': 'tt4288316',
              },
            ]),
            200,
          );
        },
      );
      final ApibayProvider provider = ApibayProvider(client: client);
      final List<dynamic> results = await provider.search('interstellar');

      expect(results, hasLength(1));
      final dynamic torrent = results.single;
      expect(torrent.infoHash, '89599BF4DC369A3A8ECA26411C5CCF922D78B486');
      expect(torrent.sizeBytes, 2431905867);
      expect(torrent.seeders, 965);
      expect(torrent.tpbNumericId, 11756968);
      expect(torrent.imdbId, 'tt4288316');
      expect(torrent.magnetUri!, startsWith('magnet:?xt=urn:btih:89599BF4'));
      expect(torrent.uploadedAt, isNotNull);
    });

    test('treats the "No results" sentinel as empty', () async {
      final http.Client client = MockClient(
        (http.Request request) async => http.Response('"No results"', 200),
      );
      final ApibayProvider provider = ApibayProvider(client: client);
      expect(await provider.search('qwjhqwe'), isEmpty);
    });

    test('skips malformed entries', () async {
      final http.Client client = MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<dynamic>[
            <String, String>{'name': 'broken', 'info_hash': 'short'},
          ]),
          200,
        ),
      );
      final ApibayProvider provider = ApibayProvider(client: client);
      expect(await provider.search('x'), isEmpty);
    });
  });
}
