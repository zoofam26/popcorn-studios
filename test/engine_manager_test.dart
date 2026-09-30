import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/core/errors.dart';
import 'package:popcorn_studio/engine/engine_manager.dart';

/// Engine spawn diagnostics: a real device failure (engine dead on Android)
/// must produce a message that says WHY, instead of a generic timeout.
void main() {
  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('popcorn_engine');
  });

  tearDown(() async {
    try {
      await workDir.delete(recursive: true);
    } catch (_) {}
  });

  Aria2Engine engineWith({String? binaryOverride}) {
    return Aria2Engine(
      paths: EnginePaths(
        downloadDir: '${workDir.path}/downloads',
        configDir: '${workDir.path}/config',
        executableDir: workDir.path,
        platform: 'linux',
        binaryOverride: binaryOverride,
      ),
    );
  }

  test('missing binary produces an actionable error', () async {
    final Aria2Engine engine =
        engineWith(binaryOverride: '${workDir.path}/does-not-exist');
    await expectLater(
      engine.start(),
      throwsA(
        isA<EngineException>().having(
          (EngineException e) => e.message,
          'message',
          contains('could not be found'),
        ),
      ),
    );
  });

  test(
      'engine that exits immediately reports exit code + output tail',
      () async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return; // /bin/sh redirection used below is POSIX-only.
    }
    // A script that writes a line to stderr and dies with code 7.
    final File badBinary = File('${workDir.path}/fake-engine')..create();
    await badBinary.writeAsString('#!/bin/sh\necho boom >&2\nexit 7\n');
    await Process.run('chmod', <String>['+x', badBinary.path]);

    final Aria2Engine engine = engineWith(binaryOverride: badBinary.path);
    await expectLater(
      engine.start(),
      throwsA(isA<EngineException>().having(
        (EngineException e) => e.message,
        'message',
        allOf(contains('code 7'), contains('boom')),
      )),
    );
    expect(engine.isRunning, isFalse);
  });

  test('real engine still passes the immediate-exit probe', () async {
    final String? binary = _findAria2();
    if (binary == null) {
      print('Skipping: no aria2 binary available.');
      return;
    }
    final Aria2Engine engine = engineWith(binaryOverride: binary);
    await engine.start();
    expect(engine.isRunning, isTrue);
    await engine.stop();
  });
}

String? _findAria2() {
  const String env = String.fromEnvironment('POPCORN_ARIA2');
  if (env.isNotEmpty && File(env).existsSync()) return env;
  for (final String path in const <String>[
    '/usr/bin/aria2c',
    '/usr/local/bin/aria2c',
  ]) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
