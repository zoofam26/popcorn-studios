import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Result of an update check.
///
/// [updateRequired] is the single bit the app enforces: when true every
/// screen except the update gate becomes unreachable until the user
/// installs a build whose version is at least [latestVersion].
class UpdateStatus {
  const UpdateStatus({
    required this.currentVersion,
    required this.updateRequired,
    this.latestVersion,
    this.releaseUrl,
    this.fromCache = false,
    this.checkFailed = false,
  });

  /// Version of the installed app (e.g. `1.1.0`).
  final String currentVersion;

  /// True when a newer release exists and this build must not work.
  final bool updateRequired;

  /// Latest published version, when known (`null` while offline).
  final String? latestVersion;

  /// Human download page for the latest release.
  final String? releaseUrl;

  /// The decision came from the last successful check (device was offline).
  final bool fromCache;

  /// The live check failed and no usable cache existed.
  final bool checkFailed;

  bool get known => latestVersion != null;
}

/// Compares dotted versions (`1.2.10` > `1.2.9`, leading `v` tolerated).
int compareVersions(String a, String b) {
  final List<int> pa = _parts(a);
  final List<int> pb = _parts(b);
  final int len = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < len; i++) {
    final int x = i < pa.length ? pa[i] : 0;
    final int y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _parts(String v) {
  final String clean = v.trim().replaceFirst(RegExp(r'^[vV]\s*'), '');
  final RegExpMatch? m =
      RegExp(r'(\d+(?:\.\d+)*)').firstMatch(clean);
  if (m == null) return const <int>[0];
  return m
      .group(1)!
      .split('.')
      .map((String s) => int.tryParse(s) ?? 0)
      .toList(growable: false);
}

/// Checks GitHub Releases for a version newer than the installed one and
/// decides whether the installed build may keep working.
///
/// Behaviour contract:
///   * Every launch performs a live check against
///     `repos/zoofam26/popcorn-studios/releases/latest`.
///   * Newer release → [UpdateStatus.updateRequired] = true: the router
///     locks the app to the update screen (no way past it).
///   * Same-or-older release → the app runs normally.
///   * Network/parse failure → the last successful decision (cached for up
///     to 48 h) is reused; with no cache at all the app fails OPEN so a
///     temporary outage never bricks it.
class UpdateService {
  UpdateService({
    http.Client? client,
    Uri? latestReleaseUri,
    SharedPreferences? prefs,
    String? currentVersionOverride,
  })  : _client = client ?? http.Client(),
        _latestReleaseUri =
            latestReleaseUri ?? Uri.parse(AppConstants.latestReleaseUrl),
        _prefs = prefs,
        _currentVersionOverride = currentVersionOverride;

  final http.Client _client;
  final Uri _latestReleaseUri;
  SharedPreferences? _prefs;
  final String? _currentVersionOverride;

  static const String _cacheTagKey = 'update.cache.latestTag';
  static const String _cacheUrlKey = 'update.cache.releaseUrl';
  static const String _cacheAtKey = 'update.cache.checkedAtMs';
  static const Duration _cacheTtl = Duration(hours: 48);

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Installed app version, e.g. `1.2.0`.
  Future<String> currentVersion() async {
    if (_currentVersionOverride != null) return _currentVersionOverride;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) return info.version;
    } catch (_) {}
    return AppConstants.appVersion;
  }

  /// Startup evaluation: live check with a short timeout, cache fallback.
  Future<UpdateStatus> evaluate({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return _check(timeout: timeout, force: false);
  }

  /// Manual check (Settings): same as [evaluate] but ignores the cache for
  /// failures and always reports the live outcome.
  Future<UpdateStatus> checkNow({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    return _check(timeout: timeout, force: true);
  }

  Future<UpdateStatus> _check({
    required Duration timeout,
    required bool force,
  }) async {
    final String current = await currentVersion();

    String? latest;
    String? releaseUrl;
    bool failed = false;
    try {
      final http.Response response = await _client
          .get(
            _latestReleaseUri,
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'PopcornStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(timeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> body =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>;
        final String tag = (body['tag_name'] as String?)?.trim() ?? '';
        if (tag.isNotEmpty) {
          latest = tag.replaceFirst(RegExp(r'^[vV]\s*'), '');
          releaseUrl = (body['html_url'] as String?)?.trim().isNotEmpty ?? false
              ? body['html_url'] as String
              : AppConstants.releasePageUrl;
          await _writeCache(latest, releaseUrl);
        }
      } else {
        failed = true;
      }
    } on Exception {
      failed = true;
    }

    if (latest != null) {
      return UpdateStatus(
        currentVersion: current,
        updateRequired: compareVersions(latest, current) > 0,
        latestVersion: latest,
        releaseUrl: releaseUrl ?? AppConstants.releasePageUrl,
      );
    }

    // Live check failed — fall back to a recent cached decision so the
    // policy ("older builds stop working") still holds for a while
    // offline. With no cache at all, fail open.
    if (!force) {
      final UpdateStatus? cached = await _cachedStatus(current);
      if (cached != null) return cached;
    }
    return UpdateStatus(
      currentVersion: current,
      updateRequired: false,
      checkFailed: failed,
    );
  }

  Future<UpdateStatus?> _cachedStatus(String current) async {
    try {
      final SharedPreferences prefs = await _preferences;
      final int at = prefs.getInt(_cacheAtKey) ?? 0;
      if (at <= 0) return null;
      final DateTime when =
          DateTime.fromMillisecondsSinceEpoch(at);
      if (DateTime.now().difference(when) > _cacheTtl) return null;
      final String? tag = prefs.getString(_cacheTagKey);
      if (tag == null || tag.isEmpty) return null;
      return UpdateStatus(
        currentVersion: current,
        updateRequired: compareVersions(tag, current) > 0,
        latestVersion: tag,
        releaseUrl: prefs.getString(_cacheUrlKey) ??
            AppConstants.releasePageUrl,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String latest, String? url) async {
    try {
      final SharedPreferences prefs = await _preferences;
      await prefs.setString(_cacheTagKey, latest);
      if (url != null) await prefs.setString(_cacheUrlKey, url);
      await prefs.setInt(
          _cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
