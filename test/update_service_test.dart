import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/data/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('compareVersions', () {
    test('newer releases compare greater', () {
      expect(compareVersions('1.3.0', '1.2.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.2.10', '1.2.9'), greaterThan(0));
      expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
    });

    test('older releases compare smaller', () {
      expect(compareVersions('1.1.0', '1.2.0'), lessThan(0));
      expect(compareVersions('1.2', '1.2.1'), lessThan(0));
      expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
    });

    test('equal versions compare zero (leading v tolerated)', () {
      expect(compareVersions('1.2.0', '1.2.0'), 0);
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('V1.2.0', 'v1.2.0'), 0);
    });

    test('junk falls back to zero parts without throwing', () {
      expect(compareVersions('', '1.0.0'), lessThan(0));
      expect(compareVersions('abc', 'abc'), 0);
    });
  });

  group('UpdateService gate decisions', () {
    late HttpServer server;
    late String Function() tagForRequest;
    late int Function() statusCodeForRequest;

    setUp(() async {
      tagForRequest = () => 'v1.2.0';
      statusCodeForRequest = () => 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        final String body = jsonEncode(<String, dynamic>{
          'tag_name': tagForRequest(),
          'html_url':
              'https://github.com/zoofam26/popcorn-studios/releases/tag/${tagForRequest()}',
        });
        request.response.statusCode = statusCodeForRequest();
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    UpdateService service({required String current}) {
      return UpdateService(
        latestReleaseUri:
            Uri.parse('http://127.0.0.1:${server.port}/releases/latest'),
        currentVersionOverride: current,
      );
    }

    test('older installed build is BLOCKED when a newer release exists',
        () async {
      tagForRequest = () => 'v1.3.0';
      final UpdateStatus status = await service(current: '1.2.0').evaluate();
      expect(status.updateRequired, isTrue);
      expect(status.latestVersion, '1.3.0');
      expect(status.releaseUrl, contains('releases/tag/v1.3.0'));
      expect(status.fromCache, isFalse);
      expect(status.checkFailed, isFalse);
    });

    test('current build is allowed when the release matches', () async {
      tagForRequest = () => 'v1.2.0';
      final UpdateStatus status = await service(current: '1.2.0').evaluate();
      expect(status.updateRequired, isFalse);
      expect(status.latestVersion, '1.2.0');
    });

    test('newer installed build is allowed', () async {
      tagForRequest = () => 'v1.1.9';
      final UpdateStatus status = await service(current: '1.2.0').evaluate();
      expect(status.updateRequired, isFalse);
    });

    test('numeric segments compare numerically (1.2.10 > 1.2.9)', () async {
      tagForRequest = () => 'v1.2.10';
      final UpdateStatus status = await service(current: '1.2.9').evaluate();
      expect(status.updateRequired, isTrue);
    });

    test('failing check with no cache fails OPEN', () async {
      statusCodeForRequest = () => 503;
      final UpdateStatus status = await service(current: '1.2.0').evaluate();
      expect(status.updateRequired, isFalse);
      expect(status.checkFailed, isTrue);
      expect(status.known, isFalse);
    });

    test('decision is cached and reused while offline (48 h window)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tagForRequest = () => 'v2.0.0';
      final UpdateStatus live = await service(current: '1.2.0').evaluate();
      expect(live.updateRequired, isTrue);

      // The update service now errors out — the recent cached decision
      // still blocks the old build.
      statusCodeForRequest = () => 503;
      final UpdateStatus cached = await service(current: '1.2.0').evaluate();
      expect(cached.updateRequired, isTrue);
      expect(cached.fromCache, isTrue);
      expect(cached.latestVersion, '2.0.0');
    });

    test('stale cache (older than TTL) is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update.cache.latestTag': '9.9.9',
        'update.cache.releaseUrl': 'https://example.com',
        'update.cache.checkedAtMs':
            DateTime.now().millisecondsSinceEpoch - 72 * 3600 * 1000,
      });
      statusCodeForRequest = () => 503;
      final UpdateStatus status = await service(current: '1.2.0').evaluate();
      expect(status.updateRequired, isFalse);
      expect(status.fromCache, isFalse);
    });

    test('manual checkNow reports failures instead of failing open silently',
        () async {
      statusCodeForRequest = () => 503;
      final UpdateStatus status = await service(current: '1.2.0').checkNow();
      expect(status.checkFailed, isTrue);
      expect(status.updateRequired, isFalse);
    });
  });
}
