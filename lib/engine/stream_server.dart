import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/errors.dart';

/// Snapshot of a file inside an active download, used by the stream server
/// to decide what can be served immediately and what must be waited for.
///
/// When [bitfieldHex] is present the server maps byte positions to piece
/// indexes and only serves bytes that belong to fully downloaded pieces —
/// the download frontier is piece-accurate instead of the (scattered)
/// completed-bytes counter, which prevents stutter and corruption when the
/// engine fills pieces out of order.
class StreamFileStatus {
  StreamFileStatus({
    required this.filePath,
    required this.totalLength,
    required this.completedLength,
    this.pieceLength,
    this.fileStartOffset = 0,
    this.bitfieldHex,
    this.numPieces,
  });

  final String filePath;
  final int totalLength;

  /// Bytes of this file that belong to fully completed pieces.
  final int completedLength;

  /// Torrent piece length in bytes (when known).
  final int? pieceLength;

  /// Absolute byte offset of this file inside the whole download — needed
  /// to translate file positions into piece indexes.
  final int fileStartOffset;

  /// aria2 bitfield: one hex character per 4 pieces (`1` = complete).
  final String? bitfieldHex;

  final int? numPieces;

  Uint8List? _bits;

  bool get _hasBitfield =>
      bitfieldHex != null &&
      bitfieldHex!.isNotEmpty &&
      pieceLength != null &&
      pieceLength! > 0;

  bool _pieceComplete(int index) {
    final Uint8List? bits = _bits ??= _decodeBitfield(bitfieldHex!);
    if (bits == null) return false;
    final int byte = index >> 3;
    if (byte >= bits.length) return false;
    return (bits[byte] >> (7 - (index & 7))) & 1 == 1;
  }

  static Uint8List? _decodeBitfield(String hex) {
    final int len = hex.length;
    if (len.isOdd) return null;
    final Uint8List out = Uint8List(len ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final int? v = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (v == null) return null;
      out[i] = v;
    }
    return out;
  }

  /// Returns true when the byte at file position [pos] lives inside a fully
  /// downloaded piece.
  bool hasByte(int pos) {
    if (pos < 0 || pos >= totalLength) return false;
    if (!_hasBitfield) return pos < completedLength;
    return _pieceComplete((fileStartOffset + pos) ~/ pieceLength!);
  }

  /// The first file-space position >= [pos] that is NOT yet downloaded —
  /// in other words, the length of the contiguous downloaded run starting
  /// at [pos]. Returns `totalLength` when everything from [pos] onward is
  /// available.
  int incompleteFrom(int pos) {
    if (!_hasBitfield) return min(completedLength, totalLength);
    if (pos >= totalLength) return totalLength;
    final int pieceLen = pieceLength!;
    int piece = (fileStartOffset + pos) ~/ pieceLen;
    if (!_pieceComplete(piece)) {
      // The byte at [pos] itself lives in an incomplete piece.
      return pos;
    }
    final int? total = numPieces;
    while (total == null || piece < total) {
      if (!_pieceComplete(piece)) {
        final int pieceStartAbs = piece * pieceLen;
        final int filePos = pieceStartAbs - fileStartOffset;
        return max(pos, min(filePos, totalLength));
      }
      piece++;
    }
    return totalLength;
  }
}

/// Local HTTP server that streams partially-downloaded files with proper
/// `Accept-Ranges` / `206 Partial Content` semantics.
///
/// This replicates the "watch while downloading" behaviour popularised by
/// FDM / Stremio:
///   1. The player opens `http://127.0.0.1:<port>/video/<gid>/<fileIndex>`
///      and issues byte-range requests like any HTTP video source.
///   2. For ranges that are already on disk we serve straight from the file.
///   3. For ranges ahead of the download frontier we hold the response while
///      polling the engine, then stream bytes as pieces complete — the
///      player just sees a slightly slow origin server.
class StreamServer {
  StreamServer({
    required this.statusProvider,
    this.pollInterval = const Duration(
      milliseconds: AppConstants.streamPollIntervalMs,
    ),
    this.startBufferBytes = AppConstants.streamStartBufferBytes,
    this.startBufferTimeout = const Duration(
      seconds: AppConstants.streamStartBufferTimeoutSec,
    ),
    this.stallTimeout = const Duration(
      seconds: AppConstants.streamStallTimeoutSec,
    ),
    this.chunkSize = AppConstants.streamChunkBytes,
  });

  /// Resolves the current file status for an active download. Throwing or
  /// returning null yields a 404/502 to the client.
  final Future<StreamFileStatus?> Function(String gid, int fileIndex)
      statusProvider;

  final Duration pollInterval;
  final int startBufferBytes;
  final Duration startBufferTimeout;
  final Duration stallTimeout;
  final int chunkSize;

  HttpServer? _server;
  final Map<String, String> _staticFiles = <String, String>{};
  final Random _random = Random.secure();

  int get port {
    final HttpServer? server = _server;
    if (server == null)
      throw const EngineException('Stream server not started');
    return server.port;
  }

  String get baseUrl => 'http://127.0.0.1:$port';

  bool get isRunning => _server != null;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(
      (HttpRequest request) {
        unawaited(_safeHandle(request));
      },
      onError: (Object _) {},
    );
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _staticFiles.clear();
  }

  /// Playback URL for [fileIndex] of download [gid].
  Uri videoUri(String gid, int fileIndex) =>
      Uri.parse('$baseUrl/video/$gid/$fileIndex');

  /// Registers a real file (e.g. a subtitle) for anonymous local serving and
  /// returns its URL.
  String registerStaticFile(String filePath) {
    final String token = _randomToken();
    _staticFiles[token] = filePath;
    final String name = filePath.replaceAll('\\', '/').split('/').last;
    return '$baseUrl/static/$token/$name';
  }

  String _randomToken() => List<String>.generate(
      12, (int _) => _random.nextInt(16).toRadixString(16)).join();

  Future<void> _safeHandle(HttpRequest request) async {
    try {
      final List<String> segments = request.uri.pathSegments;
      if (segments.length >= 3 && segments.first == 'video') {
        await _handleVideo(request, segments[1], segments[2]);
      } else if (segments.length >= 3 && segments.first == 'static') {
        await _handleStatic(request, segments[1], segments.skip(2).join('/'));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } on RpcException {
      await _respondJson(request, HttpStatus.badGateway,
          <String, dynamic>{'error': 'engine-rpc-failed'});
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleVideo(
    HttpRequest request,
    String gid,
    String indexSegment,
  ) async {
    final int? fileIndex = int.tryParse(indexSegment);
    if (fileIndex == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final StreamFileStatus? status = await statusProvider(gid, fileIndex);
    if (status == null || status.totalLength <= 0) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final int total = status.totalLength;
    final Range? parsedRange = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      total,
    );
    if (parsedRange == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$total',
      );
      await request.response.close();
      return;
    }
    Range range = parsedRange;

    // Gate the response on availability: at playback start we wait for the
    // head buffer; on a seek we wait until the first requested byte exists.
    final int available = status.incompleteFrom(range.start);
    final bool isInitialRequest = range.start == 0;
    final int target =
        isInitialRequest ? _min(startBufferBytes, total) : range.start + 1;

    if (available < target) {
      final bool ready = await _waitForBytes(
        gid,
        fileIndex,
        target,
        startPos: range.start,
        budget: isInitialRequest ? startBufferTimeout : stallTimeout,
      );
      // Re-read the frontier: bytes may have arrived during the wait.
      final int nowAvailable = (await statusProvider(gid, fileIndex))
              ?.incompleteFrom(range.start) ??
          0;
      final bool haveStartByte = nowAvailable > range.start;
      if (!ready && !haveStartByte && !isInitialRequest) {
        // Seek into an undownloaded region — ask the player to retry.
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.set(HttpHeaders.retryAfterHeader, '2');
        await request.response.close();
        return;
      }
      // Initial request: stream whatever exists; the pump loop keeps
      // waiting for progress until the stall timeout.
    }

    // Carry engine context through to the pump loop.
    range = Range(
      start: range.start,
      end: range.end,
      partial: range.partial,
      gid: gid,
      fileIndex: fileIndex,
      filePath: status.filePath,
    );

    final bool isHead = request.method == 'HEAD';
    final HttpHeaders headers = request.response.headers;
    headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentType = _contentType(status.filePath)
      ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(DateTime.now()));

    if (range.partial) {
      request.response.statusCode = HttpStatus.partialContent;
      headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$total',
      );
    } else {
      request.response.statusCode = HttpStatus.ok;
    }
    request.response.contentLength = range.end - range.start + 1;

    if (isHead) {
      await request.response.close();
      return;
    }

    // Stream progressively: flush every chunk immediately so the player
    // sees bytes as pieces complete.
    request.response.bufferOutput = false;
    await _pumpFile(request, status.filePath, range);
  }

  /// Streams [range] of [filePath], polling the engine for frontier progress
  /// and throttling on undownloaded regions.
  Future<void> _pumpFile(
      HttpRequest request, String filePath, Range range) async {
    RandomAccessFile? raf;
    try {
      // The file may not exist yet (allocation=none) — brief wait loop.
      final DateTime deadline = DateTime.now().add(startBufferTimeout);
      while (!await File(filePath).exists()) {
        if (DateTime.now().isAfter(deadline)) {
          await request.response.close();
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
      raf = await File(filePath).open();

      int pos = range.start;
      int lastProgressBytes = -1;
      DateTime lastProgressAt = DateTime.now();

      while (pos <= range.end) {
        try {
          final StreamFileStatus? status =
              await statusProvider(range.gid, range.fileIndex);
          // Piece-accurate contiguous frontier from the current position.
          final int frontier = status?.incompleteFrom(pos) ?? 0;

          if (frontier > lastProgressBytes) {
            lastProgressBytes = frontier;
            lastProgressAt = DateTime.now();
          } else if (DateTime.now().difference(lastProgressAt) > stallTimeout) {
            break; // Stalled for too long — let the player re-request.
          }

          final int readable =
              _min(_min(frontier - pos, range.end - pos + 1), chunkSize);
          if (readable <= 0) {
            await Future<void>.delayed(pollInterval);
            continue;
          }

          await raf.setPosition(pos);
          final Uint8List bytes = await raf.read(readable);
          if (bytes.isEmpty) {
            await Future<void>.delayed(pollInterval);
            continue;
          }
          request.response.add(bytes);
          await request.response.flush();
          pos += bytes.length;
        } on SocketException {
          break; // Player disconnected (seek/closed) — expected.
        } on StateError {
          break;
        }
      }
    } finally {
      await raf?.close();
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<bool> _waitForBytes(
    String gid,
    int fileIndex,
    int target, {
    required int startPos,
    required Duration budget,
  }) async {
    final DateTime deadline = DateTime.now().add(budget);
    int lastSeen = -1;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final StreamFileStatus? status = await statusProvider(gid, fileIndex);
        if (status == null) return false;
        final int available = status.incompleteFrom(startPos);
        if (available >= target || available >= status.totalLength) {
          return true;
        }
        lastSeen = available;
      } catch (_) {
        return false;
      }
      await Future<void>.delayed(pollInterval);
    }
    return lastSeen >= target;
  }

  Future<void> _handleStatic(
    HttpRequest request,
    String token,
    String name,
  ) async {
    final String? path = _staticFiles[token];
    if (path == null || !await File(path).exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final File file = File(path);
    final List<int> bytes = await file.readAsBytes();
    request.response.headers.contentType = _contentType(path);
    request.response.contentLength = bytes.length;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    request.response.add(bytes);
    await request.response.close();
  }

  Range? _parseRange(String? header, int total) {
    int start = 0;
    int end = total - 1;
    bool partial = false;
    if (header != null) {
      final RegExpMatch? match =
          RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
      if (match == null) return null;
      final String startStr = match.group(1) ?? '';
      final String endStr = match.group(2) ?? '';
      if (startStr.isEmpty && endStr.isEmpty) return null;
      if (startStr.isEmpty) {
        // suffix range: last N bytes
        final int n = int.parse(endStr);
        if (n <= 0) return null;
        start = _max(0, total - n);
      } else {
        start = int.parse(startStr);
        if (endStr.isNotEmpty) end = int.parse(endStr);
      }
      if (start >= total) return null;
      end = _min(end, total - 1);
      if (end < start) return null;
      partial = true;
    }
    return Range(start: start, end: end, partial: partial);
  }

  Future<void> _respondJson(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  }

  static ContentType _contentType(String path) {
    final String ext = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .split('.')
        .last
        .toLowerCase();
    return switch (ext) {
      'mp4' || 'm4v' => ContentType('video', 'mp4'),
      'mkv' => ContentType('video', 'x-matroska'),
      'webm' => ContentType('video', 'webm'),
      'avi' => ContentType('video', 'x-msvideo'),
      'mov' => ContentType('video', 'quicktime'),
      'ts' || 'm2ts' => ContentType('video', 'mp2t'),
      'srt' => ContentType('application', 'x-subrip'),
      'vtt' => ContentType('text', 'vtt'),
      'ass' || 'ssa' => ContentType('text', 'plain'),
      _ => ContentType.binary,
    };
  }
}

/// Simple value object describing the byte span of one response.
class Range {
  const Range({
    required this.start,
    required this.end,
    required this.partial,
    this.gid = '',
    this.fileIndex = 0,
    this.filePath = '',
  });

  final int start;
  final int end;
  final bool partial;

  /// Extra context copied from the request for the pump loop.
  final String gid;
  final int fileIndex;
  final String filePath;
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
