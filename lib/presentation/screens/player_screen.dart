import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../domain/models.dart';
import '../providers/app_providers.dart';
import '../widgets/common.dart';
import '../../engine/torrent_facade.dart';

/// Full-screen player.
///
/// Streams through the local engine HTTP server so playback works while the
/// torrent is still downloading. The overlay shows live download progress,
/// buffered range, and subtitle selection (embedded + OpenSubtitles).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerArgs? args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Player? _player;
  VideoController? _controller;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _buffering = true;

  final List<SubtitleOption> _subtitleOptions = <SubtitleOption>[];
  SubtitleOption? _activeSubtitle;

  PlayerArgs? get _args => widget.args;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_init);
  }

  Future<void> _init() async {
    final PlayerArgs? args = _args;
    if (args == null) return;
    final TorrentFacade facade;
    try {
      facade = await ref.read(engineReadyProvider.future);
    } catch (e) {
      _showSnack('Engine unavailable: $e');
      return;
    }

    final Player player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 96 * 1024 * 1024,
        osc: false,
      ),
    );
    if (!mounted) {
      await player.dispose();
      return;
    }
    _player = player;
    _controller = VideoController(player);

    player.stream.position.listen((Duration p) {
      if (mounted) setState(() => _position = p);
    });
    player.stream.duration.listen((Duration d) {
      if (mounted) setState(() => _duration = d);
    });
    player.stream.buffer.listen((Duration b) {
      if (mounted) setState(() => _buffer = b);
    });
    player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _buffering = b);
    });
    player.stream.error.listen((String e) {
      if (e.isNotEmpty) _showSnack('Playback error: $e');
    });

    final Uri streamUri =
        facade.streamServer.videoUri(args.gid, args.fileIndex);
    await player.open(Media(streamUri.toString()));

    await _loadSubtitles(facade, args);
    _scheduleHide();
  }

  Future<void> _loadSubtitles(
    TorrentFacade facade,
    PlayerArgs args,
  ) async {
    // 1) Embedded subtitles that were selected with the torrent.
    try {
      final List<EngineFile> files = await facade.engineFiles(args.gid);
      for (final EngineFile file in files) {
        if (!file.isSubtitle || file.length <= 0) continue;
        final String url = facade.streamServer.registerStaticFile(file.path);
        _addSubtitleOption(
          SubtitleOption(
            track: SubtitleTrack.uri(url, title: file.fileName),
            label: file.fileName,
            origin: 'Embedded',
          ),
        );
      }
    } catch (_) {}

    // 2) OpenSubtitles when the movie is known.
    if (args.tmdbId != null) {
      try {
        final List<SubtitleSearchResult> results =
            await ref.read(subtitlesForMovieProvider(args.tmdbId!).future);
        final int limit = results.length < 3 ? results.length : 3;
        for (int i = 0; i < limit; i++) {
          final SubtitleSearchResult result = results[i];
          try {
            final String dir = facade.subtitleCacheDir(args.gid);
            final String path = await ref
                .read(openSubtitlesProvider)
                .downloadSubtitle(result, dir);
            final String url = facade.streamServer.registerStaticFile(path);
            _addSubtitleOption(
              SubtitleOption(
                track: SubtitleTrack.uri(url,
                    title:
                        '${result.language.toUpperCase()} · ${result.release ?? result.fileName}'),
                label:
                    '${result.language.toUpperCase()} · ${result.release ?? result.fileName}',
                origin: 'OpenSubtitles',
              ),
            );
          } catch (_) {
            // Quota exhausted or network hiccup — skip this one.
          }
        }
      } catch (_) {}
    }
  }

  void _addSubtitleOption(SubtitleOption option) {
    if (!mounted) return;
    setState(() => _subtitleOptions.add(option));
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktopPlatform()) {
      SystemChrome.setEnabledSystemUIMode(
        _fullscreen ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
      setState(() => _fullscreen = !_fullscreen);
      return;
    }
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _pickSubtitle() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Subtitles',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: Icon(
                Icons.subtitles_off_outlined,
                color: _activeSubtitle == null ? AppTheme.accent : null,
              ),
              title: const Text('Off'),
              onTap: () {
                _player?.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(sheetContext);
                setState(() => _activeSubtitle = null);
              },
            ),
            for (final SubtitleOption option in _subtitleOptions)
              ListTile(
                leading: Icon(
                  option.origin == 'OpenSubtitles'
                      ? Icons.cloud_download_outlined
                      : Icons.subtitles_outlined,
                  color: _activeSubtitle == option ? AppTheme.accent : null,
                ),
                title: Text(option.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text(option.origin, style: const TextStyle(fontSize: 11)),
                onTap: () {
                  _player?.setSubtitleTrack(option.track);
                  Navigator.pop(sheetContext);
                  setState(() => _activeSubtitle = option);
                },
              ),
            if (_subtitleOptions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No subtitles found yet. Torrent-embedded and OpenSubtitles '
                  'tracks appear here automatically.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSpeed() async {
    const List<double> speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Playback speed',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final double s in speeds)
              ListTile(
                title: Text('${s}x'),
                onTap: () {
                  _player?.setRate(s);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player?.dispose();
    if (isDesktopPlatform() && _fullscreen) {
      windowManager.setFullScreen(false);
    }
    if (!isDesktopPlatform()) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerArgs? args = _args;
    final VideoController? controller = _controller;

    if (args == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const ErrorRetryView(message: 'Nothing to play.'),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Video(controller: controller, controls: _noControls),
                // Tap surface for controls toggle.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                  ),
                ),
                _buildOverlay(args),
              ],
            ),
    );
  }

  Widget _buildOverlay(PlayerArgs args) {
    final TorrentTask? task = _findTask(args.gid);
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Column(
          children: <Widget>[
            // ── Top bar ────────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            args.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              shadows: <Shadow>[
                                Shadow(blurRadius: 8, color: Colors.black),
                              ],
                            ),
                          ),
                          if (task != null && !task.isComplete)
                            Text(
                              'Streaming while downloading · '
                              '${formatProgress(task.progress)} · '
                              '${formatSpeed(task.downloadSpeed)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.accentAlt,
                                shadows: const <Shadow>[
                                  Shadow(blurRadius: 6, color: Colors.black),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // ── Center controls ────────────────────────────────────────
            if (_buffering)
              const Column(
                children: <Widget>[
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Buffering…',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  SizedBox(height: 18),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: () => _player?.seek(
                    _position - const Duration(seconds: 10),
                  ),
                ),
                const SizedBox(width: 18),
                IconButton(
                  iconSize: 60,
                  icon: Icon(
                    _player?.state.playing ?? false
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: () {
                    final Player? player = _player;
                    if (player == null) return;
                    player.state.playing ? player.pause() : player.play();
                  },
                ),
                const SizedBox(width: 18),
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.forward_10_rounded),
                  onPressed: () => _player?.seek(
                    _position + const Duration(seconds: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Bottom bar ─────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: <Widget>[
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: _position.inMilliseconds
                            .clamp(
                                0,
                                _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds
                                    : 1)
                            .toDouble(),
                        max: _duration.inMilliseconds > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 1,
                        secondaryTrackValue: _buffer.inMilliseconds
                            .clamp(
                                0,
                                _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds
                                    : 1)
                            .toDouble(),
                        onChanged: (double v) =>
                            _player?.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Text(
                          formatDuration(_position.inMilliseconds),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '  /  ${formatDuration(_duration.inMilliseconds)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Subtitles',
                          icon: const Icon(Icons.subtitles_outlined),
                          onPressed: _pickSubtitle,
                        ),
                        IconButton(
                          tooltip: 'Speed',
                          icon: const Icon(Icons.speed_outlined),
                          onPressed: _pickSpeed,
                        ),
                        IconButton(
                          tooltip: 'Fullscreen',
                          icon: Icon(_fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen),
                          onPressed: _toggleFullscreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TorrentTask? _findTask(String gid) {
    final AsyncValue<List<TorrentTask>> tasks = ref.watch(tasksProvider);
    for (final TorrentTask task in tasks.value ?? const <TorrentTask>[]) {
      if (task.gid == gid) return task;
    }
    return null;
  }
}

class SubtitleOption {
  const SubtitleOption({
    required this.track,
    required this.label,
    required this.origin,
  });

  final SubtitleTrack track;
  final String label;
  final String origin;
}

/// Disables media_kit's built-in controls — Popcorn Studio renders its own
/// overlay on top of the video surface.
Widget _noControls(VideoState state) => const SizedBox.shrink();
