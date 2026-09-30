import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Platform bindings used before the engine can start.
class PlatformBindings {
  const PlatformBindings();

  /// Android: `applicationInfo.nativeLibraryDir` via MainActivity platform
  /// channel — this is where bundled `lib*.so` executables are extracted.
  Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      const MethodChannel channel = MethodChannel(
        'com.popcornstudio.popcorn_studio/platform',
      );
      return await channel.invokeMethod<String>('getNativeLibraryDir');
    } on PlatformException {
      return null;
    }
  }

  Future<String?> downloadsDirectory() async {
    final Directory? dir = await getDownloadsDirectory();
    return dir?.path;
  }
}
