# Popcorn Studio

**A Netflix-style movie discovery app that streams and downloads films from public sources — watch while you download.**

Popcorn Studio is a Flutter application for **Android, Linux (generic + Debian) and Windows**.
It ships **no content**: it aggregates open metadata (TMDB), public media catalogs
(Torrentio — the stream source used by Stremio — plus YTS and ThePirateBay via apibay),
a battle-tested C++ download engine (aria2) and free subtitle sources (OpenSubtitles)
into one polished experience.

> **Legal notice** — Popcorn Studio pulls media from public third-party sources and
> ships no content of its own. You are responsible for streaming and downloading only
> material you have the right to access under your local laws.

## Features

- **Netflix-style dark UI** — hero banner, content rails, poster grid, adaptive
  navigation (bottom bar on mobile, rail on desktop).
- **Rich movie catalog** — trending / popular / top-rated / in-theaters rails,
  search, cast, trailers and similar titles powered by the TMDB API.
- **Quality chooser (Stremio-style loading)** — for every movie, all available
  sources (Torrentio + YTS + PirateBay) are de-duplicated and grouped into
  per-quality options (480p → 2160p) with **file size, availability and provider**.
  Results appear progressively as each source answers — you can start in seconds.
- **Watch while downloading (FDM-style)** — sources are downloaded with
  head/tail piece prioritisation (`head=64M,tail=16M`) and served to the player
  through a local HTTP server with full `Range` / `206 Partial Content` semantics
  and **piece-accurate availability tracking** (bitfield-based), so playback is
  smooth and never serves unfinished data. Playback starts within seconds;
  seeks into undownloaded regions stall gracefully until the bytes arrive.
- **Multi-video sources** — when a source bundle contains several videos (packs,
  collections), every video file is listed and you choose what to stream.
- **Subtitles** — embedded `.srt/.ass/.vtt` tracks plus automatic OpenSubtitles
  lookup by TMDB id, switchable from the player.
- **Robust engine** — bundled static **aria2 1.37.0** (C++) controlled over
  JSON-RPC, DHT enabled, extra trackers injected into every source link, session
  persistence across restarts, pause/resume/remove.
- **Instant source resolution** — when a source's info hash is known (stream
  addons always provide it), the .torrent descriptor is fetched over HTTPS and
  the file list appears in seconds — no waiting on swarm metadata — then the
  download runs with the full peer set. Fallback to classic metadata exchange
  is automatic.
- **Forced self-update** — every launch checks GitHub Releases; when a newer
  version is published, older installs are locked to an "Update required"
  screen (no playback, no downloads) with a direct link to the new build.
  The check fails open while offline so a flaky connection never bricks the app.

## Architecture

```
lib/
├── core/            theme, constants, errors, formatting utils
├── domain/          typed models (Movie, TorrentInfo, TorrentTask, …)
├── data/            TMDB client · apibay + YTS providers · quality
│                    aggregation · OpenSubtitles client · settings store
├── engine/          pure-Dart BitTorrent orchestration:
│   ├── engine_manager.dart    aria2 process lifecycle (per-platform paths)
│   ├── aria2_rpc_client.dart  JSON-RPC client (fixed-length bodies!)
│   ├── torrent_facade.dart    metadata→select→download lifecycle + records
│   ├── stream_server.dart     local HTTP Range server (FDM-style streaming)
│   ├── bencode.dart           minimal bencode codec
│   └── os_hash.dart           OpenSubtitles movie hash
└── presentation/    Riverpod providers + screens (home, search, details,
                     player, downloads, settings) + sheets/widgets
```

**Why aria2?** It is a proven C++ engine with rock-solid tracker/DHT/peer
handling, per-file selection and head/tail piece prioritisation — the levers
that make streaming-while-downloading possible. The engine layer is isolated
behind `TorrentFacade`, so a libtorrent-FFI backend with full sequential
piece selection can slot in later without UI changes.

**Streaming strategy.** aria2 is rarest-first by default (issues #911/#1365),
so Popcorn Studio combines three techniques: `bt-prioritize-piece` fetches the
head of the file immediately (fast start, MP4 `moov` / MKV index), the local
`StreamServer` gates HTTP Range responses on the downloaded frontier and polls
the engine (the same technique used by peerflix/FDM), and the player's buffer
absorbs piece-order randomness at playback speed.

## Platform engine delivery

| Platform    | Binary source                                       | Installed as                          |
|-------------|-----------------------------------------------------|---------------------------------------|
| Android     | `devgianlu/aria2-android` static builds (NDK r23)   | `jniLibs/<abi>/libpopcornaria2.so` → exec'd from `nativeLibraryDir` |
| Linux/Debian| `abcfy2/aria2-static-build` (musl, fully static)    | `<bundle>/engine/aria2c`              |
| Windows     | `abcfy2/aria2-static-build` (mingw, static)         | `<app>\engine\aria2c.exe`             |

CI downloads engine binaries at build time — **no binaries are committed**.

## Building

```bash
flutter pub get
dart run flutter_launcher_icons     # generate launcher icons
flutter build apk --release --split-per-abi   # Android
flutter build linux --release                 # Linux
flutter build windows --release               # Windows
```

Run tests (unit suite always runs; the engine end-to-end test auto-downloads
nothing — it uses the binary found via `POPCORN_ARIA2`, standard paths, or
skips gracefully):

```bash
curl -sL -o aria2c https://github.com/abcfy2/aria2-static-build/releases/download/1.37.0/aria2-x86_64-linux-musl_static.zip
unzip aria2c.zip && chmod +x aria2c
POPCORN_ARIA2=$PWD/aria2c flutter test
```

## Releases

CI (`.github/workflows/`) publishes on every `v*` tag:

- `PopcornStudio-arm64-v8a.apk`, `PopcornStudio-armeabi-v7a.apk`,
  `PopcornStudio-x86_64.apk`, `PopcornStudio-x86.apk`
- `PopcornStudio-linux-x64.tar.gz` + `popcorn-studio_<ver>_amd64.deb`
- `PopcornStudio-windows-x64.zip`

## Credits & data sources

- Metadata: [TMDB](https://www.themoviedb.org) (this product uses the TMDB API but is not endorsed or certified by TMDB)
- Subtitles: [OpenSubtitles](https://www.opensubtitles.com)
- Torrent indexers: YTS API, apibay (The Pirate Bay's official JSON API)
- Engine: [aria2](https://github.com/aria2/aria2)
- Player: [media_kit](https://github.com/media-kit/media-kit) (libmpv)

Licensed under the [MIT License](LICENSE).
