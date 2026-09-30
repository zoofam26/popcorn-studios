/// Central application constants: API endpoints, credentials, engine tuning.
class AppConstants {
  AppConstants._();

  // ── TMDB ────────────────────────────────────────────────────────────────
  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String tmdbBearerToken =
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI2N2Q3YWNmMTQ0ODRjYWUxNjNlMjc3YzI3ZDQzZjg4OSIsIm5iZiI6MTc4Mzk2ODExNy41NzUsInN1YiI6IjZhNTUzMTc1MzVhMzZiZDQzNjYxM2ZhZiIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.5I0UyZNLiVPeIfqg2cLOWylxyxNSvbGwaSGPAF88R8A';
  static const String tmdbApiKey = '67d7acf14484cae163e277c27d43f889';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';

  // ── OpenSubtitles ───────────────────────────────────────────────────────
  static const String openSubtitlesBaseUrl =
      'https://api.opensubtitles.com/api/v1';
  static const String openSubtitlesApiKey = 'tW8f2Of8mxchIgsx9VWOiNC9l0xyLY8K';
  static const String openSubtitlesUserAgent = 'PopcornStudio v1.0.0';

  // ── Torrent providers ───────────────────────────────────────────────────
  /// apibay.org is The Pirate Bay's official JSON API. It sits behind a
  /// Cloudflare rule that rejects non-browser user agents — a Chrome UA is
  /// enough to receive clean JSON (verified 2026-09).
  static const String apibayBaseUrl = 'https://apibay.org';
  static const String apibayUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// YTS hosts with automatic fail-over (mx is DNS-blocked in some regions).
  static const List<String> ytsBaseUrls = <String>[
    'https://yts.mx',
    'https://yts.am',
    'https://yts.lt',
    'https://yts.ag',
    'https://movies-api.accel.li',
  ];

  /// Fallback .torrent resolution for bare magnets (best effort).
  static const String itorrentsTemplate =
      'https://itorrents.org/torrent/%HASH%.torrent';

  // ── BitTorrent engine tuning ────────────────────────────────────────────
  /// aria2 is rarest-first by default; head/tail prioritisation is the lever
  /// that makes streaming start quickly (head covers MP4 moov / MKV index,
  /// tail covers MKV Cues / moov-at-end MP4s).
  static const String prioritizePiece = 'head=32M,tail=8M';

  /// Extra trackers merged into every magnet we build (improves peer
  /// discovery for magnets that ship with few or dead trackers).
  static const List<String> defaultTrackers = <String>[
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://opentracker.i2p.rocks:6969/announce',
    'http://tracker.files.fm:6969/announce',
    'http://open.acgnxtracker.com:80/announce',
    'udp://tracker.coppersurfer.tk:6969/announce',
    'udp://tracker.internetwarriors.net:1337/announce',
  ];

  /// Bytes buffered before playback starts (or before we hand bytes to the
  /// player when it seeks into undownloaded regions).
  static const int streamStartBufferBytes = 8 * 1024 * 1024;
  static const int streamStartBufferTimeoutSec = 20;
  static const int streamStallTimeoutSec = 60;
  static const int streamPollIntervalMs = 300;

  // ── File type classification ────────────────────────────────────────────
  static const Set<String> videoExtensions = <String>{
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'm4v',
    'ts',
    'mpg',
    'mpeg',
    'wmv',
    'flv',
    'ogv',
    '3gp',
    'm2ts',
    'divx',
  };
  static const Set<String> subtitleExtensions = <String>{
    'srt',
    'ass',
    'ssa',
    'vtt',
    'sub',
    'idx',
  };

  static const String appTitle = 'Popcorn Studio';
  static const String appVersion = '1.0.0';
}
