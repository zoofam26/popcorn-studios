import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/engine/bencode.dart';

void main() {
  group('Bencode encode', () {
    test('encodes integers', () {
      expect(Bencode.encode(42), 'i42e'.codeUnits);
      expect(Bencode.encode(-7), 'i-7e'.codeUnits);
    });

    test('encodes strings', () {
      expect(Bencode.encode('spam'), '4:spam'.codeUnits);
    });

    test('encodes lists', () {
      expect(Bencode.encode(<Object>['a', 1]), 'l1:ai1ee'.codeUnits);
    });

    test('encodes dicts with byte-sorted keys', () {
      final String encoded = String.fromCharCodes(
        Bencode.encode(<String, dynamic>{'b': 2, 'a': 1}),
      );
      expect(encoded, 'd1:ai1e1:bi2ee');
    });

    test('encodes raw byte payloads', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final String encoded = String.fromCharCodes(Bencode.encode(bytes));
      expect(encoded, '3:\x01\x02\x03');
    });
  });

  group('Bencode decode', () {
    test('round-trips complex metadata-like structures', () {
      final Map<String, dynamic> torrent = <String, dynamic>{
        'announce': 'http://tracker/announce',
        'info': <String, dynamic>{
          'name': 'Sintel.mp4',
          'length': 129301094,
          'piece length': 262144,
          // 0xFF bytes are invalid UTF-8, forcing raw binary preservation.
          'pieces': Uint8List.fromList(List<int>.filled(20, 0xFF)),
        },
      };
      final List<int> encoded = Bencode.encode(torrent);
      final Object? decoded = Bencode.decodeValue(encoded);
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> map = decoded! as Map<String, dynamic>;
      final Map<String, dynamic> info = map['info']! as Map<String, dynamic>;
      expect(info['name'], 'Sintel.mp4');
      expect(info['length'], 129301094);
      expect(info['pieces'], isA<Uint8List>());
      expect((info['pieces']! as Uint8List).length, 20);
    });

    test('rejects malformed input', () {
      expect(() => Bencode.decodeValue('i12'.codeUnits),
          throwsA(isA<BencodeException>()));
      expect(() => Bencode.decodeValue('zz'.codeUnits),
          throwsA(isA<BencodeException>()));
    });
  });
}
