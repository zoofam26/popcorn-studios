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
}
