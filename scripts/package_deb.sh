#!/usr/bin/env bash
# Packages the built Flutter Linux bundle into a tar.gz and a Debian .deb.
# Usage: scripts/package_deb.sh <version>
set -euo pipefail

VERSION="${1:?Usage: package_deb.sh <version>}"
BUNDLE="build/linux/x64/release/bundle"
DIST="dist"
APP_ID="popcorn-studio"
BINARY_NAME="popcorn_studio"
INSTALL_DIR="/opt/popcorn-studio"

[ -d "$BUNDLE" ] || { echo "Bundle not found at $BUNDLE — run 'flutter build linux --release' first"; exit 1; }
[ -x "$BUNDLE/engine/aria2c" ] || { echo "Engine binary missing — bundle aria2 first"; exit 1; }

mkdir -p "$DIST"

# ── tar.gz for generic Linux ─────────────────────────────────────────────
tar -C "$(dirname "$BUNDLE")" -czf "$DIST/PopcornStudio-linux-x64.tar.gz" "$(basename "$BUNDLE")"

# ── .deb for Debian/Ubuntu ───────────────────────────────────────────────
STAGING="build/deb/${APP_ID}_${VERSION}_amd64"
rm -rf "$STAGING"
mkdir -p \
  "$STAGING/DEBIAN" \
  "$STAGING$INSTALL_DIR" \
  "$STAGING/usr/bin" \
  "$STAGING/usr/share/applications" \
  "$STAGING/usr/share/icons/hicolor/512x512/apps"

# Application payload
cp -r "$BUNDLE"/* "$STAGING$INSTALL_DIR/"
chmod +x "$STAGING$INSTALL_DIR/$BINARY_NAME" "$STAGING$INSTALL_DIR/engine/aria2c"

# Launcher symlink
ln -sf "$INSTALL_DIR/$BINARY_NAME" "$STAGING/usr/bin/$APP_ID"

# Desktop entry
cat > "$STAGING/usr/share/applications/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Popcorn Studio
Comment=Stream and download movies with a Netflix-style interface
Exec=$APP_ID
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=movie;stream;torrent;popcorn;
DESKTOP

# Icon (any PNG source, hicolor expects a real 512x512 — resize if needed)
if command -v convert >/dev/null 2>&1; then
  convert assets/images/app_icon.png -resize 512x512 "$STAGING/usr/share/icons/hicolor/512x512/apps/${APP_ID}.png"
else
  cp assets/images/app_icon.png "$STAGING/usr/share/icons/hicolor/512x512/apps/${APP_ID}.png"
fi

# Debian control file
cat > "$STAGING/DEBIAN/control" <<CONTROL
Package: ${APP_ID}
Version: ${VERSION}
Section: video
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libmpv2 | libmpv1, libstdc++6, libc6
Maintainer: Popcorn Studio <popcorn@zoofam.dev>
Description: Netflix-style movie discovery, streaming and downloads over BitTorrent
 Popcorn Studio browses TMDB metadata, lists every available torrent quality
 (YTS / PirateBay), streams video while it downloads through a bundled aria2
 engine and local range server, and fetches subtitles from OpenSubtitles.
CONTROL

dpkg-deb --build --root-owner-group "$STAGING" "$DIST/popcorn-studio_${VERSION}_amd64.deb"

echo "── Artifacts ──"
ls -la "$DIST"
