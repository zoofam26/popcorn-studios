import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/platform_bindings.dart';
import '../../data/platform_info.dart';
import '../../data/settings_store.dart';
import '../../data/tmdb_service.dart';
import '../../data/torrent_search_service.dart';
import '../../data/opensubtitles_service.dart';
import '../../domain/models.dart';
import '../../engine/engine_manager.dart';
import '../../engine/torrent_facade.dart';
import '../screens/details_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/home_screen.dart';
import '../screens/player_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/common.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Services
// ─────────────────────────────────────────────────────────────────────────────

final Provider<TmdbService> tmdbServiceProvider =
    Provider<TmdbService>((Ref ref) => TmdbService());

final Provider<TorrentSearchService> torrentSearchProvider =
    Provider<TorrentSearchService>((Ref ref) => TorrentSearchService());

final Provider<OpenSubtitlesService> openSubtitlesProvider =
    Provider<OpenSubtitlesService>((Ref ref) => OpenSubtitlesService());

final Provider<SettingsStore> settingsStoreProvider =
    Provider<SettingsStore>((Ref ref) => SettingsStore());

// ─────────────────────────────────────────────────────────────────────────────
// Engine bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Boots the engine exactly once; screens await [engineReadyProvider].
final FutureProvider<TorrentFacade> engineReadyProvider =
    FutureProvider<TorrentFacade>((Ref ref) async {
  final PlatformBindings bindings = PlatformBindings();
  final String? nativeLibDir = await bindings.nativeLibraryDir();

  final EnginePaths paths = await buildEnginePaths(
    nativeLibraryDir: nativeLibDir,
  );
  final Aria2Engine engine = Aria2Engine(paths: paths);
  final TorrentFacade facade = TorrentFacade(
    engine: engine,
    taskStore: SharedPrefsTaskStore(),
  );

  final AppSettings settings = await ref.read(settingsStoreProvider).load();
  await facade.start(
    maxOverallDownloadLimit: settings.maxOverallSpeedBytesPerSec <= 0
        ? '0'
        : '${settings.maxOverallSpeedBytesPerSec}',
    seedRatio: settings.seedRatio.toStringAsFixed(2),
  );
  ref.onDispose(() {
    facade.stop();
  });
  return facade;
});

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    state = await ref.read(settingsStoreProvider).load();
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsStoreProvider).save(next);
    // Apply live engine limits when the engine is already running.
    final TorrentFacade? facade = ref.watch(engineReadyProvider).value;
    if (facade != null) {
      await facade.rpc.changeGlobalOption(<String, String>{
        'max-overall-download-limit': next.maxOverallSpeedBytesPerSec <= 0
            ? '0'
            : '${next.maxOverallSpeedBytesPerSec}',
        'seed-ratio': next.seedRatio.toStringAsFixed(2),
      });
    }
  }
}

final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Catalog
// ─────────────────────────────────────────────────────────────────────────────

final FutureProvider<List<Movie>> trendingProvider =
    FutureProvider<List<Movie>>(
        (Ref ref) => ref.watch(tmdbServiceProvider).trending());

final FutureProvider<List<Movie>> popularProvider = FutureProvider<List<Movie>>(
    (Ref ref) => ref.watch(tmdbServiceProvider).popular());

final FutureProvider<List<Movie>> topRatedProvider =
    FutureProvider<List<Movie>>(
        (Ref ref) => ref.watch(tmdbServiceProvider).topRated());

final FutureProvider<List<Movie>> nowPlayingProvider =
    FutureProvider<List<Movie>>(
        (Ref ref) => ref.watch(tmdbServiceProvider).nowPlaying());

final searchProvider = FutureProvider.family<List<Movie>, String>(
    (Ref ref, String query) => ref.watch(tmdbServiceProvider).search(query));

final movieDetailProvider = FutureProvider.family<MovieDetail, int>(
    (Ref ref, int id) => ref.watch(tmdbServiceProvider).movieDetail(id));

/// Quality options for the details screen — depends on the resolved movie
/// (title/year/imdb).
final qualityOptionsProvider =
    FutureProvider.family<List<QualityOption>, int>((Ref ref, int id) async {
  final MovieDetail detail = await ref.watch(movieDetailProvider(id).future);
  return ref.watch(torrentSearchProvider).findOptionsForMovie(
        title: detail.movie.title,
        year: detail.movie.releaseYear,
        imdbId: detail.imdbId,
      );
});

/// Subtitles for a movie (player).
final subtitlesForMovieProvider =
    FutureProvider.family<List<SubtitleSearchResult>, int>(
        (Ref ref, int tmdbId) async {
  final AppSettings settings = ref.watch(settingsProvider);
  return ref
      .watch(openSubtitlesProvider)
      .search(tmdbId: tmdbId, languages: settings.subtitleLanguages);
});

// ─────────────────────────────────────────────────────────────────────────────
// Downloads
// ─────────────────────────────────────────────────────────────────────────────

final StreamProvider<List<TorrentTask>> tasksProvider =
    StreamProvider<List<TorrentTask>>((Ref ref) async* {
  final TorrentFacade facade = await ref.watch(engineReadyProvider.future);
  yield* facade.tasksStream;
});

final FutureProvider<GlobalStats> globalStatsProvider =
    FutureProvider<GlobalStats>((Ref ref) async {
  final TorrentFacade facade = await ref.watch(engineReadyProvider.future);
  return facade.globalStats();
});

// ─────────────────────────────────────────────────────────────────────────────
// Router
// ─────────────────────────────────────────────────────────────────────────────

class PlayerArgs {
  const PlayerArgs({
    required this.gid,
    required this.fileIndex,
    required this.title,
    this.tmdbId,
    this.posterUrl,
  });

  final String gid;
  final int fileIndex;
  final String title;
  final int? tmdbId;
  final String? posterUrl;
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
                StatefulNavigationShell shell) =>
            AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                builder: (BuildContext context, GoRouterState state) =>
                    const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/downloads',
                builder: (BuildContext context, GoRouterState state) =>
                    const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/movie/:id',
        builder: (BuildContext context, GoRouterState state) => DetailsScreen(
          movieId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (BuildContext context, GoRouterState state) {
          final PlayerArgs? args = state.extra as PlayerArgs?;
          return PlayerScreen(args: args);
        },
      ),
    ],
  );
});
