import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../domain/models.dart';

/// Lists every video file inside a source bundle so the user can choose
/// what to download/stream (multi-video bundles, collections, etc).
class VideoPickerSheet extends StatefulWidget {
  const VideoPickerSheet({super.key, required this.videos});

  final List<EngineFile> videos;

  @override
  State<VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<VideoPickerSheet> {
  late final Map<int, bool> _selected = <int, bool>{
    // Preselect the largest video (usually the main feature).
    for (final EngineFile video in _sorted)
      video.index: video.index == _sorted.first.index,
  };

  List<EngineFile> get _sorted => widget.videos.toList()
    ..sort((EngineFile a, EngineFile b) => b.length.compareTo(a.length));

  int get _selectedCount => _selected.values.where((bool v) => v).length;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Videos in this source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'This source contains ${widget.videos.length} videos. '
              'Pick what you want to stream or download.',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12.5),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _sorted.length,
              itemBuilder: (BuildContext context, int index) {
                final EngineFile video = _sorted[index];
                return CheckboxListTile(
                  value: _selected[video.index] ?? false,
                  onChanged: (bool? value) =>
                      setState(() => _selected[video.index] = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    video.prettyName.isEmpty
                        ? video.fileName
                        : video.prettyName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    formatBytes(video.length),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                  secondary: const Icon(Icons.movie_outlined, size: 20),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _selectedCount == 0
                        ? null
                        : () => Navigator.of(context).pop(_selectedIndexes()),
                    child: const Text('Download Only'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selectedCount == 0
                        ? null
                        : () => Navigator.of(context).pop(_selectedIndexes()),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Stream ($_selectedCount)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<int> _selectedIndexes() => _selected.entries
      .where((MapEntry<int, bool> e) => e.value)
      .map((MapEntry<int, bool> e) => e.key)
      .toList();
}
