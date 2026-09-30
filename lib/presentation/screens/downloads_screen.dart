import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../data/magnet_builder.dart' show extractInfoHash;
import '../../domain/models.dart';
import '../providers/app_providers.dart';
import '../widgets/common.dart';
import '../widgets/video_picker_sheet.dart';
import '../../engine/torrent_facade.dart';

/// Download manager: live progress, watch-while-downloading, pause/resume,
/// delete and manual magnet import.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Timer? _statsTimer;
  GlobalStats _stats = GlobalStats.empty;

  @override
  void initState() {
    super.initState();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (Timer _) async {
      try {
        final TorrentFacade facade = await ref.read(engineReadyProvider.future);
        final GlobalStats stats = await facade.globalStats();
        if (mounted) setState(() => _stats = stats);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<TorrentFacade> engine = ref.watch(engineReadyProvider);
    final AsyncValue<List<TorrentTask>> tasks = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                '↓ ${formatSpeed(_stats.downloadSpeed)}   '
                '↑ ${formatSpeed(_stats.uploadSpeed)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: engine.hasValue
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.accent,
              onPressed: () => _showAddLinkDialog(context, ref),
              icon: const Icon(Icons.add_link),
              label: const Text('Paste link'),
            )
          : null,
      body: engine.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Starting download engine…',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
        error: (Object e, StackTrace s) => ErrorRetryView(
          message: 'Download engine failed to start.\n$e',
          onRetry: () => ref.invalidate(engineReadyProvider),
        ),
        data: (TorrentFacade _) => tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace s) => ErrorRetryView(
            message: 'Lost connection to the engine.\n$e',
            onRetry: () => ref.invalidate(engineReadyProvider),
          ),
          data: (List<TorrentTask> list) {
            if (list.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.download_for_offline_outlined,
                        size: 64, color: AppTheme.textSecondary),
                    SizedBox(height: 12),
                    Text(
                      'No downloads yet.\nPick a movie from Home or paste a '
                      'link here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) =>
                  _TaskCard(task: list[index]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddLinkDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final TextEditingController controller = TextEditingController();
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Add from link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Paste link here',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.isEmpty || !mounted) return;

    try {
      final TorrentFacade facade = await ref.read(engineReadyProvider.future);
      final bool isSourceUrl = input.startsWith('http');
      final PreparedTorrent prepared = await facade.prepare(
        magnetUri: isSourceUrl ? null : input,
        torrentUrl: isSourceUrl ? input : null,
        infoHash: isSourceUrl ? null : extractInfoHash(input),
        friendlyTitle: _titleFromLink(input),
      );
      if (!mounted) return;

      List<int> selected;
      if (prepared.videoFiles.isEmpty) {
        _snack('No playable video was found in this source.', error: true);
        return;
      } else if (prepared.videoFiles.length == 1) {
        selected = <int>[prepared.videoFiles.first.index];
      } else {
        final List<int>? picked = await showModalBottomSheet<List<int>>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) =>
              VideoPickerSheet(videos: prepared.videoFiles),
        );
        if (picked == null || picked.isEmpty || !mounted) return;
        selected = picked;
      }

      await facade.startDownload(prepared, selected);
      _snack('Download added.');
    } catch (e) {
      _snack('Could not add: $e', error: true);
    }
  }

  /// Best-effort human title from a pasted link (used until the engine
  /// resolves the real name).
  String _titleFromLink(String input) {
    final String lower = input.toLowerCase();
    if (lower.startsWith('magnet:')) {
      final RegExpMatch? dn =
          RegExp(r'[?&]dn=([^&]+)').firstMatch(input);
      if (dn != null) {
        final String dnValue = Uri.decodeComponent(dn.group(1)!);
        if (dnValue.trim().isNotEmpty) {
          return dnValue.replaceAll(RegExp(r'[._]'), ' ').trim();
        }
      }
      return 'Shared download';
    }
    if (lower.startsWith('http')) {
      final String file = input.split('/').last;
      return file
          .replaceAll(RegExp(r'\.(torrent|mp4|mkv|avi)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[._%20+]'), ' ')
          .trim();
    }
    return 'Shared download';
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger.withValues(alpha: 0.9) : null,
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});

  final TorrentTask task;

  /// Raw identifiers never appear in the UI — links and hashes collapse
  /// into a neutral label, release names get tidied up.
  String get _prettyName {
    final String name = task.displayName;
    if (name.startsWith('magnet:') ||
        RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(name)) {
      return 'Shared download';
    }
    // If the engine only resolved a technical name, tidy it up a little.
    if (name.length > 4 && RegExp(r'[._]').hasMatch(name)) {
      return name.replaceAll(RegExp(r'[._]'), ' ').trim();
    }
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<EngineFile> videos = task.videoFiles;
    final bool canWatch =
        videos.isNotEmpty && task.completedLength > 256 * 1024;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _prettyName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(status: task.status),
            ],
          ),
          if (task.qualityLabel != null) ...<Widget>[
            const SizedBox(height: 6),
            QualityBadge(label: task.qualityLabel!),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: task.progress),
              duration: const Duration(milliseconds: 400),
              builder: (BuildContext c, double v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: AppTheme.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  task.isComplete ? AppTheme.accentAlt : AppTheme.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(
                '${formatProgress(task.progress)} · '
                '${formatBytes(task.completedLength)} / ${formatBytes(task.totalLength)}',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              if (task.status == 'active') ...<Widget>[
                const Icon(Icons.arrow_downward_rounded,
                    size: 13, color: AppTheme.success),
                Text(
                  formatSpeed(task.downloadSpeed),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 10),
                Icon(Icons.people_alt_outlined,
                    size: 13, color: AppTheme.textSecondary),
                Text(
                  '${task.connections}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (canWatch)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: () => context.push(
                    '/player',
                    extra: PlayerArgs(
                      gid: task.gid,
                      fileIndex: videos.first.index,
                      title: _prettyName,
                      tmdbId: task.tmdbId,
                      posterUrl: task.posterUrl,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Watch now'),
                ),
              const Spacer(),
              IconButton(
                tooltip: task.status == 'paused' ? 'Resume' : 'Pause',
                icon: Icon(
                  task.status == 'paused'
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                onPressed: () async {
                  try {
                    final TorrentFacade facade =
                        await ref.read(engineReadyProvider.future);
                    if (task.status == 'paused') {
                      await facade.resumeTask(task.infoHash);
                    } else {
                      await facade.pauseTask(task.infoHash);
                    }
                  } catch (e) {
                    _error(context, '$e');
                  }
                },
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmRemove(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    bool deleteFiles = false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) setState) =>
            AlertDialog(
          title: const Text('Remove download?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_prettyName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (bool? v) =>
                    setState(() => deleteFiles = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete downloaded files'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final TorrentFacade facade = await ref.read(engineReadyProvider.future);
      await facade.removeTask(task.infoHash, deleteFiles: deleteFiles);
    } catch (e) {
      _error(context, '$e');
    }
  }

  void _error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger.withValues(alpha: 0.9),
      ),
    );
  }
}
