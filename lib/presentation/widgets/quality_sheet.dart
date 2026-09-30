import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../engine/torrent_facade.dart';
import '../providers/app_providers.dart';
import 'common.dart';
import 'video_picker_sheet.dart';

/// Bottom sheet listing every quality option for a movie.
Future<void> showQualitySheet(
  BuildContext context,
  WidgetRef ref,
  int movieId,
) async {
  final List<QualityOption> options =
      await ref.read(qualityOptionsProvider(movieId).future);

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: <Widget>[
          const Text(
            'Choose quality',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Every source is listed with size and availability. You can '
            'start watching before the download completes.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          for (final QualityOption option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.divider),
                ),
                tileColor: AppTheme.surface,
                leading: QualityBadge(label: option.label, fontSize: 13),
                title: Text(
                  option.sizeLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  option.best.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
                trailing: SeedersChip(seeders: option.best.seeders),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showQualityFlow(sheetContext, ref, option.best, movieId);
                },
              ),
            ),
        ],
      ),
    ),
  );
}

/// Full playback lifecycle for one chosen source:
///   resolve details → (multi-video picker) → start download → player.
Future<void> showQualityFlow(
  BuildContext context,
  WidgetRef ref,
  TorrentInfo torrent,
  int movieId,
) async {
  final TorrentFacade facade;
  try {
    facade = await ref.read(engineReadyProvider.future);
  } catch (e) {
    _showSnack(context, 'Engine unavailable: $e', error: true);
    return;
  }

  final MovieDetail detail;
  try {
    detail = await ref.read(movieDetailProvider(movieId).future);
  } catch (e) {
    _showSnack(context, 'Movie metadata unavailable: $e', error: true);
    return;
  }

  final ValueNotifier<String> stage =
      ValueNotifier<String>('Finding sources…');
  bool sentToBackground = false;

  final Future<void> flow = _runFlow(
    context,
    ref,
    facade,
    torrent,
    detail,
    stage,
    () => sentToBackground,
  );

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => PopScope<bool>(
      canPop: false,
      child: AlertDialog(
        title: const Text('Preparing playback'),
        content: ValueListenableBuilder<String>(
          valueListenable: stage,
          builder: (BuildContext c, String s, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                s,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              sentToBackground = true;
              Navigator.of(dialogContext).pop();
              _showSnack(
                dialogContext,
                'Resolving in background — check Downloads shortly.',
              );
            },
            child: const Text('Run in background'),
          ),
        ],
      ),
    ),
  );

  await flow;
}

Future<void> _runFlow(
  BuildContext context,
  WidgetRef ref,
  TorrentFacade facade,
  TorrentInfo torrent,
  MovieDetail detail,
  ValueNotifier<String> stage,
  bool Function() backgroundRequested,
) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  PreparedTorrent? prepared;
  try {
    prepared = await facade.prepare(
      magnetUri: torrent.magnetUri,
      torrentUrl: torrent.torrentUrl,
      tmdbId: detail.movie.id,
      posterUrl: detail.movie.posterUrl,
      qualityLabel: torrent.quality,
      friendlyTitle: _friendlyTitle(detail.movie, torrent),
      onStage: (String s) => stage.value = s,
    );
  } catch (e) {
    stage.dispose();
    if (!backgroundRequested()) {
      navigator.pop();
    }
    _showSnack(context, 'Could not prepare this source: $e', error: true);
    return;
  }

  final PreparedTorrent torrentData = prepared;
  if (!backgroundRequested()) {
    navigator.pop();
  }
  stage.dispose();

  if (torrentData.videoFiles.isEmpty) {
    _showSnack(
      context,
      'No playable video was found in this source. Try another quality.',
      error: true,
    );
    return;
  }

  // Resolve the video to play. When the source tells us the exact file
  // (Stremio-style addons do), match it directly — no picker needed. With
  // several videos inside one bundle the user chooses.
  List<int> selected;
  final String? expected = torrent.videoFileName;
  final EngineFile? exactMatch = expected == null
      ? null
      : torrentData.videoFiles.cast<EngineFile?>().firstWhere(
          (EngineFile? f) =>
              f != null &&
              f.fileName.toLowerCase() == expected.toLowerCase(),
          orElse: () => null,
        );
  if (exactMatch != null) {
    selected = <int>[exactMatch.index];
  } else if (torrentData.videoFiles.length == 1) {
    selected = <int>[torrentData.videoFiles.first.index];
  } else {
    final List<int>? picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => VideoPickerSheet(
        videos: torrentData.videoFiles,
      ),
    );
    if (picked == null || picked.isEmpty) {
      _showSnack(context, 'Cancelled — nothing was downloaded.');
      return;
    }
    selected = picked;
  }

  try {
    final String gid = await facade.startDownload(torrentData, selected);
    _showSnack(
      context,
      'Download started — you can watch while it downloads.',
    );
    final bool autoPlay = ref.read(settingsProvider).autoStartPlayback;
    if (autoPlay && context.mounted) {
      await context.push(
        '/player',
        extra: PlayerArgs(
          gid: gid,
          fileIndex: selected.first,
          title: torrentData.displayName,
          tmdbId: torrentData.tmdbId,
          posterUrl: torrentData.posterUrl,
        ),
      );
    }
  } catch (e) {
    _showSnack(context, 'Failed to start download: $e', error: true);
  }
}

void _showSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.danger.withValues(alpha: 0.9) : null,
    ),
  );
}

/// The title shown in the Downloads screen: movie name (+ year), falling
/// back to the cleaned release name — never a raw link.
String _friendlyTitle(Movie movie, TorrentInfo torrent) {
  final String base =
      movie.releaseYear > 0 ? '${movie.title} (${movie.releaseYear})' : movie.title;
  if (base.trim().isNotEmpty) return base;
  return torrent.name.replaceAll(RegExp(r'[._]'), ' ').trim();
}
