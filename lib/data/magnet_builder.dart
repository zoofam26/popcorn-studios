import '../core/constants.dart';

/// Builds magnet URIs with Popcorn Studio's tracker set appended so that
/// peer discovery works even when source magnets carry few or dead
/// trackers.
String buildMagnetUri({
  required String infoHash,
  String? displayName,
  List<String> extraTrackers = const <String>[],
}) {
  final StringBuffer buffer = StringBuffer(
    'magnet:?xt=urn:btih:${infoHash.toUpperCase()}',
  );
  if (displayName != null && displayName.trim().isNotEmpty) {
    buffer.write('&dn=${Uri.encodeComponent(displayName.trim())}');
  }
  final Set<String> trackers = <String>{
    ...AppConstants.defaultTrackers,
    ...extraTrackers,
  };
  for (final String tracker in trackers) {
    buffer.write('&tr=${Uri.encodeComponent(tracker)}');
  }
  return buffer.toString();
}

/// Extracts the v1 info hash (40 hex chars) from a magnet URI.
String? extractInfoHash(String magnetOrHash) {
  final RegExpMatch? hexMatch =
      RegExp(r'urn:btih:([0-9a-fA-F]{40})').firstMatch(magnetOrHash);
  if (hexMatch != null) return hexMatch.group(1)!.toUpperCase();
  // Bare 40-char hash.
  if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(magnetOrHash.trim())) {
    return magnetOrHash.trim().toUpperCase();
  }
  // Base32 v1 hash (32 chars) → decode to hex.
  final RegExpMatch? b32 =
      RegExp(r'urn:btih:([A-Z2-7]{32})', caseSensitive: false)
          .firstMatch(magnetOrHash);
  if (b32 != null) {
    return base32ToHex(b32.group(1)!.toUpperCase());
  }
  return null;
}

/// Decodes RFC-4648 base32 (no padding) to uppercase hex.
String base32ToHex(String input) {
  const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  int bits = 0;
  int value = 0;
  final StringBuffer hex = StringBuffer();
  for (final int code in input.codeUnits) {
    final int idx = alphabet.indexOf(String.fromCharCode(code));
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    while (bits >= 4) {
      bits -= 4;
      hex.write(((value >> bits) & 0xF).toRadixString(16));
    }
  }
  return hex.toString().toUpperCase();
}

/// Extracts all `tr=` tracker URLs from a magnet URI.
List<String> extractTrackers(String magnetUri) {
  return Uri.parse(magnetUri)
      .queryParametersAll
      .entries
      .where((MapEntry<String, List<String>> e) => e.key == 'tr')
      .expand((MapEntry<String, List<String>> e) => e.value)
      .toList(growable: false);
}
