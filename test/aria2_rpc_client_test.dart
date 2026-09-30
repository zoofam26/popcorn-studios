import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/core/errors.dart';
import 'package:popcorn_studio/engine/aria2_rpc_client.dart';

void main() {
  late HttpServer server;
  late Aria2RpcClient client;
  final List<Map<String, dynamic>> receivedBodies = <Map<String, dynamic>>[];
  Object? Function(Map<String, dynamic> request) handler =
      (Map<String, dynamic> request) => <String, dynamic>{};

  setUp(() async {
    receivedBodies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final String raw = await utf8.decoder.bind(request).join();
      receivedBodies.add(jsonDecode(raw) as Map<String, dynamic>);
      final Object? result = handler(receivedBodies.last);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, dynamic>{
        'id': receivedBodies.last['id'],
        'jsonrpc': '2.0',
        'result': result,
      }));
      await request.response.close();
    });
    client = Aria2RpcClient(port: server.port, secret: 'testsecret');
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('sends token:secret as first param and returns typed results', () async {
    handler = (Map<String, dynamic> request) =>
        <String, dynamic>{'version': '1.37.0'};

    final String version = await client.getVersion();

    expect(version, '1.37.0');
    expect(receivedBodies.single['method'], 'aria2.getVersion');
    final List<dynamic> params =
        receivedBodies.single['params'] as List<dynamic>;
    expect(params.first, 'token:testsecret');
  });

  test('addUri forwards options map', () async {
    handler = (Map<String, dynamic> request) => 'gid-123';
    final String gid = await client.addUri(
      <String>['magnet:?xt=urn:btih:abc'],
      options: <String, String>{'dir': '/tmp/x', 'seed-ratio': '0'},
    );

    expect(gid, 'gid-123');
    final List<dynamic> params =
        receivedBodies.single['params'] as List<dynamic>;
    expect(params[1], <String>['magnet:?xt=urn:btih:abc']);
    expect(params[2], <String, String>{'dir': '/tmp/x', 'seed-ratio': '0'});
  });

  test('maps RPC errors to RpcException', () async {
    final HttpServer failingServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    failingServer.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, dynamic>{
        'id': '1',
        'jsonrpc': '2.0',
        'error': <String, dynamic>{'code': 1, 'message': 'Unauthorized'},
      }));
      await request.response.close();
    });

    final Aria2RpcClient badClient =
        Aria2RpcClient(port: failingServer.port, secret: 'wrong');
    try {
      await badClient.getVersion();
      fail('expected RpcException');
    } on RpcException catch (e) {
      expect(e.message, 'Unauthorized');
      expect(e.code, 1);
    } finally {
      badClient.close();
      await failingServer.close(force: true);
    }
  });

  test('tellStatus requests the keys we need', () async {
    handler = (Map<String, dynamic> request) => <String, dynamic>{
          'gid': 'g1',
          'status': 'active',
          'files': <dynamic>[],
        };

    await client.tellStatus('g1');

    final List<dynamic> params =
        receivedBodies.single['params'] as List<dynamic>;
    expect(params[0], 'token:testsecret'); // secret is always first
    expect(params[1], 'g1');
    final List<dynamic> keys = params[2] as List<dynamic>;
    expect(keys, containsAll(<String>['files', 'infoHash', 'bittorrent']));
  });
}
