import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:popcorn_studio/data/yts_provider.dart';

void main() {
  group('YtsProvider', () {
    test('parses movies + torrents and fails over mirrors', () async {
      int requestsSeen = 0;
      final http.Client client = MockClient(
        (http.Request request) async {
          requestsSeen++;
          if (request.url.host == 'yts.mx') {
            // First mirror fails — the provider must try the next.
            return http.Response('blocked', 403);
          }
          expect(request.url.path, '/api/v2/list_movies.json');
          expect(request.url.queryParameters['query_term'], 'interstellar');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'data': <String, dynamic>{
                'movies': <dynamic>[
                  <String, dynamic>{
                    'id': 42,
                    'title': 'Interstellar',
                    'title_long': 'Interstellar (2014)',
                    'year': 2014,
                    'imdb_code': 'tt0816692',
                    'torrents': <dynamic>[
                      <String, dynamic>{
                        'hash': '89599bf4dc369a3a8eca26411c5ccf922d78b486',
                        'url': 'https://yts.gg/torrent/download/HASH',
                        'quality': '1080p',
                        'type': 'bluray',
                        'seeds': 100,
                        'peers': 40,
                        'size': '2.26 GB',
                        'size_bytes': 2426656522,
                        'date_uploaded_unix': 1446333487,
                      },
                      <String, dynamic>{
                        'hash': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                        'quality': '720p',
                        'seeds': 250,
                        'peers': 10,
                        'size_bytes': 900000000,
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        },
      );

      final YtsProvider provider = YtsProvider(
        client: client,
        baseUrls: <String>['https://yts.mx', 'https://yts.am'],
      );
      final List<dynamic> results =
          await provider.search(queryTerm: 'interstellar');

      expect(requestsSeen, greaterThanOrEqualTo(2));
      expect(results, hasLength(2));
      final dynamic first = results[0];
      expect(first.infoHash, '89599BF4DC369A3A8ECA26411C5CCF922D78B486');
      expect(first.quality, '1080p');
      expect(first.sizeBytes, 2426656522);
      expect(first.imdbId, 'tt0816692');
      expect(first.torrentUrl, 'https://yts.gg/torrent/download/HASH');
      expect(first.uploadedAt, isNotNull);
    });

    test('throws a NetworkException when every mirror fails', () async {
      final http.Client client = MockClient(
        (http.Request request) async => http.Response('nope', 500),
      );
      final YtsProvider provider = YtsProvider(
        client: client,
        baseUrls: const <String>['https://a.invalid', 'https://b.invalid'],
      );
      await expectLater(
        provider.search(queryTerm: 'x'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
