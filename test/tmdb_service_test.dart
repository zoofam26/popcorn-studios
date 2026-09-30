import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:popcorn_studio/core/constants.dart';
import 'package:popcorn_studio/data/tmdb_service.dart';

void main() {
  group('TmdbService', () {
    test('sends bearer auth and maps trending results', () async {
      String? authHeader;
      final http.Client client = MockClient(
        (http.Request request) async {
          authHeader = request.headers['Authorization'];
          return http.Response(
            jsonEncode(<String, dynamic>{
              'results': <dynamic>[
                <String, dynamic>{
                  'id': 157336,
                  'title': 'Interstellar',
                  'overview': 'Space farm.',
                  'poster_path': '/poster.jpg',
                  'backdrop_path': '/backdrop.jpg',
                  'release_date': '2014-11-05',
                  'vote_average': 8.4,
                  'genre_ids': <int>[12, 878],
                },
              ],
            }),
            200,
          );
        },
      );

      final TmdbService service = TmdbService(client: client);
      final List<dynamic> movies = await service.trending();

      expect(authHeader, 'Bearer ${AppConstants.tmdbBearerToken}');
      expect(movies, hasLength(1));
      final dynamic movie = movies.single;
      expect(movie.id, 157336);
      expect(movie.title, 'Interstellar');
      expect(movie.releaseYear, 2014);
      expect(movie.posterUrl, '${AppConstants.tmdbImageBase}/w500/poster.jpg');
      expect(movie.backdropUrl,
          '${AppConstants.tmdbImageBase}/w1280/backdrop.jpg');
    });

    test('maps movie detail with appended responses', () async {
      final http.Client client = MockClient(
        (http.Request request) async {
          expect(request.url.path, '/3/movie/157336');
          expect(
            request.url.queryParameters['append_to_response'],
            'credits,videos,similar,external_ids',
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'id': 157336,
              'title': 'Interstellar',
              'runtime': 169,
              'tagline': 'Mankind was born on Earth.',
              'genres': <dynamic>[
                <String, dynamic>{'id': 12, 'name': 'Adventure'},
              ],
              'external_ids': <String, dynamic>{'imdb_id': 'tt0816692'},
              'credits': <String, dynamic>{
                'cast': <dynamic>[
                  <String, dynamic>{
                    'id': 1,
                    'name': 'Matthew McConaughey',
                    'character': 'Cooper',
                    'profile_path': '/cooper.jpg',
                  },
                ],
              },
              'videos': <String, dynamic>{
                'results': <dynamic>[
                  <String, dynamic>{
                    'key': 'zSWdZVtXT7E',
                    'site': 'YouTube',
                    'type': 'Trailer',
                    'name': 'Trailer',
                  },
                ],
              },
              'similar': <String, dynamic>{
                'results': <dynamic>[
                  <String, dynamic>{'id': 2, 'title': 'Dunkirk'},
                ],
              },
            }),
            200,
          );
        },
      );

      final TmdbService service = TmdbService(client: client);
      final dynamic detail = await service.movieDetail(157336);

      expect(detail.runtime, 169);
      expect(detail.imdbId, 'tt0816692');
      expect(detail.trailer!.key, 'zSWdZVtXT7E');
      expect(detail.cast.single.name, 'Matthew McConaughey');
      expect(detail.similar.single.title, 'Dunkirk');
    });

    test('throws ApiAuthException on 401', () async {
      final http.Client client = MockClient(
        (http.Request request) async => http.Response('unauthorized', 401),
      );
      final TmdbService service = TmdbService(client: client);
      await expectLater(
        service.trending(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
