import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:popcorn_studio/data/opensubtitles_service.dart';
import 'package:popcorn_studio/domain/models.dart';

void main() {
  group('OpenSubtitlesService', () {
    test('searches with sorted query params and parses results', () async {
      final List<Uri> seen = <Uri>[];
      final http.Client client = MockClient(
        (http.Request request) async {
          seen.add(request.url);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <dynamic>[
                <String, dynamic>{
                  'id': 's1',
                  'attributes': <String, dynamic>{
                    'language': 'en',
                    'release': 'Interstellar.2014.1080p.BluRay',
                    'format': 'srt',
                    'hd': true,
                    'download_count': 4200,
                    'files': <dynamic>[
                      <String, dynamic>{
                        'file_id': 12538153,
                        'file_name': 'Interstellar.2014.1080p.BluRay.srt',
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        },
      );

      final OpenSubtitlesService service = OpenSubtitlesService(client: client);
      final List<SubtitleSearchResult> results = await service.search(
        languages: const <String>['en'],
        tmdbId: 157336,
      );

      // Params must be sent alphabetically (the API 301s otherwise).
      final List<String> keys = seen.single.queryParameters.keys.toList();
      final List<String> sortedKeys = List<String>.of(keys)..sort();
      expect(keys, sortedKeys);
      expect(keys.first, 'languages');

      expect(results, hasLength(1));
      expect(results.single.fileId, 12538153);
      expect(results.single.language, 'en');
      expect(results.single.hd, isTrue);
    });

    test('downloads via POST /download and saves the file', () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('popcorn_subs_test');
      addTearDown(() => temp.delete(recursive: true));

      final http.Client client = MockClient(
        (http.Request request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/download') {
            final Map<String, dynamic> body =
                jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['file_id'], 12538153);
            return http.Response(
              jsonEncode(<String, dynamic>{
                'link': 'https://dl.example/sub.srt',
                'file_name': 'sub.srt',
                'remaining': 99,
              }),
              200,
            );
          }
          if (request.url.toString() == 'https://dl.example/sub.srt') {
            return http.Response.bytes(
              utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nHello\n'),
              200,
            );
          }
          return http.Response('unexpected', 404);
        },
      );

      final OpenSubtitlesService service = OpenSubtitlesService(client: client);
      final String path = await service.downloadSubtitle(
        const SubtitleSearchResult(
          fileId: 12538153,
          language: 'en',
          fileName: 'sub.srt',
          format: 'srt',
        ),
        temp.path,
      );

      expect(service.lastRemainingQuota, 99);
      final File file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('Hello'));
    });

    test('extracts srt files from a zip container', () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('popcorn_subs_zip_test');
      addTearDown(() => temp.delete(recursive: true));

      // Build a real zip containing one .srt using package:archive.
      final Archive archive = Archive()
        ..addFile(
          ArchiveFile.bytes('inner.srt', utf8.encode('1\n00:00:01\nZip\n')),
        );
      final List<int> zipBytes = ZipEncoder().encode(archive);

      final http.Client client = MockClient(
        (http.Request request) async {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'link': 'https://dl.example/sub.zip',
                'remaining': 98,
              }),
              200,
            );
          }
          return http.Response.bytes(zipBytes, 200);
        },
      );

      final OpenSubtitlesService service = OpenSubtitlesService(client: client);
      final String path = await service.downloadSubtitle(
        const SubtitleSearchResult(
          fileId: 1,
          language: 'en',
          fileName: 'sub.zip',
        ),
        temp.path,
      );

      expect(path.endsWith('.srt'), isTrue);
      expect(await File(path).readAsString(), contains('Zip'));
    });
  });
}
