/// Parses release names such as
/// `Interstellar.2014.2014.1080p.BluRay.x264.YIFY.mp4` into a clean title,
/// year and quality tag so torrents from different providers can be grouped
/// into per-quality download options.
class ParsedRelease {
  const ParsedRelease({
    required this.cleanTitle,
    this.year,
    this.quality,
  });

  final String cleanTitle;
  final int? year;
  final String? quality;
}

/// Scene tag dictionary — tokens ignored when deriving the clean title.
const Set<String> _junkTokens = <String>{
  'x264',
  'x265',
  'xvid',
  'divx',
  'webdl',
  'web',
  'webrip',
  'dl',
  'web-dl',
  'brrip',
  'bluray',
  'blu-ray',
  'bdrip',
  'dvdrip',
  'hdrip',
  'hdtv',
  'cam',
  'hdcam',
  'dvdscr',
  'remux',
  'proper',
  'repack',
  'extended',
  'unrated',
  'remastered',
  'imax',
  'yify',
  'yts',
  'rarbg',
  'ettv',
  'eztv',
  'fgt',
  'amzn',
  'nf',
  'netflix',
  'aac',
  'aac2',
  'ac3',
  'eac3',
  'dts',
  'dtshd',
  'truehd',
  'atmos',
  'ddp',
  'dd',
  '10bit',
  '8bit',
  'hdr',
  'hdr10',
  'dv',
  'dolby',
  'vision',
  'sdr',
  'uhd',
  '4k',
  'mp4',
  'mkv',
  'avi',
  'mov',
  'multi',
  'dual',
  'subbed',
  'subs',
  'itunes',
  'hmax',
  'dsnp',
  'atvp',
  'hulu',
  'amx',
  'hevc',
  'avc',
  'h264',
  'h265',
  'pahe',
  'psa',
  'galaxyrg',
};

/// Matches audio/codec fragments like `ddp5`, `ac3e`, `dtshdma`.
final RegExp _codecFragment = RegExp(r'^(ddp|dd|ac3|eac3|dts|dtshd|aac)\d*$');

ParsedRelease parseRelease(String name) {
  // Strip bracketed groups first, then normalise every separator
  // (dots, underscores, hyphens) to spaces so compound tags like
  // `x264-YIFY` or `DDP5.1` split correctly.
  String text = name
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');

  int? year;
  final RegExpMatch? yearMatch =
      RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(text);
  if (yearMatch != null) {
    year = int.tryParse(yearMatch.group(0)!);
  }

  String? quality;
  final RegExpMatch? qualityMatch =
      RegExp(r'\b(2160|1440|1080|720|480|360)p\b', caseSensitive: false)
          .firstMatch(text);
  if (qualityMatch != null) {
    quality = '${qualityMatch.group(1)!}p'.toLowerCase();
  }

  final List<String> kept = <String>[];
  for (final String raw in text.split(' ')) {
    final String token = raw.trim().toLowerCase();
    if (token.isEmpty) continue;
    if (token == '$year') continue;
    if (quality != null && token == quality) continue;
    if (_junkTokens.contains(token)) continue;
    if (_codecFragment.hasMatch(token)) continue;
    if (RegExp(r'^\d+$').hasMatch(token)) continue; // loose numbers
    if (token.length == 1) continue; // stray initials (h, x, …)
    if (token.length > 40) continue;
    kept.add(token);
  }

  return ParsedRelease(
    cleanTitle: kept.join(' ').trim(),
    year: year,
    quality: quality,
  );
}

/// Extracts a resolution tag (`480p`…`2160p`) from a release name.
String? detectQuality(String name) {
  final RegExpMatch? match =
      RegExp(r'\b(2160|1440|1080|720|480|360)p\b', caseSensitive: false)
          .firstMatch(name);
  return match == null ? null : '${match.group(1)}p'.toLowerCase();
}

/// Jaccard similarity over word tokens, used to rank torrent groups
/// against the movie being browsed.
double titleSimilarity(String a, String b) {
  final Set<String> tokensA = _tokens(a);
  final Set<String> tokensB = _tokens(b);
  if (tokensA.isEmpty || tokensB.isEmpty) return 0;
  int intersection = 0;
  for (final String t in tokensA) {
    if (tokensB.contains(t)) intersection++;
  }
  final int union = tokensA.length + tokensB.length - intersection;
  return union == 0 ? 0 : intersection / union;
}

Set<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((String t) => t.isNotEmpty)
    .toSet();
