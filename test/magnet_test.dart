import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/data/magnet_builder.dart';

void main() {
  group('buildMagnetUri', () {
    test('uppercases hash and appends default trackers', () {
      final String magnet = buildMagnetUri(
        infoHash: '0123456789abcdef0123456789abcdef01234567',
        displayName: 'Sintel (2010)',
      );
      expect(
        magnet,
        startsWith(
          'magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567',
        ),
      );
      expect(magnet, contains('dn=Sintel%20(2010)'));
      expect(
        magnet,
        contains(
            'tr=${Uri.encodeComponent('udp://tracker.opentrackr.org:1337/announce')}'),
      );
    });

    test('merges extra trackers without duplicates', () {
      final String magnet = buildMagnetUri(
        infoHash: 'a' * 40,
        extraTrackers: <String>['udp://extra.example:1337/announce'],
      );
      final String encoded =
          Uri.encodeComponent('udp://extra.example:1337/announce');
      expect(magnet.contains(encoded), isTrue);
      expect(encoded.allMatches(magnet).length, 1);
    });
  });

  group('extractInfoHash', () {
    test('extracts from magnet with hex hash', () {
      final String? hash = extractInfoHash(
        'magnet:?xt=urn:btih:89599bf4dc369a3a8eca26411c5ccf922d78b486&dn=x',
      );
      expect(hash, '89599BF4DC369A3A8ECA26411C5CCF922D78B486');
    });

    test('accepts bare hash', () {
      expect(extractInfoHash('A' * 40), 'A' * 40);
    });

    test('decodes base32 hashes', () {
      // A 31-char string is not a valid base32 v1 hash.
      expect(extractInfoHash('magnet:?xt=urn:btih:AAAAAAAAAAAAAAA'), isNull);
      final String? valid = extractInfoHash(
        'magnet:?xt=urn:btih:GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      );
      // 32 base32 chars = 20 bytes = 40 hex chars.
      expect(valid, isNotNull);
      expect(valid!.length, 40);
    });
  });
}
