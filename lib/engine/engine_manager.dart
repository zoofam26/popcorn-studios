import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/constants.dart';
import '../core/errors.dart';
import 'aria2_rpc_client.dart';

/// Platform-aware filesystem locations the engine needs.
class EnginePaths {
  EnginePaths({
    required this.downloadDir,
    required this.configDir,
    required this.executableDir,
    this.nativeLibraryDir,
    this.platform,
    this.binaryOverride,
  });

  /// Where completed/in-progress media lives.
  final String downloadDir;

  /// Session files, engine log, saved .torrent metadata, subtitles cache.
  final String configDir;

  /// Directory of the running executable (desktop platforms).
  final String executableDir;

  /// Android only: `applicationInfo.nativeLibraryDir`, where bundled
  /// binaries named `lib*.so` are extracted and marked executable.
  final String? nativeLibraryDir;

  /// Override for tests: 'android' | 'linux' | 'windows'.
  final String? platform;

  /// Test hook: force a specific aria2 binary path.
  final String? binaryOverride;

  String get _sep => Platform.pathSeparator;

  String get logFilePath => '$configDir${_sep}engine.log';

  String get sessionFilePath => '$configDir${_sep}session.list';

  String get tasksDir => '$configDir${_sep}tasks';

  String get subtitlesDir => '$configDir${_sep}subtitles';

  String get _platformName =>
      platform ??
      (Platform.isAndroid
          ? 'android'
          : Platform.isWindows
              ? 'windows'
              : 'linux');

  /// Ordered candidate paths for the bundled aria2 binary.
  List<String> binaryCandidates() {
    if (binaryOverride != null) return <String>[binaryOverride!];
    switch (_platformName) {
      case 'android':
        return <String>[
          if (nativeLibraryDir != null)
            '$nativeLibraryDir${_sep}libpopcornaria2.so',
        ];
      case 'windows':
        return <String>[
          '$executableDir${_sep}engine${_sep}aria2c.exe',
          r'C:\Program Files\Popcorn Studio\engine\aria2c.exe',
        ];
      case 'linux':
      default:
        return <String>[
          '$executableDir${_sep}engine${_sep}aria2c',
          '/opt/popcorn-studio/engine/aria2c',
          '/usr/local/bin/aria2c',
          '/usr/bin/aria2c',
        ];
    }
  }
}

/// Random helpers for free-port selection.
class PortPicker {
  const PortPicker();

  /// Asks the OS for a free loopback TCP port and releases it immediately.
  Future<int> pickFreePort() async {
    final ServerSocket socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = socket.port;
    await socket.close();
    return port;
  }
}

/// Owns the aria2 child process: launch, health-check, shutdown.
class Aria2Engine {
  Aria2Engine({
    required this.paths,
    PortPicker? portPicker,
    RandomSecret? randomSecret,
  })  : _portPicker = portPicker ?? const PortPicker(),
        _randomSecret = randomSecret ?? const RandomSecret();

  static const String _tag = 'Aria2Engine';

  /// How long we give a freshly spawned engine to either stay alive (if it
  /// needs time to bind the RPC port) or die with a diagnosable exit code.
  static const Duration _spawnProbeWindow = Duration(seconds: 4);

  final EnginePaths paths;
  final PortPicker _portPicker;
  final RandomSecret _randomSecret;

  Process? _process;
  Aria2RpcClient? _rpc;
  int? _rpcPort;
  String? _secret;
  IOSink? _logSink;
  bool _stopping = false;

  /// Last engine output lines (stdout+stderr), newest last. Kept so an
  /// immediate crash can be reported with the engine's own words.
  final List<String> _outputTail = <String>[];

  /// A snapshot of the engine's own recent output — surfaced in errors and
  /// the Settings diagnostics panel.
  List<String> get outputTail =>
      List<String>.unmodifiable(_outputTail.sublist(
        _outputTail.length > 40 ? _outputTail.length - 40 : 0,
      ));

  String? get lastErrorDetail => _lastErrorDetail;
  String? _lastErrorDetail;

  void _record(String line) {
    _outputTail.add(line);
    if (_outputTail.length > 200) _outputTail.removeRange(0, 100);
  }

  Aria2RpcClient get rpc {
    final Aria2RpcClient? client = _rpc;
    if (client == null) {
      throw const EngineException('Engine is not started');
    }
    return client;
  }

  bool get isRunning => _process != null;
  int? get rpcPort => _rpcPort;
  String? get secret => _secret;

  /// Launches the daemon and returns once the RPC endpoint is healthy.
  Future<void> start({
    String? maxOverallDownloadLimit,
    String? seedRatio,
    void Function(String line)? log,
  }) async {
    if (_process != null) return;
    _stopping = false;

    await Directory(paths.configDir).create(recursive: true);
    await Directory(paths.tasksDir).create(recursive: true);
    await Directory(paths.subtitlesDir).create(recursive: true);
    await Directory(paths.downloadDir).create(recursive: true);

    _logSink = File(paths.logFilePath).openWrite(mode: FileMode.append);
    void writeLog(String line) {
      log?.call(line);
      _logSink?.writeln(
        '[${DateTime.now().toIso8601String()}] $line',
      );
    }

    final int rpcPort = await _portPicker.pickFreePort();
    final int btPort = await _portPicker.pickFreePort();
    final String secret = _randomSecret.generate();
    final List<String> candidates = paths.binaryCandidates();

    // Android/desktop: verify bundled binaries exist BEFORE trying to exec
    // them, so a missing extraction produces an actionable message instead
    // of a bare ENOENT.
    final List<String> launchable = <String>[];
    for (final String candidate in candidates) {
      final File f = File(candidate);
      if (f.existsSync()) {
        launchable.add(candidate);
      } else {
        writeLog('$_tag: candidate not found on disk: $candidate');
      }
    }
    if (launchable.isEmpty) {
      _lastErrorDetail =
          'The playback engine binary was not found on this device. '
          'Expected at: ${candidates.join(", ")}';
      await _logSink?.flush();
      throw EngineException(
        'The playback engine binary could not be found on this device. '
        'Reinstall the app so its engine component is restored, then '
        'try again.',
      );
    }

    Object? lastError;
    for (final String candidate in launchable) {
      try {
        final List<String> args = <String>[
          '--enable-rpc=true',
          '--rpc-listen-port=$rpcPort',
          '--rpc-secret=$secret',
          '--dir=${paths.downloadDir}',
          '--file-allocation=none',
          '--enable-dht=true',
          '--enable-dht6=false',
          '--listen-port=$btPort',
          '--bt-max-peers=140',
          '--bt-request-peer-speed-limit=15M',
          '--dht-entry-point=dht.transmissionbt.com:6881',
          '--dht-entry-point=router.bittorrent.com:6881',
          '--dht-entry-point=dht.libtorrent.org:25401',
          '--bt-tracker=${AppConstants.defaultTrackers.join(',')}',
          '--dht-file-path=${paths.configDir}${Platform.pathSeparator}dht.dat',
          '--save-session=${paths.sessionFilePath}',
          '--save-session-interval=15',
          '--continue=true',
          '--allow-overwrite=true',
          '--auto-file-renaming=false',
          '--summary-interval=0',
          '--console-log-level=warn',
          '--rpc-save-upload-metadata=false',
          '--seed-ratio=${seedRatio ?? '0'}',
          '--max-overall-download-limit=${maxOverallDownloadLimit ?? '0'}',
          '--user-agent=PopcornStudio/${AppConstants.appVersion}',
          // Exit together with the app process — prevents orphaned engines
          // and phantom-process buildup on Android 12+.
          '--stop-with-process=$pid',
        ];
        if (File(paths.sessionFilePath).existsSync()) {
          args.add('--input-file=${paths.sessionFilePath}');
        }

        writeLog('$_tag: launching ${_safeBinaryName(candidate)} '
            'rpcPort=$rpcPort btPort=$btPort');
        final Process process =
            await Process.start(candidate, args, mode: ProcessStartMode.normal);
        _process = process;
        _rpcPort = rpcPort;
        _secret = secret;

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((String line) {
          _record(line);
          writeLog(line);
        }, onError: (Object _) {});
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((String line) {
          _record(line);
          writeLog(line);
        }, onError: (Object _) {});
        unawaited(
          process.exitCode.then((int code) {
            writeLog('$_tag: exited with code $code');
            _process = null;
            if (!_stopping && code != 0) {
              writeLog('$_tag: engine terminated unexpectedly');
            }
          }),
        );

        // Detect engines that die instantly (bad binary, ROM restriction,
        // missing libs) and surface WHY instead of burning the full health
        // check and failing with a generic message.
        final int exitCode = await process.exitCode
            .timeout(_spawnProbeWindow, onTimeout: () => -1);
        if (exitCode != -1 && !_stopping) {
          // The engine's dying words can arrive on the stdout/stderr
          // streams just after the exit event — let them flush first.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          _process = null;
          final String tail = _outputTail.isEmpty
              ? 'no output captured'
              : _outputTail.take(12).join(' | ');
          _lastErrorDetail =
              'Engine process exited immediately (code $exitCode): $tail';
          writeLog('$_tag: $_lastErrorDetail');
          _rpc = null;
          await _logSink?.flush();
          throw EngineException(
            'The playback engine exited immediately after starting '
            '(code $exitCode). This usually means the engine component is '
            'incompatible with this device. Details: $tail',
          );
        }
        break;
      } on ProcessException catch (e) {
        lastError = e;
        _lastErrorDetail = 'failed to launch $candidate: ${e.message}';
        writeLog('$_tag: $_lastErrorDetail');
        continue;
      }
    }

    if (_process == null) {
      await _logSink?.flush();
      throw EngineException(
        'Could not start the playback engine on this device. '
        'Tried: ${launchable.join(", ")}. '
        'Reason: ${_lastErrorDetail ?? lastError ?? 'unknown'}',
        cause: lastError,
      );
    }

    // Health-check the RPC endpoint (fail fast — the UI never blocks on
    // this; it only makes the Downloads screen show a retry state).
    final Aria2RpcClient client = Aria2RpcClient(port: rpcPort, secret: secret);
    _rpc = client;
    bool healthy = false;
    for (int attempt = 0; attempt < 40; attempt++) {
      try {
        await client.getVersion();
        healthy = true;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_process == null) break;
      }
    }
    if (!healthy) {
      final String tail = outputTail.isEmpty
          ? 'no output captured'
          : outputTail.take(12).join(' | ');
      _lastErrorDetail = 'RPC never became ready: $tail';
      await stop();
      throw EngineException(
        'The playback engine started but did not accept commands on this '
        'device. Details: $tail',
      );
    }
    writeLog('$_tag: RPC ready on port $rpcPort');
  }

  String _safeBinaryName(String path) =>
      path.split(Platform.pathSeparator).last;

  Future<void> stop() async {
    _stopping = true;
    try {
      await _rpc?.saveSession();
    } catch (_) {}
    _rpc?.close();
    _rpc = null;
    _process?.kill();
    _process = null;
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
  }

  /// Reads the last [lines] lines of the engine log file for diagnostics.
  Future<List<String>> readLogTail({int lines = 30}) async {
    try {
      final File file = File(paths.logFilePath);
      if (!await file.exists()) return const <String>[];
      final List<String> all =
          await file.readAsLines().timeout(const Duration(seconds: 3));
      return all.length <= lines
          ? all
          : all.sublist(all.length - lines);
    } catch (_) {
      return const <String>[];
    }
  }

  /// Applies global option changes without restarting.
  Future<void> applyGlobalOptions(Map<String, String> options) async {
    await rpc.changeGlobalOption(options);
  }
}

/// Generates the RPC secret token.
class RandomSecret {
  const RandomSecret();

  String generate() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (int _) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  static const String _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
}
