import '../../core/constants.dart';
import '../../core/utils/format.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Catalog models (TMDB)
// ─────────────────────────────────────────────────────────────────────────────

class Genre {
  const Genre({required this.id, required this.name});

  final int id;
  final String name;

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
      );
}

class CastMember {
  const CastMember({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });

  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  String get profileUrl => profilePath == null
      ? ''
      : '${AppConstants.tmdbImageBase}/w185$profilePath';

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        character: json['character'] as String?,
        profilePath: json['profile_path'] as String?,
      );
}

class MovieVideo {
  const MovieVideo({
    required this.key,
    required this.site,
    required this.type,
    required this.name,
  });

  final String key;
  final String site;
  final String type;
  final String name;

  bool get isYouTubeTrailer =>
      site == 'YouTube' && (type == 'Trailer' || type == 'Teaser');

  factory MovieVideo.fromJson(Map<String, dynamic> json) => MovieVideo(
        key: (json['key'] as String?) ?? '',
        site: (json['site'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );
}

class Movie {
  const Movie({
    required this.id,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage = 0,
    this.genreIds = const <int>[],
  });

  final int id;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final List<int> genreIds;

  int get releaseYear {
    final String? date = releaseDate;
    if (date == null || date.length < 4) return 0;
    return int.tryParse(date.substring(0, 4)) ?? 0;
  }

  String get posterUrl =>
      posterPath == null ? '' : '${AppConstants.tmdbImageBase}/w500$posterPath';

  /// Lighter poster variant for cards/rails — faster to fetch in bulk.
  String get posterUrlW342 => posterPath == null
      ? ''
      : '${AppConstants.tmdbImageBase}/w342$posterPath';

  String get backdropUrl => backdropPath == null
      ? ''
      : '${AppConstants.tmdbImageBase}/w1280$backdropPath';

  static Movie fromJson(Map<String, dynamic> json) => Movie(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? (json['name'] as String?) ?? '',
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate: (json['release_date'] as String?) ??
            json['first_air_date'] as String?,
        voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
        genreIds: ((json['genre_ids'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => (e as num).toInt())
            .toList(),
      );
}

class MovieDetail {
  const MovieDetail({
    required this.movie,
    this.runtime,
    this.tagline,
    this.imdbId,
    this.genres = const <Genre>[],
    this.cast = const <CastMember>[],
    this.similar = const <Movie>[],
    this.videos = const <MovieVideo>[],
  });

  final Movie movie;
  final int? runtime;
  final String? tagline;
  final String? imdbId;
  final List<Genre> genres;
  final List<CastMember> cast;
  final List<Movie> similar;
  final List<MovieVideo> videos;

  MovieVideo? get trailer => videos.cast<MovieVideo?>().firstWhere(
        (MovieVideo? v) => v?.isYouTubeTrailer ?? false,
        orElse: () => null,
      );

  static MovieDetail fromJson(Map<String, dynamic> json) {
    final Movie movie = Movie.fromJson(json);
    final Map<String, dynamic> credits =
        (json['credits'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> videosJson =
        (json['videos'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> similarJson =
        (json['similar'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> externalIds =
        (json['external_ids'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return MovieDetail(
      movie: movie,
      runtime: (json['runtime'] as num?)?.toInt(),
      tagline: json['tagline'] as String?,
      imdbId: externalIds['imdb_id'] as String? ?? json['imdb_id'] as String?,
      genres: ((json['genres'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => Genre.fromJson(e as Map<String, dynamic>))
          .toList(),
      cast: ((credits['cast'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => CastMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      similar: ((similarJson['results'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList(),
      videos: ((videosJson['results'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => MovieVideo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Torrent models
// ─────────────────────────────────────────────────────────────────────────────

enum TorrentSource { torrentio, yts, apibay, piratebayApi, manual }

extension TorrentSourceX on TorrentSource {
  String get label => switch (this) {
        TorrentSource.torrentio => 'Torrentio',
        TorrentSource.yts => 'YTS',
        TorrentSource.apibay => 'ThePirateBay',
        TorrentSource.piratebayApi => 'PirateBay API',
        TorrentSource.manual => 'Manual',
      };
}

class TorrentInfo {
  const TorrentInfo({
    required this.infoHash,
    required this.name,
    required this.sizeBytes,
    required this.seeders,
    required this.leechers,
    required this.source,
    this.magnetUri,
    this.torrentUrl,
    this.fileIdx,
    this.videoFileName,
    this.tpbNumericId,
    this.quality,
    this.uploadedAt,
    this.imdbId,
  });

  final String infoHash;
  final String name;
  final int sizeBytes;
  final int seeders;
  final int leechers;
  final TorrentSource source;
  final String? magnetUri;
  final String? torrentUrl;

  /// Zero-based index of the video file inside the bundle, when the source
  /// provides it (Stremio-style stream addons do).
  final int? fileIdx;

  /// Exact video file name inside the bundle, when the source provides it.
  final String? videoFileName;

  /// Numeric PirateBay torrent id (enables the apibay f.php file list API).
  final int? tpbNumericId;

  /// Detected resolution tag such as `1080p`, if present in the name.
  final String? quality;
  final DateTime? uploadedAt;
  final String? imdbId;

  String get sizeLabel => formatBytes(sizeBytes);
}

/// A quality-resolved download choice shown in the details screen.
class QualityOption {
  const QualityOption({required this.label, required this.best});

  final String label;
  final TorrentInfo best;

  String get sizeLabel => best.sizeLabel;
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine models
// ─────────────────────────────────────────────────────────────────────────────

class EngineFile {
  const EngineFile({
    required this.index,
    required this.path,
    required this.length,
    required this.completedLength,
    required this.selected,
  });

  /// aria2 file index, 1-based.
  final int index;
  final String path;
  final int length;
  final int completedLength;
  final bool selected;

  String get fileName {
    final String normalized = path.replaceAll('\\', '/');
    return normalized.contains('/') ? normalized.split('/').last : normalized;
  }

  String get extension =>
      fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  bool get isVideo => AppConstants.videoExtensions.contains(extension);
  bool get isSubtitle => AppConstants.subtitleExtensions.contains(extension);

  /// Presentation-friendly name: release tags and separators cleaned up.
  String get prettyName {
    String base = fileName.isEmpty ? '' : fileName;
    if (base.contains('.')) {
      final String ext = base.split('.').last;
      if (ext.length <= 4) base = base.substring(0, base.length - ext.length - 1);
    }
    return base
        .replaceAll(RegExp(r'[._]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class TorrentTask {
  const TorrentTask({
    required this.gid,
    required this.infoHash,
    required this.displayName,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.connections,
    required this.files,
    required this.downloadDir,
    this.tmdbId,
    this.posterUrl,
    this.qualityLabel,
  });

  final String gid;
  final String infoHash;
  final String displayName;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final int connections;
  final List<EngineFile> files;
  final String downloadDir;
  final int? tmdbId;
  final String? posterUrl;
  final String? qualityLabel;

  bool get isComplete =>
      status == 'complete' ||
      (totalLength > 0 && completedLength >= totalLength);

  double get progress =>
      totalLength <= 0 ? 0 : (completedLength / totalLength).clamp(0.0, 1.0);

  List<EngineFile> get videoFiles =>
      files.where((EngineFile f) => f.isVideo).toList(growable: false);

  List<EngineFile> get subtitleFiles =>
      files.where((EngineFile f) => f.isSubtitle).toList(growable: false);
}

class GlobalStats {
  const GlobalStats({
    required this.active,
    required this.waiting,
    required this.stopped,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });

  final int active;
  final int waiting;
  final int stopped;
  final int downloadSpeed;
  final int uploadSpeed;

  static const GlobalStats empty = GlobalStats(
    active: 0,
    waiting: 0,
    stopped: 0,
    downloadSpeed: 0,
    uploadSpeed: 0,
  );
}

class PreparedTorrent {
  const PreparedTorrent({
    required this.placeholderGid,
    required this.infoHash,
    required this.displayName,
    required this.downloadDir,
    required this.files,
    required this.torrentFilePath,
    required this.torrentBytes,
    this.tmdbId,
    this.posterUrl,
    this.qualityLabel,
  });

  /// GID of the paused placeholder download (removed when the real download
  /// starts with file selection applied).
  final String placeholderGid;
  final String infoHash;
  final String displayName;
  final String downloadDir;
  final List<EngineFile> files;
  final String torrentFilePath;
  final List<int> torrentBytes;
  final int? tmdbId;
  final String? posterUrl;
  final String? qualityLabel;

  List<EngineFile> get videoFiles => files
      .where((EngineFile f) => f.isVideo && f.length > 0)
      .toList(growable: false);

  List<EngineFile> get subtitleFiles =>
      files.where((EngineFile f) => f.isSubtitle).toList(growable: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Subtitles
// ─────────────────────────────────────────────────────────────────────────────

class SubtitleSearchResult {
  const SubtitleSearchResult({
    required this.fileId,
    required this.language,
    this.release,
    this.format,
    required this.fileName,
    this.hd = false,
    this.downloadCount = 0,
  });

  final int fileId;
  final String language;
  final String? release;
  final String? format;
  final String fileName;
  final bool hd;
  final int downloadCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

class AppSettings {
  const AppSettings({
    this.subtitleLanguages = const <String>['en'],
    this.maxOverallSpeedBytesPerSec = 0,
    this.seedRatio = 0,
    this.autoStartPlayback = true,
    this.headPrioritize = AppConstants.prioritizePiece,
  });

  final List<String> subtitleLanguages;

  /// Global download cap in bytes/sec, `0` = unlimited.
  final int maxOverallSpeedBytesPerSec;

  /// Seed ratio target after completion, `0` = stop immediately.
  final double seedRatio;

  final bool autoStartPlayback;
  final String headPrioritize;

  AppSettings copyWith({
    List<String>? subtitleLanguages,
    int? maxOverallSpeedBytesPerSec,
    double? seedRatio,
    bool? autoStartPlayback,
    String? headPrioritize,
  }) =>
      AppSettings(
        subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
        maxOverallSpeedBytesPerSec:
            maxOverallSpeedBytesPerSec ?? this.maxOverallSpeedBytesPerSec,
        seedRatio: seedRatio ?? this.seedRatio,
        autoStartPlayback: autoStartPlayback ?? this.autoStartPlayback,
        headPrioritize: headPrioritize ?? this.headPrioritize,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subtitleLanguages': subtitleLanguages,
        'maxOverallSpeedBytesPerSec': maxOverallSpeedBytesPerSec,
        'seedRatio': seedRatio,
        'autoStartPlayback': autoStartPlayback,
        'headPrioritize': headPrioritize,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        subtitleLanguages: ((json['subtitleLanguages'] as List<dynamic>?) ??
                const <dynamic>['en'])
            .map((dynamic e) => e as String)
            .toList(),
        maxOverallSpeedBytesPerSec:
            (json['maxOverallSpeedBytesPerSec'] as num?)?.toInt() ?? 0,
        seedRatio: (json['seedRatio'] as num?)?.toDouble() ?? 0,
        autoStartPlayback: json['autoStartPlayback'] as bool? ?? true,
        headPrioritize:
            json['headPrioritize'] as String? ?? AppConstants.prioritizePiece,
      );
}

/// A persisted download task so the library survives app restarts.
class TaskRecord {
  const TaskRecord({
    required this.infoHash,
    required this.displayName,
    required this.downloadDir,
    required this.selectedFileIndexes,
    required this.filePaths,
    required this.torrentFilePath,
    required this.addedAtMs,
    this.gid = '',
    this.tmdbId,
    this.posterUrl,
    this.qualityLabel,
    this.totalBytes = 0,
  });

  final String gid;
  final String infoHash;
  final String displayName;
  final String downloadDir;
  final List<int> selectedFileIndexes;
  final List<String> filePaths;
  final String torrentFilePath;
  final int addedAtMs;
  final int? tmdbId;
  final String? posterUrl;
  final String? qualityLabel;
  final int totalBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'gid': gid,
        'infoHash': infoHash,
        'displayName': displayName,
        'downloadDir': downloadDir,
        'selectedFileIndexes': selectedFileIndexes,
        'filePaths': filePaths,
        'torrentFilePath': torrentFilePath,
        'addedAtMs': addedAtMs,
        'tmdbId': tmdbId,
        'posterUrl': posterUrl,
        'qualityLabel': qualityLabel,
        'totalBytes': totalBytes,
      };

  static TaskRecord fromJson(Map<String, dynamic> json) => TaskRecord(
        gid: (json['gid'] as String?) ?? '',
        infoHash: (json['infoHash'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        downloadDir: (json['downloadDir'] as String?) ?? '',
        selectedFileIndexes: ((json['selectedFileIndexes'] as List<dynamic>?) ??
                const <dynamic>[])
            .map((dynamic e) => (e as num).toInt())
            .toList(),
        filePaths: ((json['filePaths'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e as String)
            .toList(),
        torrentFilePath: (json['torrentFilePath'] as String?) ?? '',
        addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
        tmdbId: (json['tmdbId'] as num?)?.toInt(),
        posterUrl: json['posterUrl'] as String?,
        qualityLabel: json['qualityLabel'] as String?,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      );
}
