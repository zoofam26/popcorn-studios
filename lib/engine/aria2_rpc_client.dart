import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors.dart';

/// Thin, typed JSON-RPC client for the aria2 daemon.
///
/// Every call posts to `http://127.0.0.1:<port>/jsonrpc` with the secret
/// token as the first parameter (`token:<secret>`), exactly as required by
/// the aria2 JSON-RPC interface.
class Aria2RpcClient {
  Aria2RpcClient({
    required this.port,
    required this.secret,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  final int port;
  final String secret;
  final HttpClient _client;
  final Duration timeout;

  int _idCounter = 0;

  Uri get _endpoint => Uri.parse('http://127.0.0.1:$port/jsonrpc');

  /// Performs a raw JSON-RPC call and returns the decoded `result`.
  Future<dynamic> call(String method,
      [List<dynamic> params = const <dynamic>[]]) async {
    final String id = 'pc-${_idCounter++}';
    final Map<String, dynamic> body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': <dynamic>['token:$secret', ...params],
    };

    final HttpClientRequest request = await _client.postUrl(_endpoint);
    request.headers.contentType = ContentType.json;
    // aria2's HTTP server rejects chunked request bodies — always send an
    // explicit content length.
    final List<int> payload = utf8.encode(jsonEncode(body));
    request.contentLength = payload.length;
    request.add(payload);
    final HttpClientResponse response = await request.close().timeout(timeout);

    if (response.statusCode != 200) {
      throw RpcException(
        'aria2 RPC HTTP ${response.statusCode} for $method',
        code: response.statusCode,
      );
    }

    final Map<String, dynamic> decoded =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;

    if (decoded.containsKey('error')) {
      final Map<String, dynamic> error =
          decoded['error'] as Map<String, dynamic>;
      throw RpcException(
        (error['message'] as String?) ?? 'Unknown aria2 error',
        code: (error['code'] as num?)?.toInt(),
      );
    }
    return decoded['result'];
  }

  // ── Typed convenience API ────────────────────────────────────────────────

  Future<String> getVersion() async {
    final dynamic result = await call('aria2.getVersion');
    return (result as Map<String, dynamic>)['version'] as String;
  }

  Future<String> getSessionInfo() async {
    final dynamic result = await call('aria2.getSessionInfo');
    return (result as Map<String, dynamic>)['sessionId'] as String;
  }

  Future<String> addUri(
    List<String> uris, {
    Map<String, String> options = const <String, String>{},
    String? position,
  }) async {
    final dynamic result = await call('aria2.addUri', <dynamic>[
      uris,
      options,
    ]);
    return result as String;
  }

  Future<String> addTorrent(
    List<int> torrentBytes, {
    Map<String, String> options = const <String, String>{},
  }) async {
    final dynamic result = await call('aria2.addTorrent', <dynamic>[
      base64Encode(torrentBytes),
      <String>[],
      options,
    ]);
    return result as String;
  }

  Future<Map<String, dynamic>> tellStatus(
    String gid, {
    List<String> keys = const <String>[
      'gid',
      'status',
      'totalLength',
      'completedLength',
      'downloadSpeed',
      'uploadSpeed',
      'connections',
      'infoHash',
      'numPieces',
      'pieceLength',
      'bittorrent',
      'files',
      'followedBy',
      'errorCode',
      'errorMessage',
    ],
  }) async {
    final dynamic result = await call('aria2.tellStatus', <dynamic>[gid, keys]);
    return result as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getFiles(String gid) async {
    final dynamic result = await call('aria2.getFiles', <dynamic>[gid]);
    return (result as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> tellActive({
    List<String> keys = const <String>['gid'],
  }) async {
    final dynamic result = await call('aria2.tellActive', <dynamic>[keys]);
    return (result as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> tellWaiting({
    List<String> keys = const <String>['gid'],
    int offset = 0,
    int num = 100,
  }) async {
    final dynamic result =
        await call('aria2.tellWaiting', <dynamic>[offset, num, keys]);
    return (result as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> tellStopped({
    List<String> keys = const <String>['gid'],
    int offset = 0,
    int num = 100,
  }) async {
    final dynamic result =
        await call('aria2.tellStopped', <dynamic>[offset, num, keys]);
    return (result as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getGlobalStat() async {
    final dynamic result = await call('aria2.getGlobalStat');
    return result as Map<String, dynamic>;
  }

  Future<void> pause(String gid) async {
    await call('aria2.pause', <dynamic>[gid]);
  }

  Future<void> forcePause(String gid) async {
    await call('aria2.forcePause', <dynamic>[gid]);
  }

  Future<void> unpause(String gid) async {
    await call('aria2.unpause', <dynamic>[gid]);
  }

  Future<void> remove(String gid) async {
    try {
      await call('aria2.remove', <dynamic>[gid]);
    } on RpcException catch (e) {
      // "GID ... cannot be removed" / "is not found" are non-fatal cleanup
      if (!e.message.contains('is not found')) rethrow;
    }
  }

  Future<void> forceRemove(String gid) async {
    try {
      await call('aria2.forceRemove', <dynamic>[gid]);
    } on RpcException catch (e) {
      if (!e.message.contains('is not found')) rethrow;
    }
  }

  Future<void> changeGlobalOption(Map<String, String> options) async {
    await call('aria2.changeGlobalOption', <dynamic>[options]);
  }

  Future<void> saveSession() async {
    await call('aria2.saveSession');
  }

  void close() {
    _client.close(force: true);
  }
}
