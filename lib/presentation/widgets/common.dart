import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/utils/format.dart';
import '../../domain/models.dart';
import '../../core/theme.dart';

/// Adaptive navigation scaffold: NavigationRail on wide desktop windows,
/// bottom NavigationBar on compact/mobile layouts.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const List<(String, IconData)> _destinations = <(String, IconData)>[
    ('Home', Icons.home_outlined),
    ('Search', Icons.search),
    ('Downloads', Icons.download_outlined),
    ('Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int index = shell.currentIndex;
    final bool wide = MediaQuery.sizeOf(context).width >= 1000;

    final Widget body = wide
        ? Row(
            children: <Widget>[
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (int i) => _go(shell, i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                destinations: <NavigationRailDestination>[
                  for (final (String, IconData) d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$2),
                      selectedIcon: Icon(d.$2, fill: 1),
                      label: Text(d.$1),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: shell),
            ],
          )
        : Scaffold(
            body: shell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (int i) => _go(shell, i),
              destinations: <Widget>[
                for (final (String, IconData) d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.$2),
                    selectedIcon: Icon(d.$2, fill: 1),
                    label: d.$1,
                  ),
              ],
            ),
          );

    return wide ? Scaffold(body: body) : body;
  }

  void _go(StatefulNavigationShell shell, int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalog artwork
// ─────────────────────────────────────────────────────────────────────────────

/// Cached network artwork with a disk-backed image cache — covers render
/// instantly after the first fetch (and across restarts), instead of
/// re-downloading on every screen visit.
class NetworkArt extends StatelessWidget {
  const NetworkArt({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.fallbackIcon = Icons.movie_outlined,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: AppTheme.textSecondary),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (BuildContext c, String u) => Container(
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (BuildContext c, String u, Object e) => Container(
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: AppTheme.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Poster cards & rails
// ─────────────────────────────────────────────────────────────────────────────

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.movie, this.width = 150});

  final Movie movie;
  final double width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/movie/${movie.id}'),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: movie.posterUrl.isEmpty
                    ? Container(
                        color: AppTheme.surfaceHigh,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          movie.title,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : NetworkArt(
                        url: movie.posterUrlW342,
                        memCacheWidth: 400,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: <Widget>[
                if (movie.releaseYear > 0)
                  Text(
                    '${movie.releaseYear}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                const Spacer(),
                Icon(Icons.star_rounded, size: 13, color: AppTheme.accentAlt),
                Text(
                  movie.voteAverage.toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal Netflix-style content rail with a heading.
class ContentRail extends StatelessWidget {
  const ContentRail({
    super.key,
    required this.title,
    required this.snapshot,
    this.posterWidth = 150,
  });

  final String title;
  final AsyncValue<List<Movie>> snapshot;
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        snapshot.when(
          data: (List<Movie> data) => SizedBox(
            height: posterWidth / 2 * 3 + 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: data.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) =>
                  PosterCard(movie: data[index], width: posterWidth),
            ),
          ),
          error: (Object error, StackTrace stackTrace) => _RailMessage(
            'Could not load "$title". Check your connection.',
            onRetry: null,
          ),
          loading: () => SizedBox(
            height: posterWidth / 2 * 3 + 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) => Container(
                width: posterWidth,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailMessage extends StatelessWidget {
  const _RailMessage(this.message, {this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared UI atoms
// ─────────────────────────────────────────────────────────────────────────────

class SeedersChip extends StatelessWidget {
  const SeedersChip({super.key, required this.seeders});

  final int seeders;

  @override
  Widget build(BuildContext context) {
    final Color color = seeders >= 50
        ? AppTheme.success
        : seeders >= 5
            ? AppTheme.warning
            : AppTheme.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.arrow_upward_rounded, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          formatCompact(seeders),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.label, this.fontSize = 12});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accentAlt, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.accentAlt,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Rounded status pill used across the Downloads and Player screens.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      'active' => (AppTheme.success, 'Downloading'),
      'paused' => (AppTheme.warning, 'Paused'),
      'complete' => (AppTheme.accentAlt, 'Complete'),
      'waiting' => (AppTheme.textSecondary, 'Queued'),
      'error' => (AppTheme.danger, 'Error'),
      'offline' => (AppTheme.danger, 'Engine offline'),
      _ => (AppTheme.textSecondary, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Global error/empty-state view with retry.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                size: 44, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Streams a video through the local engine server if available, otherwise
/// plays a local file directly (used when a task has completed).
bool isDesktopPlatform() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

String appTitle() => AppConstants.appTitle;
