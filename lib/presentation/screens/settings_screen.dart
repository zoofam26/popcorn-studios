import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../providers/app_providers.dart';
import '../../domain/models.dart';

/// Settings: subtitle preferences, bandwidth limits, seeding policy,
/// engine diagnostics and legal notice.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<String> _languages = <String>[
    'en',
    'es',
    'fr',
    'de',
    'pt',
    'it',
    'ru',
    'ar',
    'hi',
    'tr',
    'zh',
    'ja',
    'ko',
  ];

  static const List<(String, int)> _speedChoices = <(String, int)>[
    ('Unlimited', 0),
    ('1 MB/s', 1048576),
    ('5 MB/s', 5 * 1048576),
    ('10 MB/s', 10 * 1048576),
    ('50 MB/s', 50 * 1048576),
  ];

  static const List<(String, double)> _seedChoices = <(String, double)>[
    ('Stop immediately', 0),
    ('0.5x', 0.5),
    ('1.0x', 1.0),
    ('2.0x', 2.0),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final int? subtitleQuota =
        ref.watch(openSubtitlesProvider).lastRemainingQuota;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          _SectionHeader('Subtitles'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _box(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Preferred languages (OpenSubtitles)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String lang in _languages)
                      FilterChip(
                        label: Text(lang.toUpperCase()),
                        selected: settings.subtitleLanguages.contains(lang),
                        onSelected: (bool selected) {
                          final List<String> next =
                              List<String>.of(settings.subtitleLanguages);
                          selected ? next.add(lang) : next.remove(lang);
                          if (next.isEmpty) return;
                          ref.read(settingsProvider.notifier).update(
                              settings.copyWith(subtitleLanguages: next));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subtitleQuota == null
                      ? 'OpenSubtitles daily quota appears after the first '
                          'subtitle download.'
                      : 'OpenSubtitles downloads remaining today: '
                          '$subtitleQuota',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Bandwidth'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _box(),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text('Max download speed',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    DropdownButton<int>(
                      value: _closestSpeed(settings.maxOverallSpeedBytesPerSec),
                      underline: const SizedBox.shrink(),
                      items: <DropdownMenuItem<int>>[
                        for (final (String, int) c in _speedChoices)
                          DropdownMenuItem<int>(
                            value: c.$2,
                            child: Text(c.$1),
                          ),
                      ],
                      onChanged: (int? value) => ref
                          .read(settingsProvider.notifier)
                          .update(settings.copyWith(
                              maxOverallSpeedBytesPerSec: value ?? 0)),
                    ),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Seeding after completion',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DropdownButton<double>(
                      value: settings.seedRatio,
                      underline: const SizedBox.shrink(),
                      items: <DropdownMenuItem<double>>[
                        for (final (String, double) c in _seedChoices)
                          DropdownMenuItem<double>(
                            value: c.$2,
                            child: Text(c.$1),
                          ),
                      ],
                      onChanged: (double? value) => ref
                          .read(settingsProvider.notifier)
                          .update(settings.copyWith(seedRatio: value ?? 0)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Playback'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _box(),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start playing while downloading',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Open the player right after a torrent is added. '
                'You can always watch from Downloads later.',
                style: TextStyle(fontSize: 12.5),
              ),
              value: settings.autoStartPlayback,
              onChanged: (bool value) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(autoStartPlayback: value)),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Engine'),
          const SizedBox(height: 6),
          FutureBuilder<String>(
            future: _engineInfo(ref),
            builder: (BuildContext context, AsyncSnapshot<String> snap) =>
                Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Text(
                snap.data ?? 'Engine starting…',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('About'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _box(),
            child: Column(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Popcorn Studio ${AppConstants.appVersion}',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Popcorn Studio is a BitTorrent media client. It ships no '
                  'content: you are responsible for streaming and '
                  'downloading only material you have the right to access '
                  'under your local laws. Metadata by TMDB, subtitles by '
                  'OpenSubtitles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _engineInfo(WidgetRef ref) async {
    try {
      final engine = await ref.read(engineReadyProvider.future);
      final String version = await engine.rpc.getVersion();
      final String port = '${engine.streamServer.port}';
      return 'aria2 engine: v$version\n'
          'Streaming server: 127.0.0.1:$port\n'
          'Piece strategy: ${AppConstants.prioritizePiece} '
          '(head-first streaming)';
    } catch (e) {
      return 'Engine offline: $e';
    }
  }

  int _closestSpeed(int configured) {
    for (final (String, int) c in _speedChoices) {
      if (c.$2 == configured) return c.$2;
    }
    return 0;
  }

  BoxDecoration _box() => BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
