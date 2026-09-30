import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../engine/torrent_facade.dart';

/// Persists [AppSettings] in SharedPreferences.
class SettingsStore {
  static const String _key = 'popcorn.settings';

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

/// SharedPreferences-backed [TaskStore].
class SharedPrefsTaskStore implements TaskStore {
  static const String _key = 'popcorn.tasks';

  @override
  Future<List<TaskRecord>> loadAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null) return const <TaskRecord>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((dynamic e) => TaskRecord.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const <TaskRecord>[];
    }
  }

  @override
  Future<void> save(TaskRecord record) async {
    final List<TaskRecord> all = (await loadAll())
        .where((TaskRecord r) => r.infoHash != record.infoHash)
        .toList();
    all.add(record);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((TaskRecord r) => r.toJson()).toList()),
    );
  }

  @override
  Future<void> delete(String infoHash) async {
    final List<TaskRecord> all = (await loadAll())
        .where((TaskRecord r) => r.infoHash != infoHash)
        .toList();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((TaskRecord r) => r.toJson()).toList()),
    );
  }
}
