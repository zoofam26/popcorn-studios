import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../../domain/models.dart';
import '../providers/app_providers.dart';
import '../widgets/common.dart';
import '../widgets/quality_sheet.dart';

/// Movie details: backdrop hero, metadata, cast, similar titles and the
/// quality/source chooser that drives the download & stream flow.
class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MovieDetail> detail =
        ref.watch(movieDetailProvider(movieId));
    final bool wide = MediaQuery.sizeOf(context).width >= 750;

    return Scaffold(
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace s) => ErrorRetryView(
          message: 'Could not load this movie.\n$e',
          onRetry: () => ref.invalidate(movieDetailProvider(movieId)),
        ),
        data: (MovieDetail d) {
          final Movie movie = d.movie;
          return CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                expandedHeight: wide ? 420 : 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      NetworkArt(url: movie.backdropUrl),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                              Theme.of(context)
                                  .scaffoldBackgroundColor
                                  .withValues(alpha: 0.98),
                            ],
                            stops: const <double>[0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(<Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (wide && movie.posterUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 180,
                                height: 270,
                                child: NetworkArt(url: movie.posterUrl),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                movie.title,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                              if (d.tagline?.isNotEmpty ?? false)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    d.tagline!,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  if (movie.releaseYear > 0)
                                    _MetaText('${movie.releaseYear}'),
                                  _MetaText(formatRuntime(d.runtime)),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(Icons.star_rounded,
                                          size: 16, color: AppTheme.accentAlt),
                                      const SizedBox(width: 3),
                                      Text(
                                        movie.voteAverage.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  for (final Genre g in d.genres.take(3))
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceHigh,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        g.name,
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: <Widget>[
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _openQualitySheet(context, ref),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Watch / Download'),
                                  ),
                                  if (d.trailer != null)
                                    OutlinedButton.icon(
                                      onPressed: () => launchUrl(
                                        Uri.parse(
                                            'https://www.youtube.com/watch?v=${d.trailer!.key}'),
                                        mode: LaunchMode.externalApplication,
                                      ),
                                      icon: const Icon(Icons.movie_outlined),
                                      label: const Text('Trailer'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Overview',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      movie.overview?.isNotEmpty ?? false
                          ? movie.overview!
                          : 'No overview available.',
                      style: const TextStyle(
                        height: 1.55,
                        color: Color(0xFFC9CDD9),
                      ),
                    ),
                    if (d.cast.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 24),
                      const Text(
                        'Cast',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 128,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: d.cast.take(15).length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (BuildContext context, int index) {
                            final CastMember member = d.cast[index];
                            return SizedBox(
                              width: 76,
                              child: Column(
                                children: <Widget>[
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: AppTheme.surfaceHigh,
                                    backgroundImage: member.profileUrl.isEmpty
                                        ? null
                                        : CachedNetworkImageProvider(
                                            member.profileUrl),
                                    child: member.profileUrl.isEmpty
                                        ? const Icon(Icons.person,
                                            color: AppTheme.textSecondary)
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    member.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  if (member.character?.isNotEmpty ?? false)
                                    Text(
                                      member.character!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _QualitySection(movieId: movieId),
                    if (d.similar.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 26),
                      Text(
                        'More Like This',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 260,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: d.similar.take(14).length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (BuildContext context, int index) =>
                              PosterCard(movie: d.similar[index], width: 140),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openQualitySheet(BuildContext context, WidgetRef ref) {
    return showQualitySheet(context, ref, movieId);
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _QualitySection extends ConsumerWidget {
  const _QualitySection({required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<QualityOption>> options =
        ref.watch(qualityOptionsProvider(movieId));
    final bool stillSearching = options.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              'Available Sources',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (stillSearching)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Refresh sources',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => ref.invalidate(qualityOptionsProvider(movieId)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        options.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Searching sources…',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          error: (Object e, StackTrace s) => const _RailMessageInline(
            'Sources are unreachable right now. Check your connection and '
            'try again.',
          ),
          data: (List<QualityOption> list) {
            final Widget listWidget = list.isEmpty
                ? (stillSearching
                    ? const SizedBox.shrink()
                    : const _RailMessageInline(
                        'No sources found for this title yet. Try refreshing '
                        'in a moment.',
                      ))
                : Column(
                    children: <Widget>[
                      for (final QualityOption option in list)
                        _QualityTile(option: option, movieId: movieId),
                    ],
                  );
            if (!stillSearching || list.isEmpty) return listWidget;
            // Stremio-style: results already visible while more load in.
            return Column(
              children: <Widget>[
                listWidget,
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Searching more sources…',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QualityTile extends ConsumerWidget {
  const _QualityTile({required this.option, required this.movieId});

  final QualityOption option;
  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TorrentInfo t = option.best;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showQualityFlow(context, ref, t, movieId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: <Widget>[
              QualityBadge(label: option.label, fontSize: 13),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.sizeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SeedersChip(seeders: t.seeders),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailMessageInline extends StatelessWidget {
  const _RailMessageInline(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
      ),
    );
  }
}
