import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:popcorn_studio/data/stremio_streams_provider.dart';
import 'package:popcorn_studio/domain/models.dart';

void main() {
  group('StremioStreamProvider (Torrentio)', () {
    test('parses streams with hash, file index, seeds, size and quality',
        () async {
      const String payload = '''
{
  "streams": [
    {
      "title": "Interstellar.2014.1080p.BluRay.x264-YIFY\\n👤 950 💾 2.1 GB ⚙️ 1337x",
      "name": "Torrentio\\n1080p",
      "infoHash": "89599bf4dc369a3a8eca26411c5ccf922d78b486",
      "fileIdx": 2,
      "behaviorHints": {"bingeGroup": "torrentio|1080p", "filename": "Interstellar.2014.1080p.BluRay.x264-YIFY.mkv"}
    },
    {
      "title": "Interstellar 2014 2160p REMUX\\n👤 271 💾 95.63 GB ⚙️ RARBG",
      "name": "Torrentio\\n4k DV | HDR10+",
      "infoHash": "D8D05EBEC7303F05A7243986E8C7D0E201B0AC0D",
      "fileIdx": 0
    },
    {
      "title": "broken entry without hash\\n👤 10 💾 1 GB",
      "name": "Torrentio\\n720p"
    }
  ]
}
''';
      final StremioStreamProvider provider = StremioStreamProvider(
        client: MockClient((http.Request request) async {
          expect(request.url.toString(),
              'https://torrentio.strem.fun/stream/movie/tt0816692.json');
          expect(request.headers['User-Agent'], contains('Mozilla'));
          return http.Response.bytes(utf8.encode(payload), 200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8'
              });
        }),
      );

      final List<TorrentInfo> streams =
          await provider.streamsForImdb('tt0816692');

      expect(streams, hasLength(2));

      final TorrentInfo first = streams[0];
      expect(first.infoHash, '89599BF4DC369A3A8ECA26411C5CCF922D78B486');
      expect(first.fileIdx, 2);
      expect(first.seeders, 950);
      expect(first.videoFileName, 'Interstellar.2014.1080p.BluRay.x264-YIFY.mkv');
      expect(first.source, TorrentSource.torrentio);
      expect(first.sizeBytes, inExclusiveRange(2 * 1000 * 1000 * 1000, 2500000000));
      expect(first.magnetUri, contains(first.infoHash));

      final TorrentInfo remux = streams[1];
      expect(remux.quality, '2160p');
      expect(remux.seeders, 271);
      expect(remux.sizeBytes, inExclusiveRange(95 * 1000 * 1000 * 1000, 96 * 1000 * 1000 * 1000));
      expect(remux.fileIdx, 0);
    });

    test('falls back across mirrors and tolerates total failure', () async {
      int calls = 0;
      final StremioStreamProvider provider = StremioStreamProvider(
        baseUrls: const <String>[
          'https://mirror-a.invalid',
          'https://mirror-b.invalid',
        ],
        client: MockClient((http.Request request) async {
          calls++;
          if (calls == 1) {
            return http.Response('server error', 500);
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'streams': <dynamic>[
                  <String, dynamic>{
                    'title': 'Some.Movie.2020.1080p.WEBRip\\n👤 55 💾 1.5 GB',
                    'name': 'Torrentio\\n1080p',
                    'infoHash': 'a' * 40,
                  },
                ],
              }),
            ),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8'
            },
          );
        }),
      );

      final List<TorrentInfo> streams = await provider.streamsForImdb('tt123');
      expect(streams, hasLength(1));
      expect(streams.single.quality, '1080p');

      final List<TorrentInfo> none = await StremioStreamProvider(
        client: MockClient((http.Request request) async {
          throw Exception('offline');
        }),
      ).streamsForImdb('tt123');
      expect(none, isEmpty);
    });
  });
}
