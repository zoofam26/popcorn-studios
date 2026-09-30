import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/domain/models.dart';
import 'package:popcorn_studio/engine/bencode.dart';
import 'package:popcorn_studio/engine/engine_manager.dart';
import 'package:popcorn_studio/engine/torrent_facade.dart';

/// End-to-end engine test against the REAL aria2 binary.
///
/// Strategy: the sandbox/CI has no BitTorrent peers, so we craft a torrent
/// whose only seed source is an HTTP webseed on localhost. aria2 downloads
/// it (webseeds use its sequential piece selector), which exercises the
/// complete pipeline: engine spawn → RPC → addTorrent → file selection →
/// completion → stream server byte-range serving.
///
/// Skips automatically when no aria2 binary is available (e.g. plain dev
/// machines). CI downloads the binary first and sets POPCORN_ARIA2.
void main() {
  final String? binary = _findAria2();
  if (binary == null) {
    print('Skipping engine e2e: no aria2 binary found.');
    return;
  }

  late Directory workDir;
  late HttpServer webseed;
  late Uint8List payload;
  late List<int> torrentBytes;
  late Aria2Engine engine;
  late TorrentFacade facade;

  setUpAll(() async {
    workDir = await Directory.systemTemp.createTemp('popcorn_e2e');

    // 1 MiB deterministic payload.
    payload = Uint8List(1 << 20);
    for (int i = 0; i < payload.length; i++) {
      payload[i] = i & 0xFF;
    }

    // Webseed server.
    webseed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    webseed.listen((HttpRequest request) async {
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });

    // Craft the .torrent with a webseed.
    const int pieceLength = 262144;
    final BytesBuilder pieces = BytesBuilder();
    for (int offset = 0; offset < payload.length; offset += pieceLength) {
      final int end = (offset + pieceLength).clamp(0, payload.length);
      pieces.add(sha1.convert(payload.sublist(offset, end)).bytes);
    }
    final Map<String, dynamic> metainfo = <String, dynamic>{
      'announce': 'http://127.0.0.1:9/announce', // unreachable on purpose
      'url-list': <String>['http://127.0.0.1:${webseed.port}/payload.bin'],
      'info': <String, dynamic>{
        'name': 'sintel_test.mp4',
        'length': payload.length,
        'piece length': pieceLength,
        'pieces': pieces.takeBytes(),
      },
    };
    torrentBytes = Bencode.encode(metainfo);
  });

  tearDownAll(() async {
    await facade.stop();
    await webseed.close(force: true);
    if (workDir.existsSync()) await workDir.delete(recursive: true);
  });

  setUp(() async {
    final EnginePaths paths = EnginePaths(
      downloadDir: '${workDir.path}/downloads',
      configDir: '${workDir.path}/config',
      executableDir: workDir.path,
      platform: 'linux',
      binaryOverride: binary,
    );
    engine = Aria2Engine(paths: paths);
    facade = TorrentFacade(engine: engine, taskStore: InMemoryTaskStore());
    await facade.start();
  });

  tearDown(() async {
    await facade.stop();
  });

  test('prepare → select file → download to completion → stream ranges',
      () async {
    // 1. Metadata resolution from raw torrent bytes.
    final PreparedTorrent prepared = await facade.prepare(
      torrentBytes: torrentBytes,
    );
    expect(prepared.displayName, 'sintel_test.mp4');
    expect(prepared.videoFiles, hasLength(1));
    expect(prepared.videoFiles.first.fileName, 'sintel_test.mp4');
    expect(prepared.infoHash, isNotEmpty);

    // 2. Start the real download with file selection.
    final String gid = await facade.startDownload(
      prepared,
      <int>[prepared.videoFiles.first.index],
    );
    expect(gid, isNotEmpty);

    // 3. Wait for completion via the UI-facing task stream.
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
    TorrentTask? completed;
    await for (final List<TorrentTask> list in facade.tasksStream) {
      for (final TorrentTask task in list) {
        if (task.gid == gid && task.isComplete) completed = task;
      }
      if (completed != null) break;
      if (DateTime.now().isAfter(deadline)) {
        fail('download never completed within timeout');
      }
    }
    final TorrentTask task = completed!;
    expect(task.completedLength, payload.length);
    expect(task.videoFiles.first.completedLength, payload.length);

    // 4. The downloaded file matches the original payload byte-for-byte.
    final File downloaded = File(task.videoFiles.first.path);
    expect(await downloaded.exists(), isTrue);
    expect((await downloaded.length()), payload.length);
    final RandomAccessFile raf = await downloaded.open();
    await raf.setPosition(1000);
    final Uint8List slice = await raf.read(64);
    await raf.close();
    expect(slice, payload.sublist(1000, 1064));

    // 5. Stream server serves correct 206 ranges of the finished file.
    final Uri uri = facade.streamServer.videoUri(gid, 1);
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.openUrl('GET', uri);
    request.headers.set('Range', 'bytes=100-199');
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, 206);
    expect(
      response.headers.value('content-range'),
      'bytes 100-199/${payload.length}',
    );
    final List<int> served = await response
        .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
    client.close();
    expect(served, payload.sublist(100, 200));
  }, timeout: const Timeout(Duration(seconds: 180)));
}

String? _findAria2() {
  final String? env = Platform.environment['POPCORN_ARIA2'];
  if (env != null && File(env).existsSync()) return env;
  for (final String candidate in <String>[
    '/usr/local/bin/aria2c',
    '/usr/bin/aria2c',
    '/home/z/tools/aria2/aria2c',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}
