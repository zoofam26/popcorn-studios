import 'package:flutter_test/flutter_test.dart';
import 'package:popcorn_studio/data/release_parser.dart';
import 'package:popcorn_studio/domain/models.dart';
import 'package:popcorn_studio/data/torrent_search_service.dart';

void main() {
  group('parseRelease', () {
    test('extracts title, year and quality from scene name', () {
      final ParsedRelease parsed =
          parseRelease('Interstellar.2014.2014.1080p.BluRay.x264.YIFY.mp4');
      expect(parsed.year, 2014);
      expect(parsed.quality, '1080p');
      expect(parsed.cleanTitle, contains('interstellar'));
      expect(parsed.cleanTitle.contains('bluray'), isFalse);
      expect(parsed.cleanTitle.contains('yify'), isFalse);
      expect(parsed.cleanTitle.contains('x264'), isFalse);
    });

    test('handles web-dl releases', () {
      final ParsedRelease parsed =
          parseRelease('The.Martian.2015.720p.WEB-DL.DDP5.1.H.264-AMZN');
      expect(parsed.year, 2015);
      expect(parsed.quality, '720p');
      expect(parsed.cleanTitle, 'the martian');
    });
  });

  group('TorrentSearchService.groupIntoQualityOptions', () {
    final TorrentSearchService service = TorrentSearchService();

    TorrentInfo torrent(
      String name,
      int sizeBytes,
      int seeders, {
      String? hash,
      String? url,
    }) =>
        TorrentInfo(
          infoHash: hash ?? _hashOf(name),
          name: name,
          sizeBytes: sizeBytes,
          seeders: seeders,
          leechers: 0,
          source: TorrentSource.apibay,
          magnetUri: 'magnet:?xt=urn:btih:${hash ?? _hashOf(name)}',
          torrentUrl: url,
        );

    test('groups same movie into per-quality options sorted by resolution', () {
      final List<QualityOption> options = service.groupIntoQualityOptions(
        <TorrentInfo>[
          torrent('Interstellar.2014.720p.BluRay.x264.YIFY', 900 << 20, 300),
          torrent('Interstellar.2014.1080p.BluRay.x264-YIFY', 2100 << 20, 950),
          torrent('Interstellar 2014 2160p WEB-DL x265', 16000 << 20, 40),
          torrent('Interstellar.2014.1080p.WEBRip.x265', 2000 << 20, 120),
        ],
        preferredTitle: 'Interstellar',
        preferredYear: 2014,
      );

      expect(options.map((QualityOption o) => o.label).toList(),
          <String>['2160p', '1080p', '720p']);
      // Best-seeded torrent wins within a quality.
      expect(options[1].best.seeders, 950);
      expect(
          options[1].best.quality ?? parseRelease(options[1].best.name).quality,
          '1080p');
    });

    test('prefers the group matching the requested title', () {
      final List<QualityOption> options = service.groupIntoQualityOptions(
        <TorrentInfo>[
          torrent('Some.Other.Movie.2019.1080p.BluRay', 1000 << 20, 9000),
          torrent('Interstellar.2014.720p.BluRay.x264', 900 << 20, 50),
        ],
        preferredTitle: 'Interstellar',
        preferredYear: 2014,
      );
      expect(options, hasLength(1));
      expect(options.single.label, '720p');
    });

    test('de-duplicates identical info hashes preferring .torrent url', () {
      final String hash = 'b' * 40;
      final List<TorrentInfo> deduped = service.dedupeByHash(<TorrentInfo>[
        torrent('A.1080p.BluRay', 100, 10, hash: hash),
        torrent('A.1080p.BluRay', 100, 20,
            hash: hash, url: 'https://x/t.torrent'),
      ]);
      expect(deduped, hasLength(1));
      expect(deduped.single.torrentUrl, 'https://x/t.torrent');
    });
  });
}

String _hashOf(String seed) {
  // Deterministic 40-char pseudo hash per name.
  final StringBuffer buffer = StringBuffer();
  int x = seed.hashCode & 0xFFFFFFFF;
  for (int i = 0; i < 40; i++) {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    buffer.write((x % 16).toRadixString(16));
  }
  return buffer.toString();
}
