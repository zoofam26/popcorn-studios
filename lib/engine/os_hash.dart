import 'dart:io';
import 'dart:typed_data';

/// OpenSubtitles movie-hash implementation (64-bit hash of file size plus
/// the first and last 64 KiB).
///
/// Used to search subtitles for videos without a TMDB id (direct magnet
/// playback) and matches what tools like `oshash` produce.
class OpenSubtitlesHash {
  OpenSubtitlesHash._();

  static const int _chunkSize = 65536; // 64 KiB

  /// Returns the 16-hex-character movie hash for [file].
  static Future<String> compute(String filePath) async {
    final RandomAccessFile raf = await File(filePath).open();
    try {
      final int length = await raf.length();
      Uint8List head = Uint8List(0);
      Uint8List tail = Uint8List(0);
      if (length <= _chunkSize * 2) {
        // Small file: hash the whole content twice? Reference impls hash
        // available bytes; Pad with zeros to two chunks.
        final Uint8List all = await _readAt(raf, 0, length);
        final Uint8List padded = Uint8List(_chunkSize * 2)
          ..setRange(0, length, all);
        head = padded.sublist(0, _chunkSize);
        tail = padded.sublist(_chunkSize);
      } else {
        head = await _readAt(raf, 0, _chunkSize);
        tail = await _readAt(raf, length - _chunkSize, _chunkSize);
      }

      int hash = length;
      hash = _sumChunk(hash, head);
      hash = _sumChunk(hash, tail);

      final BigInt big = BigInt.from(hash).toUnsigned(64);
      return big.toRadixString(16).padLeft(16, '0');
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile raf,
    int offset,
    int length,
  ) async {
    await raf.setPosition(offset);
    return await raf.read(length);
  }

  static int _sumChunk(int seed, Uint8List bytes) {
    int hash = seed;
    for (int i = 0; i < bytes.length; i += 8) {
      int value = 0;
      // Little-endian u64 read.
      for (int b = 7; b >= 0; b--) {
        value = (value << 8) | bytes[i + b];
      }
      hash = (hash + value) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }
}
