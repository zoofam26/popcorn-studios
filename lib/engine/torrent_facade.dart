import 'dart:async';
import 'dart:io';

import '../core/constants.dart';
import '../core/errors.dart';
import '../domain/models.dart';
import 'aria2_rpc_client.dart';
import 'engine_manager.dart';
import 'stream_server.dart';

/// Persistence contract for task records (implemented with
/// SharedPreferences in the app, in-memory in tests).
abstract class TaskStore {
  Future<List<TaskRecord>> loadAll();
  Future<void> save(TaskRecord record);
  Future<void> delete(String infoHash);
}

/// In-memory [TaskStore] for tests and CLI tooling.
class InMemoryTaskStore implements TaskStore {
  final Map<String, TaskRecord> _records = <String, TaskRecord>{};

  @override
  Future<List<TaskRecord>> loadAll() async => _records.values.toList();

  @override
  Future<void> save(TaskRecord record) async =>
      _records[record.infoHash] = record;

  @override
  Future<void> delete(String infoHash) async => _records.remove(infoHash);
}

/// High-level facade over the aria2 engine.
///
/// Implements the app's download lifecycle:
///
///   1. `prepare()`  — resolves torrent metadata WITHOUT downloading media:
///      for magnets we start a paused metadata fetch (`bt-save-metadata`,
///      `pause-metadata`), wait for `followedBy`, then read the file list.
///      This is what makes multi-video torrents presentable before any
///      large data transfer starts.
///   2. `startDownload()` — removes the placeholder and re-adds the torrent
///      with `select-file` (chosen video(s) + subtitles) and
///      `bt-prioritize-piece=head=32M,tail=8M` so the player can start on
///      the head of the file.
///   3. `streamServer` serves byte ranges of in-progress files, enabling
///      playback seconds after the download starts.
class TorrentFacade {
  TorrentFacade({
    required Aria2Engine engine,
    required this.taskStore,
    this.metadataTimeout = const Duration(minutes: 4),
    this.pollInterval = const Duration(milliseconds: 600),
    HttpClient? httpClient,
  })  : _engine = engine,
        _httpClient = httpClient ?? HttpClient() {
    // Wire the stream server to the live RPC-backed file status provider.
    streamServer = StreamServer(statusProvider: _fileStatus);
  }

  final Aria2Engine _engine;
  final TaskStore taskStore;
  late final StreamServer streamServer;

  final Duration metadataTimeout;
  final Duration pollInterval;
  final HttpClient _httpClient;

  final Map<String, TaskRecord> _records = <String, TaskRecord>{};
  final StreamController<List<TorrentTask>> _tasksController =
      StreamController<List<TorrentTask>>.broadcast();

  static const List<String> _statusKeys = <String>[
    'gid',
    'status',
    'totalLength',
    'completedLength',
    'downloadSpeed',
    'uploadSpeed',
    'connections',
    'infoHash',
    'bittorrent',
    'files',
    'followedBy',
    'errorCode',
    'errorMessage',
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> start({
    String? maxOverallDownloadLimit,
    String? seedRatio,
  }) async {
    if (!_engine.isRunning) {
      await _engine.start(
        maxOverallDownloadLimit: maxOverallDownloadLimit,
        seedRatio: seedRatio,
      );
    }
    await streamServer.start();
    await _reconcile();
    unawaited(_pollLoop());
  }

  Future<void> stop() async {
    await _engine.stop();
    await streamServer.dispose();
    await _tasksController.close();
    _httpClient.close(force: true);
  }

  Aria2RpcClient get rpc => _engine.rpc;

  Stream<List<TorrentTask>> get tasksStream => _tasksController.stream;

  List<TaskRecord> get records => _records.values.toList(growable: false);

  // ── Preparation (metadata only) ─────────────────────────────────────────

  /// Resolves metadata for a magnet or .torrent source and returns the file
  /// listing. No media is downloaded yet.
  Future<PreparedTorrent> prepare({
    String? magnetUri,
    String? torrentUrl,
    List<int>? torrentBytes,
    int? tmdbId,
    String? posterUrl,
    String? qualityLabel,
    void Function(String stage)? onStage,
  }) async {
    final String downloadDir = _engine.paths.downloadDir;
    onStage?.call('Resolving torrent…');

    if (torrentBytes == null && torrentUrl != null) {
      onStage?.call('Fetching .torrent file…');
      torrentBytes = await _downloadTorrentFile(torrentUrl);
    }

    if (torrentBytes != null) {
      return _prepareFromTorrentBytes(
        torrentBytes,
        downloadDir,
        tmdbId: tmdbId,
        posterUrl: posterUrl,
        qualityLabel: qualityLabel,
      );
    }
    if (magnetUri == null || magnetUri.isEmpty) {
      throw const AppException('No magnet or torrent file provided');
    }
    return _prepareFromMagnet(
      magnetUri,
      downloadDir,
      tmdbId: tmdbId,
      posterUrl: posterUrl,
      qualityLabel: qualityLabel,
      onStage: onStage,
    );
  }

  Future<PreparedTorrent> _prepareFromTorrentBytes(
    List<int> bytes,
    String downloadDir, {
    int? tmdbId,
    String? posterUrl,
    String? qualityLabel,
  }) async {
    final String gid = await rpc.addTorrent(
      bytes,
      options: <String, String>{'dir': downloadDir, 'pause': 'true'},
    );
    final Map<String, dynamic> status = await _waitUntilFilesReady(gid);
    final String infoHash = (status['infoHash'] as String?) ?? '';
    final String name = _displayName(status) ?? 'Torrent $infoHash';

    final String torrentPath = await _persistTorrentBytes(infoHash, bytes);
    return PreparedTorrent(
      placeholderGid: gid,
      infoHash: infoHash.toUpperCase(),
      displayName: name,
      downloadDir: downloadDir,
      files: _parseFiles(status),
      torrentFilePath: torrentPath,
      torrentBytes: bytes,
      tmdbId: tmdbId,
      posterUrl: posterUrl,
      qualityLabel: qualityLabel,
    );
  }

  Future<PreparedTorrent> _prepareFromMagnet(
    String magnetUri,
    String downloadDir, {
    int? tmdbId,
    String? posterUrl,
    String? qualityLabel,
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('Reading torrent metadata…');
    final String gid = await rpc.addUri(
      <String>[magnetUri],
      options: <String, String>{
        'dir': downloadDir,
        'bt-metadata-only': 'false',
        'bt-save-metadata': 'true',
        'pause-metadata': 'true',
        'seed-ratio': '0',
        'seed-time': '0',
      },
    );

    // Wait for metadata: the placeholder either gains files itself or is
    // followed by the real (paused) torrent download.
    Map<String, dynamic> status;
    try {
      status = await _waitUntilFilesReady(gid);
    } on MetadataTimeoutException {
      await rpc.forceRemove(gid);
      rethrow;
    }

    // If metadata produced a followed torrent, use its status.
    final List<dynamic> followedBy =
        (status['followedBy'] as List<dynamic>?) ?? const <dynamic>[];
    String torrentGid = gid;
    if (followedBy.isNotEmpty) {
      torrentGid = followedBy.first as String;
      status = await rpc.tellStatus(torrentGid, keys: _statusKeys);
    }

    final String infoHash = (status['infoHash'] as String?) ?? '';
    final String name = _displayName(status) ?? magnetUri;

    // Locate the saved .torrent written by bt-save-metadata.
    final String savedTorrentPath =
        '${downloadDir}/${infoHash.toUpperCase()}.torrent';
    List<int>? bytes;
    if (File(savedTorrentPath).existsSync()) {
      bytes = await File(savedTorrentPath).readAsBytes();
    }
    if (bytes == null && infoHash.isNotEmpty) {
      // Best-effort fallback: fetch .torrent by hash.
      bytes = await _tryFetchTorrentByHash(infoHash);
    }
    if (bytes != null) {
      await _persistTorrentBytes(infoHash, bytes, atPath: savedTorrentPath);
    }
    if (bytes == null) {
      throw const EngineException(
        'Metadata resolved but no .torrent could be stored for file '
        'selection. Try again or use a direct magnet with trackers.',
      );
    }

    final String torrentPath = await _persistTorrentBytes(infoHash, bytes);
    return PreparedTorrent(
      placeholderGid: torrentGid,
      infoHash: infoHash.toUpperCase(),
      displayName: name,
      downloadDir: downloadDir,
      files: _parseFiles(status),
      torrentFilePath: torrentPath,
      torrentBytes: bytes,
      tmdbId: tmdbId,
      posterUrl: posterUrl,
      qualityLabel: qualityLabel,
    );
  }

  // ── Starting the real download ──────────────────────────────────────────

  /// Starts (or resumes) the download selecting only [selectFileIndexes]
  /// (aria2 1-based indexes). Registers a [TaskRecord] and returns the new
  /// active GID.
  Future<String> startDownload(
    PreparedTorrent prepared,
    List<int> selectFileIndexes,
  ) async {
    if (selectFileIndexes.isEmpty) {
      throw const AppException('No files selected for download');
    }
    await rpc.forceRemove(prepared.placeholderGid);

    final String gid = await rpc.addTorrent(
      prepared.torrentBytes,
      options: <String, String>{
        'dir': prepared.downloadDir,
        'select-file': selectFileIndexes.join(','),
        'bt-prioritize-piece': AppConstants.prioritizePiece,
        'seed-ratio': '0',
        'seed-time': '0',
        'file-allocation': 'none',
        'allow-overwrite': 'true',
        'follow-torrent': 'true',
        'bt-max-peers': '120',
      },
    );

    final List<String> selectedPaths = <String>[
      for (final EngineFile f in prepared.files)
        if (selectFileIndexes.contains(f.index)) f.path,
    ];

    final TaskRecord record = TaskRecord(
      gid: gid,
      infoHash: prepared.infoHash,
      displayName: prepared.displayName,
      downloadDir: prepared.downloadDir,
      selectedFileIndexes: selectFileIndexes,
      filePaths: selectedPaths,
      torrentFilePath: prepared.torrentFilePath,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
      tmdbId: prepared.tmdbId,
      posterUrl: prepared.posterUrl,
      qualityLabel: prepared.qualityLabel,
      totalBytes: prepared.files
          .where((EngineFile f) => selectFileIndexes.contains(f.index))
          .fold<int>(0, (int sum, EngineFile f) => sum + f.length),
    );
    _records[record.infoHash] = record;
    await taskStore.save(record);
    _emitTasks();
    return gid;
  }

  /// Re-adds a previously persisted task after a restart or manual resume.
  Future<String> resumeRecord(TaskRecord record) async {
    final File torrentFile = File(record.torrentFilePath);
    if (!await torrentFile.exists()) {
      throw EngineException(
        'Torrent metadata for "${record.displayName}" is missing on disk',
      );
    }
    final String gid = await rpc.addTorrent(
      await torrentFile.readAsBytes(),
      options: <String, String>{
        'dir': record.downloadDir,
        'select-file': record.selectedFileIndexes.join(','),
        'bt-prioritize-piece': AppConstants.prioritizePiece,
        'seed-ratio': '0',
        'seed-time': '0',
        'file-allocation': 'none',
        'allow-overwrite': 'true',
        'check-integrity': 'true',
      },
    );
    final TaskRecord updated = TaskRecord(
      gid: gid,
      infoHash: record.infoHash,
      displayName: record.displayName,
      downloadDir: record.downloadDir,
      selectedFileIndexes: record.selectedFileIndexes,
      filePaths: record.filePaths,
      torrentFilePath: record.torrentFilePath,
      addedAtMs: record.addedAtMs,
      tmdbId: record.tmdbId,
      posterUrl: record.posterUrl,
      qualityLabel: record.qualityLabel,
      totalBytes: record.totalBytes,
    );
    _records[record.infoHash] = updated;
    await taskStore.save(updated);
    _emitTasks();
    return gid;
  }

  // ── Task controls ───────────────────────────────────────────────────────

  Future<void> pauseTask(String infoHash) async {
    final TaskRecord? record = _records[infoHash];
    if (record == null || record.gid.isEmpty) return;
    await rpc.forcePause(record.gid);
    _emitTasks();
  }

  Future<void> resumeTask(String infoHash) async {
    final TaskRecord? record = _records[infoHash];
    if (record == null) return;
    if (record.gid.isNotEmpty) {
      try {
        final Map<String, dynamic> status =
            await rpc.tellStatus(record.gid, keys: <String>['status']);
        final String statusStr = status['status'] as String? ?? '';
        if (statusStr == 'paused') {
          await rpc.unpause(record.gid);
          _emitTasks();
          return;
        }
      } on RpcException {
        // Fall through to re-adding below.
      }
    }
    await resumeRecord(record);
  }

  Future<void> removeTask(
    String infoHash, {
    bool deleteFiles = false,
  }) async {
    final TaskRecord? record = _records[infoHash];
    if (record != null && record.gid.isNotEmpty) {
      await rpc.forceRemove(record.gid);
    }
    _records.remove(infoHash);
    await taskStore.delete(infoHash);
    if (deleteFiles && record != null) {
      for (final String path in record.filePaths) {
        try {
          final File file = File(path);
          if (await file.exists()) await file.delete();
          final File control = File('$path.aria2');
          if (await control.exists()) await control.delete();
        } catch (_) {}
      }
    }
    _emitTasks();
  }

  Future<GlobalStats> globalStats() async {
    try {
      final Map<String, dynamic> stat = await rpc.getGlobalStat();
      return GlobalStats(
        active: int.tryParse('${stat['numActive']}') ?? 0,
        waiting: int.tryParse('${stat['numWaiting']}') ?? 0,
        stopped: int.tryParse('${stat['numStopped']}') ?? 0,
        downloadSpeed: int.tryParse('${stat['downloadSpeed']}') ?? 0,
        uploadSpeed: int.tryParse('${stat['uploadSpeed']}') ?? 0,
      );
    } on RpcException {
      return GlobalStats.empty;
    }
  }

  /// Resolves file status for the [StreamServer] (conservative: only bytes
  /// belonging to fully completed pieces are reported as available).
  Future<StreamFileStatus?> _fileStatus(String gid, int fileIndex) async {
    final List<Map<String, dynamic>> files = await rpc.getFiles(gid);
    for (final Map<String, dynamic> file in files) {
      if ('${file['index']}' == '$fileIndex') {
        return StreamFileStatus(
          filePath: file['path'] as String,
          totalLength: int.tryParse('${file['length']}') ?? 0,
          completedLength: int.tryParse('${file['completedLength']}') ?? 0,
        );
      }
    }
    return null;
  }

  /// Direct access for the UI: current engine files of a task.
  Future<List<EngineFile>> engineFiles(String gid) async {
    final List<Map<String, dynamic>> files = await rpc.getFiles(gid);
    return files.map(_parseFile).toList(growable: false);
  }

  /// Per-torrent directory for downloaded subtitle files.
  String subtitleCacheDir(String gid) => '${_engine.paths.subtitlesDir}/$gid';

  // ── Internals ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _waitUntilFilesReady(String gid) async {
    final DateTime deadline = DateTime.now().add(metadataTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final Map<String, dynamic> status =
            await rpc.tellStatus(gid, keys: _statusKeys);
        final String statusStr = status['status'] as String? ?? '';
        final List<dynamic> files =
            (status['files'] as List<dynamic>?) ?? const <dynamic>[];
        final bool hasRealFiles = files.any((dynamic f) =>
            f is Map &&
            int.tryParse('${f['length']}') != null &&
            int.parse('${f['length']}') > 0);
        if (hasRealFiles &&
            (statusStr == 'active' ||
                statusStr == 'paused' ||
                statusStr == 'waiting' ||
                statusStr == 'complete' ||
                statusStr == 'error')) {
          if (statusStr == 'error') {
            throw EngineException(
              'Torrent reported an error: '
              '${status['errorMessage'] ?? 'unknown'}',
            );
          }
          return status;
        }
      } on RpcException catch (e) {
        if (e.message.contains('is not found')) {
          throw EngineException('Torrent vanished before metadata arrived');
        }
      }
      await Future<void>.delayed(pollInterval);
    }
    throw const MetadataTimeoutException(
      'Could not fetch torrent metadata in time. The swarm may be cold — '
      'try another torrent or add trackers.',
    );
  }

  String? _displayName(Map<String, dynamic> status) {
    final Map<String, dynamic> bittorrent =
        (status['bittorrent'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> info =
        (bittorrent['info'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return info['name'] as String?;
  }

  List<EngineFile> _parseFiles(Map<String, dynamic> status) {
    final List<dynamic> files =
        (status['files'] as List<dynamic>?) ?? const <dynamic>[];
    return files.map(_parseFile).toList(growable: false);
  }

  EngineFile _parseFile(dynamic file) {
    final Map<String, dynamic> map = file as Map<String, dynamic>;
    return EngineFile(
      index: int.tryParse('${map['index']}') ?? 0,
      path: map['path'] as String? ?? '',
      length: int.tryParse('${map['length']}') ?? 0,
      completedLength: int.tryParse('${map['completedLength']}') ?? 0,
      selected: (map['selected'] as String?) == 'true',
    );
  }

  Future<List<int>?> _downloadTorrentFile(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.headers
          .set(HttpHeaders.userAgentHeader, AppConstants.apibayUserAgent);
      final HttpClientResponse response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200) return null;
      final List<int> bytes = await response
          .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
      // Basic sanity: bencoded torrent starts with 'd'.
      if (bytes.isEmpty || bytes.first != 0x64) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> _tryFetchTorrentByHash(String infoHash) async {
    final String url = AppConstants.itorrentsTemplate
        .replaceFirst('%HASH%', infoHash.toUpperCase());
    return _downloadTorrentFile(url);
  }

  Future<String> _persistTorrentBytes(
    String infoHash,
    List<int> bytes, {
    String? atPath,
  }) async {
    final Directory dir = Directory(_engine.paths.tasksDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final String path = atPath ??
        '${dir.path}/${infoHash.isEmpty ? 'torrent' : infoHash}.torrent';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Matches persisted records against live engine state after restarts.
  Future<void> _reconcile() async {
    final List<TaskRecord> stored = await taskStore.loadAll();
    for (final TaskRecord record in stored) {
      _records[record.infoHash] = record;
    }
    if (_records.isEmpty) return;

    final Set<String> liveHashes = <String>{};
    for (final List<Map<String, dynamic>> bucket
        in <List<Map<String, dynamic>>>[
      await rpc.tellActive(),
      await rpc.tellWaiting(),
      await rpc.tellStopped(num: 200),
    ]) {
      for (final Map<String, dynamic> brief in bucket) {
        final String gid = brief['gid'] as String;
        try {
          final Map<String, dynamic> status = await rpc
              .tellStatus(gid, keys: <String>['gid', 'infoHash', 'status']);
          final String? hash = status['infoHash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            liveHashes.add(hash.toUpperCase());
            final TaskRecord? record = _records[hash.toUpperCase()];
            if (record != null && record.gid != gid) {
              // Re-bind gid if the engine restarted with a new one.
              _records[hash.toUpperCase()] = _rebindGid(record, gid);
              await taskStore.save(_records[hash.toUpperCase()]!);
            }
          }
        } on RpcException {
          continue;
        }
      }
    }
    _emitTasks();
  }

  TaskRecord _rebindGid(TaskRecord record, String gid) => TaskRecord(
        gid: gid,
        infoHash: record.infoHash,
        displayName: record.displayName,
        downloadDir: record.downloadDir,
        selectedFileIndexes: record.selectedFileIndexes,
        filePaths: record.filePaths,
        torrentFilePath: record.torrentFilePath,
        addedAtMs: record.addedAtMs,
        tmdbId: record.tmdbId,
        posterUrl: record.posterUrl,
        qualityLabel: record.qualityLabel,
        totalBytes: record.totalBytes,
      );

  /// Periodic poll loop that converts engine state into UI [TorrentTask]s.
  Future<void> _pollLoop() async {
    while (!_tasksController.isClosed) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        _emitTasks();
      } catch (_) {
        // Engine may be restarting; keep the loop alive.
      }
    }
  }

  Future<void> _emitTasks() async {
    if (_tasksController.isClosed) return;
    final List<TorrentTask> tasks = <TorrentTask>[];
    for (final TaskRecord record in _records.values) {
      if (record.gid.isEmpty) continue;
      try {
        final Map<String, dynamic> status =
            await rpc.tellStatus(record.gid, keys: _statusKeys);
        final List<EngineFile> files = _parseFiles(status);
        tasks.add(TorrentTask(
          gid: record.gid,
          infoHash: record.infoHash,
          displayName: record.displayName,
          status: status['status'] as String? ?? 'unknown',
          totalLength: int.tryParse('${status['totalLength']}') ?? 0,
          completedLength: int.tryParse('${status['completedLength']}') ?? 0,
          downloadSpeed: int.tryParse('${status['downloadSpeed']}') ?? 0,
          uploadSpeed: int.tryParse('${status['uploadSpeed']}') ?? 0,
          connections: int.tryParse('${status['connections']}') ?? 0,
          files: files,
          downloadDir: record.downloadDir,
          tmdbId: record.tmdbId,
          posterUrl: record.posterUrl,
          qualityLabel: record.qualityLabel,
        ));
      } on RpcException {
        // Keep a minimal ghost task so the UI can offer Resume.
        tasks.add(TorrentTask(
          gid: record.gid,
          infoHash: record.infoHash,
          displayName: record.displayName,
          status: 'offline',
          totalLength: record.totalBytes,
          completedLength: 0,
          downloadSpeed: 0,
          uploadSpeed: 0,
          connections: 0,
          files: const <EngineFile>[],
          downloadDir: record.downloadDir,
          tmdbId: record.tmdbId,
          posterUrl: record.posterUrl,
          qualityLabel: record.qualityLabel,
        ));
      }
    }
    tasks.sort((TorrentTask a, TorrentTask b) => b.gid.compareTo(a.gid));
    if (!_tasksController.isClosed) {
      _tasksController.add(tasks);
    }
  }
}
