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

  final EnginePaths paths;
  final PortPicker _portPicker;
  final RandomSecret _randomSecret;

  Process? _process;
  Aria2RpcClient? _rpc;
  int? _rpcPort;
  String? _secret;
  IOSink? _logSink;
  bool _stopping = false;

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

    Object? lastError;
    for (final String candidate in candidates) {
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
          '--bt-max-peers=120',
          '--bt-request-peer-speed-limit=10M',
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
            .listen(writeLog, onError: (Object _) {});
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(writeLog, onError: (Object _) {});
        unawaited(
          process.exitCode.then((int code) {
            writeLog('$_tag: exited with code $code');
            _process = null;
            if (!_stopping && code != 0) {
              writeLog('$_tag: engine terminated unexpectedly');
            }
          }),
        );
        break;
      } on ProcessException catch (e) {
        lastError = e;
        writeLog('$_tag: failed to launch $candidate: ${e.message}');
        continue;
      }
    }

    if (_process == null) {
      await _logSink?.flush();
      throw EngineException(
        'Could not start the download engine. No aria2 binary could be '
        'launched. Tried: ${candidates.join(', ')}',
        cause: lastError,
      );
    }

    // Health-check the RPC endpoint.
    final Aria2RpcClient client = Aria2RpcClient(port: rpcPort, secret: secret);
    _rpc = client;
    bool healthy = false;
    for (int attempt = 0; attempt < 60; attempt++) {
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
      await stop();
      throw const EngineException(
          'aria2 started but its RPC never became ready');
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
