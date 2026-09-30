/// Minimal bencode encoder/decoder used by the engine layer (test torrent
/// construction, metadata inspection) — pure Dart, no dependencies.
///
/// Dart type mapping:
///   int                  → bencode integer  `i42e`
///   String               → bencode string   `4:spam` (utf-8)
///   List                 → `l...e`
///   `Map<String, dynamic>` → `d...e` (keys sorted byte-wise, as required)
///   Uint8List            → raw length-prefixed bytes
library;

import 'dart:convert';
import 'dart:typed_data';

class BencodeException implements Exception {
  BencodeException(this.message);
  final String message;

  @override
  String toString() => 'BencodeException: $message';
}

abstract final class Bencode {
  /// Encodes [value] into bencode bytes.
  static List<int> encode(Object? value) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    _encodeInto(value, builder);
    return builder.takeBytes();
  }

  /// Decodes one top-level item from [data] starting at [offset].
  static ({Object? value, int bytesRead}) decode(
    List<int> data, {
    int offset = 0,
  }) {
    final _Decoder decoder = _Decoder(data, offset);
    final Object? value = decoder.readValue();
    return (value: value, bytesRead: decoder.pos - offset);
  }

  /// Decodes and returns just the value.
  static Object? decodeValue(List<int> data) => decode(data).value;

  static void _encodeInto(Object? value, BytesBuilder out) {
    switch (value) {
      case final int v:
        out.add(_ascii('i${v}e'));
      case final Uint8List v:
        out.add(_ascii('${v.length}:'));
        out.add(v);
      case final String v:
        final List<int> bytes = _utf8(v);
        out.add(_ascii('${bytes.length}:'));
        out.add(bytes);
      case final List<dynamic> v:
        out.add(_ascii('l'));
        for (final Object? item in v) {
          _encodeInto(item, out);
        }
        out.add(_ascii('e'));
      case final Map<dynamic, dynamic> v:
        final List<MapEntry<Object?, Object?>> entries = v.entries.toList()
          ..sort((MapEntry<Object?, Object?> a, MapEntry<Object?, Object?> b) =>
              _compareBytes(_utf8('${a.key}'), _utf8('${b.key}')));
        out.add(_ascii('d'));
        for (final MapEntry<Object?, Object?> entry in entries) {
          _encodeInto('${entry.key}', out);
          _encodeInto(entry.value, out);
        }
        out.add(_ascii('e'));
      default:
        throw BencodeException('Unsupported type: ${value.runtimeType}');
    }
  }

  static int _compareBytes(List<int> a, List<int> b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  static List<int> _ascii(String s) => s.codeUnits;
}

final Utf8Encoder _utf8Encoder = Utf8Encoder();
List<int> _utf8(String s) => _utf8Encoder.convert(s);

class _Decoder {
  _Decoder(this.data, this.pos);

  final List<int> data;
  int pos;

  Object? readValue() {
    if (pos >= data.length) {
      throw BencodeException('Unexpected end of data');
    }
    final int c = data[pos];
    switch (c) {
      case 0x69: // 'i'
        return _readInt();
      case 0x6C: // 'l'
        return _readList();
      case 0x64: // 'd'
        return _readDict();
      default:
        if (c >= 0x30 && c <= 0x39) return _readString();
        throw BencodeException('Invalid bencode token at $pos: $c');
    }
  }

  int _readInt() {
    pos++; // skip 'i'
    final int start = pos;
    while (pos < data.length && data[pos] != 0x65) {
      pos++;
    }
    if (pos >= data.length) throw BencodeException('Unterminated integer');
    final int value = int.tryParse(_asciiSlice(start, pos)) ??
        (throw BencodeException('Bad integer'));
    pos++; // skip 'e'
    return value;
  }

  List<dynamic> _readList() {
    pos++; // skip 'l'
    final List<dynamic> list = <dynamic>[];
    while (pos < data.length && data[pos] != 0x65) {
      list.add(readValue());
    }
    if (pos >= data.length) throw BencodeException('Unterminated list');
    pos++; // skip 'e'
    return list;
  }

  Map<String, dynamic> _readDict() {
    pos++; // skip 'd'
    final Map<String, dynamic> map = <String, dynamic>{};
    while (pos < data.length && data[pos] != 0x65) {
      final Object? key = _readString();
      final Object? value = readValue();
      map[key is String ? key : '$key'] = value;
    }
    if (pos >= data.length) throw BencodeException('Unterminated dict');
    pos++; // skip 'e'
    return map;
  }

  /// Strings decode as String when valid UTF-8, else stay raw Uint8List
  /// (binary fields such as the `pieces` hash list are preserved).
  Object _readString() {
    final int colon = data.indexOf(0x3A, pos); // ':'
    if (colon < 0) throw BencodeException('Missing colon in string');
    final int length = int.tryParse(_asciiSlice(pos, colon)) ??
        (throw BencodeException('Bad string length'));
    pos = colon + 1;
    final int end = pos + length;
    if (end > data.length) throw BencodeException('String overruns buffer');
    final Uint8List slice = Uint8List.fromList(data.sublist(pos, end));
    pos = end;
    try {
      return utf8.decode(slice, allowMalformed: false);
    } on FormatException {
      return slice;
    }
  }

  String _asciiSlice(int start, int end) =>
      String.fromCharCodes(data.sublist(start, end));
}
