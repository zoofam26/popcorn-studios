import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engine/engine_manager.dart';

/// Assembles the engine filesystem layout for the current platform.
///
///  * Android: downloads live in app-specific external storage; the bundled
///    aria2 binary is exposed by the OS under `nativeLibraryDir` as
///    `libpopcornaria2.so`.
///  * Desktop: downloads go to the user's Downloads folder (falling back to
///    Documents), engine assets ship next to the executable.
Future<EnginePaths> buildEnginePaths({
  String? nativeLibraryDir,
  String? overrideDownloadDir,
}) async {
  final Directory support = await getApplicationSupportDirectory();
  final String configDir = '${support.path}${Platform.pathSeparator}engine';

  String downloadDir;
  if (overrideDownloadDir != null) {
    downloadDir = overrideDownloadDir;
  } else if (Platform.isAndroid) {
    final Directory? ext = await getExternalStorageDirectory();
    downloadDir =
        '${(ext ?? await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}movies';
  } else {
    final Directory? downloads = await getDownloadsDirectory();
    final Directory base =
        downloads ?? await getApplicationDocumentsDirectory();
    downloadDir = '${base.path}${Platform.pathSeparator}PopcornStudio';
  }

  final String executableDir = File(Platform.resolvedExecutable).parent.path;

  return EnginePaths(
    downloadDir: downloadDir,
    configDir: configDir,
    executableDir: executableDir,
    nativeLibraryDir: nativeLibraryDir,
  );
}

/// Android-only: resolves `applicationInfo.nativeLibraryDir` through the
/// platform channel declared in MainActivity.kt.
Future<String?> resolveNativeLibraryDir() async {
  if (!Platform.isAndroid) return null;
  return null; // Replaced by PlatformBindings in the app layer (testable).
}
