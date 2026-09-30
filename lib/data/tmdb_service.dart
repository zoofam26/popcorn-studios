import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/errors.dart';
import '../domain/models.dart';

/// TMDB REST client (v3 API, bearer-token auth).
class TmdbService {
  TmdbService({
    http.Client? client,
    String? baseUrl,
    String? bearerToken,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConstants.tmdbBaseUrl,
        _bearer = bearerToken ?? AppConstants.tmdbBearerToken;

  final http.Client _client;
  final String _baseUrl;
  final String _bearer;

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $_bearer',
        'accept': 'application/json',
      };

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: <String, String>{...?query, 'language': 'en-US'},
    );
    final http.Response response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) {
      throw const ApiAuthException('TMDB rejected the API credentials');
    }
    if (response.statusCode != 200) {
      throw NetworkException(
          'TMDB request failed (HTTP ${response.statusCode})');
    }
    return jsonDecode(response.body);
  }

  Future<List<Movie>> _movieList(String path,
      [Map<String, String>? query]) async {
    final dynamic data = await _get(path, query);
    final List<dynamic> results =
        ((data as Map<String, dynamic>)['results'] as List<dynamic>?) ??
            const <dynamic>[];
    return results
        .map((dynamic e) => Movie.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Movie>> trending({String window = 'day'}) =>
      _movieList('/trending/movie/$window');

  Future<List<Movie>> popular({int page = 1}) =>
      _movieList('/movie/popular', <String, String>{'page': '$page'});

  Future<List<Movie>> topRated({int page = 1}) =>
      _movieList('/movie/top_rated', <String, String>{'page': '$page'});

  Future<List<Movie>> nowPlaying({int page = 1}) =>
      _movieList('/movie/now_playing', <String, String>{'page': '$page'});

  Future<List<Movie>> search(String query, {int page = 1}) =>
      query.trim().isEmpty
          ? Future<List<Movie>>.value(<Movie>[])
          : _movieList(
              '/search/movie',
              <String, String>{'query': query.trim(), 'page': '$page'},
            );

  Future<MovieDetail> movieDetail(int id) async {
    final dynamic data = await _get(
      '/movie/$id',
      <String, String>{
        'append_to_response': 'credits,videos,similar,external_ids'
      },
    );
    return MovieDetail.fromJson(data as Map<String, dynamic>);
  }
}
