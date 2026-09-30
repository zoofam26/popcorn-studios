import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/engine/stream_server.dart';

/// Controllable fake of the engine's file status used to simulate a file
/// that grows while a download is in progress.
class FakeStatusProvider {
  int completed = 0;
  int calls = 0;

  Future<StreamFileStatus?> call(String gid, int fileIndex) async {
    calls++;
    return StreamFileStatus(
      filePath: filePath,
      totalLength: total,
      completedLength: completed,
    );
  }

  late String filePath;
  late int total;
}

void main() {
  late Directory tempDir;
  late FakeStatusProvider status;
  late StreamServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('popcorn_stream_test');
    status = FakeStatusProvider();
    server = StreamServer(
      statusProvider: status.call,
      pollInterval: const Duration(milliseconds: 20),
      startBufferBytes: 8,
      startBufferTimeout: const Duration(milliseconds: 500),
      stallTimeout: const Duration(milliseconds: 800),
      chunkSize: 64,
    );
  });

  tearDown(() async {
    await server.dispose();
    await tempDir.delete(recursive: true);
  });

  Future<File> writeFile(String name, int size) async {
    final File file = File('${tempDir.path}/$name');
    final RandomAccessFile raf = await file.open(mode: FileMode.write);
    final Uint8List chunk = Uint8List.fromList(
      List<int>.generate(1024, (int i) => i & 0xFF),
    );
    int written = 0;
    while (written < size) {
      final int n = (size - written).clamp(0, chunk.length);
      await raf.writeFrom(chunk, 0, n);
      written += n;
    }
    await raf.close();
    status.filePath = file.path;
    status.total = size;
    return file;
  }

  Future<(HttpClientResponse, List<int>)> get(
    String path, {
    String? range,
    String method = 'GET',
  }) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request =
        await client.open(method, '127.0.0.1', server.port, path);
    if (range != null) request.headers.set('Range', range);
    final HttpClientResponse response = await request.close();
    final List<int> bytes = await response
        .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
    client.close();
    return (response, bytes);
  }

  test('serves the full file without a Range header', () async {
    final File file = await writeFile('movie.bin', 4096);
    status.completed = 4096;
    await server.start();

    final (HttpClientResponse response, List<int> bytes) =
        await get('/video/g1/1');

    expect(response.statusCode, 200);
    expect(bytes, await file.readAsBytes());
  });

  test('answers Range requests with 206 and exact bytes', () async {
    final File file = await writeFile('movie.bin', 4096);
    status.completed = 4096;
    await server.start();

    final (HttpClientResponse response, List<int> bytes) =
        await get('/video/g1/1', range: 'bytes=100-199');

    expect(response.statusCode, 206);
    expect(response.headers.value('content-range'), 'bytes 100-199/4096');
    final List<int> expected = (await file.readAsBytes()).sublist(100, 200);
    expect(bytes, expected);
  });

  test('handles open-ended and suffix ranges', () async {
    final File file = await writeFile('movie.bin', 4096);
    status.completed = 4096;
    await server.start();

    final (HttpClientResponse open, List<int> openBytes) =
        await get('/video/g1/1', range: 'bytes=4000-');
    expect(open.statusCode, 206);
    expect(openBytes.length, 96);

    final (HttpClientResponse suffix, List<int> suffixBytes) =
        await get('/video/g1/1', range: 'bytes=-50');
    expect(suffix.statusCode, 206);
    expect(suffixBytes.length, 50);
    expect(suffixBytes, (await file.readAsBytes()).sublist(4046));
  });

  test('returns 416 when the range starts beyond EOF', () async {
    await writeFile('movie.bin', 100);
    status.completed = 100;
    await server.start();

    final (HttpClientResponse response, _) =
        await get('/video/g1/1', range: 'bytes=500-');
    expect(response.statusCode, 416);
    expect(response.headers.value('content-range'), 'bytes */100');
  });

  test('HEAD returns headers without body', () async {
    await writeFile('movie.bin', 2048);
    status.completed = 2048;
    await server.start();

    final (HttpClientResponse response, List<int> bytes) =
        await get('/video/g1/1', method: 'HEAD');
    expect(response.statusCode, 200);
    expect(response.headers.contentType!.toString(), contains('octet-stream'));
    expect(bytes, isEmpty);
  });

  test('waits for undownloaded regions then streams them (FDM-style)',
      () async {
    final File file = await writeFile('movie.bin', 2048);
    status.completed = 0;

    await server.start();
    // Download races ahead of playback while the request is being served.
    final Timer grower = Timer.periodic(
      const Duration(milliseconds: 20),
      (Timer t) {
        if (status.completed < status.total) {
          status.completed = (status.completed + 128).clamp(0, status.total);
        } else {
          t.cancel();
        }
      },
    );
    addTearDown(grower.cancel);

    final HttpClient client = HttpClient();
    final HttpClientRequest request =
        await client.open('GET', '127.0.0.1', server.port, '/video/g1/1');
    final HttpClientResponse response = await request.close();

    final List<int> bytes = await response
        .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
    client.close();

    expect(response.statusCode, 200);
    expect(bytes, await file.readAsBytes());
  });

  test('responds 503 when nothing at the requested offset is available',
      () async {
    await writeFile('movie.bin', 4096);
    status.completed = 0; // nothing downloaded at all
    await server.start();

    final (HttpClientResponse response, _) =
        await get('/video/g1/1', range: 'bytes=3000-');
    // startBufferTimeout (500ms) elapses without the byte at 3000 existing.
    expect(response.statusCode, 503);
  });

  test('serves registered static files (subtitles)', () async {
    final File sub = File('${tempDir.path}/movie.srt');
    await sub.writeAsString('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
    await server.start();

    final String url = server.registerStaticFile(sub.path);
    final String path = Uri.parse(url).path;
    final (HttpClientResponse response, List<int> bytes) = await get(path);

    expect(response.statusCode, 200);
    expect(String.fromCharCodes(bytes), contains('00:00:01,000'));
  });

  group('piece-accurate availability (bitfield)', () {
    // Helper mapping completed piece indexes into the aria2 hex bitfield
    // format (4 pieces per hex char, MSB first, padded to whole bytes).
    String bitfield(int numPieces, Set<int> complete) {
      final int nibbles = (numPieces + 3) ~/ 4;
      final int padded = nibbles.isOdd ? nibbles + 1 : nibbles;
      final StringBuffer out = StringBuffer();
      for (int i = 0; i < padded * 4; i += 4) {
        int nibble = 0;
        for (int b = 0; b < 4; b++) {
          if (complete.contains(i + b)) nibble |= 1 << (3 - b);
        }
        out.write(nibble.toRadixString(16));
      }
      return out.toString();
    }

    test('maps byte positions to pieces correctly', () {
      const int pieceLength = 1024;
      final StreamFileStatus s = StreamFileStatus(
        filePath: '/x/movie.bin',
        totalLength: 4096,
        completedLength: 2048,
        pieceLength: pieceLength,
        fileStartOffset: 0,
        bitfieldHex: bitfield(4, <int>{0, 1}),
        numPieces: 4,
      );

      expect(s.hasByte(0), isTrue);
      expect(s.hasByte(1023), isTrue);
      expect(s.hasByte(1024), isTrue);
      expect(s.hasByte(2047), isTrue);
      // Piece 2 is not complete despite completedLength >= 2048+ bytes
      // possibly being scattered.
      expect(s.hasByte(2048), isFalse);
      expect(s.hasByte(4095), isFalse);

      expect(s.incompleteFrom(0), 2048);
      expect(s.incompleteFrom(1500), 2048);
      // Byte 3000 sits inside the incomplete piece 2 → nothing contiguous
      // from there yet.
      expect(s.incompleteFrom(3000), 3000);
    });

    test('honours fileStartOffset for multi-file bundles', () {
      const int pieceLength = 1024;
      // Second file of a bundle: bytes live in absolute pieces 2 and 3.
      final StreamFileStatus s = StreamFileStatus(
        filePath: '/x/second.bin',
        totalLength: 2048,
        completedLength: 0,
        pieceLength: pieceLength,
        fileStartOffset: 2048,
        bitfieldHex: bitfield(4, <int>{0, 1, 2}),
        numPieces: 4,
      );

      // Absolute piece 2 (file bytes 0..1023) is complete.
      expect(s.hasByte(0), isTrue);
      expect(s.hasByte(1023), isTrue);
      // Absolute piece 3 is not.
      expect(s.hasByte(1024), isFalse);
      expect(s.incompleteFrom(0), 1024);
    });

    test('falls back to completedLength when no bitfield exists', () {
      final StreamFileStatus s = StreamFileStatus(
        filePath: '/x/movie.bin',
        totalLength: 4096,
        completedLength: 1500,
      );
      expect(s.hasByte(1499), isTrue);
      expect(s.hasByte(1500), isFalse);
      expect(s.incompleteFrom(0), 1500);
    });

    test('server only streams bytes inside completed pieces', () async {
      const int pieceLength = 1024;
      final File file = await writeFile('movie.bin', 4096);
      // Scattered completion: pieces 0 and 2 done, 1 and 3 missing. The
      // naive completedLength counter would claim 2048 contiguous bytes.
      StreamFileStatus? current;
      Future<StreamFileStatus?> provider(String gid, int idx) async =>
          current ??= StreamFileStatus(
            filePath: file.path,
            totalLength: 4096,
            completedLength: 3072,
            pieceLength: pieceLength,
            fileStartOffset: 0,
            bitfieldHex: bitfield(4, <int>{0, 2}),
            numPieces: 4,
          );
      final StreamServer pieceServer = StreamServer(
        statusProvider: provider,
        pollInterval: const Duration(milliseconds: 20),
        startBufferBytes: 8,
        startBufferTimeout: const Duration(milliseconds: 400),
        stallTimeout: const Duration(milliseconds: 400),
        chunkSize: 512,
      );
      await pieceServer.start();
      addTearDown(pieceServer.dispose);

      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client
          .open('GET', '127.0.0.1', pieceServer.port, '/video/g1/1');
      request.headers.set('Range', 'bytes=0-1023');
      final HttpClientResponse response = await request.close();
      final List<int> bytes = await response
          .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
      client.close();

      // The response must stop at the end of piece 0 — never leap across
      // the missing piece 1 into piece 2's bytes (which a naive
      // completedLength frontier would have served).
      expect(response.statusCode, 206);
      expect(bytes, (await file.readAsBytes()).sublist(0, 1024));
    });
  });
}
