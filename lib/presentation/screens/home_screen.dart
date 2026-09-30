import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../providers/app_providers.dart';
import '../widgets/common.dart';

/// Netflix-style home: auto-rotating hero banner followed by content rails.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _heroTimer;
  final PageController _heroController = PageController();
  bool _rotationStarted = false;

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  void _startHeroRotation(int length) {
    if (_rotationStarted) return;
    _rotationStarted = true;
    if (length <= 1) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (Timer _) {
      if (!_heroController.hasClients || !mounted) return;
      final int next = (_heroController.page?.round() ?? 0) + 1;
      _heroController.animateToPage(
        next >= length ? 0 : next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Movie>> trending = ref.watch(trendingProvider);
    final bool wide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _BrandTitle(fontSize: 19),
        actions: <Widget>[
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(trendingProvider);
          ref.invalidate(popularProvider);
          ref.invalidate(topRatedProvider);
          ref.invalidate(nowPlayingProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            _HeroBanner(
              snapshot: trending,
              controller: _heroController,
              onFirstData: _startHeroRotation,
              wide: wide,
            ),
            ContentRail(
              title: 'Trending Now',
              snapshot: trending,
              posterWidth: wide ? 168 : 140,
            ),
            ContentRail(
              title: 'Popular on Popcorn Studio',
              snapshot: ref.watch(popularProvider),
              posterWidth: wide ? 168 : 140,
            ),
            ContentRail(
              title: 'Top Rated',
              snapshot: ref.watch(topRatedProvider),
              posterWidth: wide ? 168 : 140,
            ),
            ContentRail(
              title: 'In Theaters',
              snapshot: ref.watch(nowPlayingProvider),
              posterWidth: wide ? 168 : 140,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: AppTheme.textPrimary,
        ),
        children: const <TextSpan>[
          TextSpan(text: 'POPCORN'),
          TextSpan(text: ' STUDIO', style: TextStyle(color: AppTheme.accent)),
        ],
      ),
    );
  }
}

class _HeroBanner extends ConsumerWidget {
  const _HeroBanner({
    required this.snapshot,
    required this.controller,
    required this.onFirstData,
    required this.wide,
  });

  final AsyncValue<List<Movie>> snapshot;
  final PageController controller;
  final ValueChanged<int> onFirstData;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return snapshot.when(
      data: (List<Movie> movies) {
        final List<Movie> heroes = movies
            .where((Movie m) => m.backdropUrl.isNotEmpty)
            .take(5)
            .toList();
        if (heroes.isEmpty) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onFirstData(heroes.length);
        });
        return SizedBox(
          height: wide ? 430 : 350,
          child: PageView.builder(
            controller: controller,
            itemCount: heroes.length,
            itemBuilder: (BuildContext context, int index) =>
                _HeroSlide(movie: heroes[index], wide: wide),
          ),
        );
      },
      loading: () => Container(
        height: 350,
        color: AppTheme.surface,
      ),
      error: (Object e, StackTrace s) => const SizedBox(height: 0),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.movie, required this.wide});

  final Movie movie;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/movie/${movie.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.network(
            movie.backdropUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppTheme.surface),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.25),
                  Theme.of(context)
                      .scaffoldBackgroundColor
                      .withValues(alpha: 0.96),
                ],
                stops: const <double>[0.45, 0.72, 1.0],
              ),
            ),
          ),
          Positioned(
            left: wide ? 40 : 20,
            right: wide ? 40 : 20,
            bottom: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movie.title,
                  style: TextStyle(
                    fontSize: wide ? 34 : 25,
                    fontWeight: FontWeight.w900,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 14, color: Colors.black45),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(Icons.star_rounded,
                        size: 17, color: AppTheme.accentAlt),
                    const SizedBox(width: 4),
                    Text(
                      movie.voteAverage.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (movie.releaseYear > 0) ...<Widget>[
                      const SizedBox(width: 10),
                      Text(
                        '${movie.releaseYear}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    const Text(
                      'HD',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/movie/${movie.id}'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Watch Now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
