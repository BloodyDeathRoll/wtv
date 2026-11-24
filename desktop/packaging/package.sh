#!/bin/bash
# Builds the Linux packages into build/packages/:
#   - a .deb: the system's package manager installs the mpv engine with it;
#   - an AppImage: the mpv engine and its libraries are inside.
# Needs flutter, dpkg-dev, squashfs-tools, rsync, curl and docker, and the build
# packages the README lists.
# shortcut: the AppImage carries libraries of this machine's release, so it needs
# that release's C library or a newer one; build in an older release's container
# when other machines need it. The .deb uses the system's own libraries.
# shortcut: Ubuntu only: the engine's libraries come from the Docker Hub image
# named by /etc/os-release.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
project="$(dirname "$here")"
out="$project/build/packages"
id=com.wtv.desktop
version="$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' "$project/pubspec.yaml")"

# The AppImage's start program, a fixed release of github.com/AppImage/type2-runtime.
runtime_url=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
runtime_sha=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

fail() { echo "package.sh: $*" >&2; exit 1; }

# Every value in .env goes into the build: only the app's own six keys may be there.
[ -f "$project/.env" ] || fail "desktop/.env is missing (see the README, Keys)"
if grep -vE '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|GOOGLE_TV_CLIENT_ID|GOOGLE_TV_CLIENT_SECRET|WTW_SUPABASE_URL|WTW_SUPABASE_ANON_KEY)=|^[[:space:]]*(#|$)' "$project/.env" | grep -q .; then
  fail "desktop/.env holds a line that is not one of the app's six keys"
fi

# The build runs on a copy in a fixed folder: the build writes its own folder's
# path into the app, and that must not be this user's home folder.
work="${TMPDIR:-/tmp}/wtv-desktop-build"
install -d -m 700 "$work"
[ -O "$work" ] && [ ! -L "$work" ] || fail "$work belongs to someone else or is a link"
rsync -a --delete --exclude /build --exclude /.dart_tool --exclude /linux/flutter/ephemeral "$project/" "$work/src/"
(cd "$work/src" && flutter build linux --release --dart-define-from-file=.env)
bundle="$work/src/build/linux/x64/release/bundle"
# `wtv` is the binary's name in linux/CMakeLists.txt.
[ -x "$bundle/wtv" ] || fail "the build left no app in $bundle"
if [ -n "$HOME" ] && [ "$HOME" != / ] && grep -rlaF "$HOME" "$bundle" | grep -q .; then fail "the built app holds the path $HOME"; fi
# A library that searched the build folder for its own libraries would load whatever is put there.
if find "$bundle" -type f ! -name libdartjni.so -exec readelf -d {} + 2>/dev/null | grep -E 'R(UN)?PATH' | grep -vF '[$ORIGIN'; then
  fail "a built file searches for libraries outside the app"
fi

# The app's own files. libdartjni.so is for Android (it needs Java) and is never loaded here.
mapfile -t own < <(find "$bundle/wtv" "$bundle/lib" -maxdepth 1 -type f ! -name libdartjni.so | sort)

rm -rf "$out" "$work/deb" "$work/AppDir" "$work/shlibs"
mkdir -p "$out"

# ---- .deb ------------------------------------------------------------------
deb="$work/deb"
install -d "$deb/DEBIAN" "$deb/opt/wtv-desktop" "$deb/usr/bin" "$deb/usr/share/applications" \
  "$deb/usr/share/icons/hicolor/192x192/apps" "$deb/usr/share/doc/wtv-desktop"
cp -a "$bundle/." "$deb/opt/wtv-desktop/"
ln -s /opt/wtv-desktop/wtv "$deb/usr/bin/wtv-desktop"
install -m 644 "$here/$id.desktop" "$deb/usr/share/applications/"
install -m 644 "$here/$id.png" "$deb/usr/share/icons/hicolor/192x192/apps/"
cat > "$deb/usr/share/doc/wtv-desktop/copyright" <<TEXT
WTV for the desktop. Source: https://github.com/BloodyDeathRoll/wtv, folder desktop/.
Licence: GNU General Public License, version 3 (/usr/share/common-licenses/GPL-3).
The licences of the Flutter engine and the Dart packages built into the app are
in /opt/wtv-desktop/data/flutter_assets/NOTICES.Z (gzip).
TEXT
# The packages the app's files need, the mpv engine among them (the video plugin links to it).
mkdir -p "$work/shlibs/debian"
printf 'Source: wtv-desktop\n\nPackage: wtv-desktop\nArchitecture: amd64\n' > "$work/shlibs/debian/control"
depends="$(cd "$work/shlibs" && dpkg-shlibdeps -O --ignore-missing-info -l"$bundle/lib" "${own[@]/#/-e}" 2> "$work/shlibs.log" | sed -n 's/^shlibs:Depends=//p')"
[[ "$depends" == *libmpv* && "$depends" == *libgtk-3* ]] || { cat "$work/shlibs.log" >&2; fail "the .deb's dependencies miss the mpv engine or GTK: $depends"; }
# Flutter opens OpenGL ES by name when it starts, so no file links to it.
depends="$depends, libgles2"
cat > "$deb/DEBIAN/control" <<TEXT
Package: wtv-desktop
Version: $version
Architecture: amd64
Maintainer: BloodyDeathRoll <BloodyDeathRoll@users.noreply.github.com>
Installed-Size: $(du -sk --exclude=DEBIAN "$deb" | cut -f1)
Depends: $depends
Recommends: gnome-keyring
Section: video
Priority: optional
Homepage: https://github.com/BloodyDeathRoll/wtv
Description: WTV for the desktop
 Movies, series and live TV from the WTV catalog, with its own player.
TEXT
dpkg-deb --build --root-owner-group "$deb" "$out/wtv-desktop_${version}_amd64.deb" > /dev/null

# ---- AppImage --------------------------------------------------------------
appdir="$work/AppDir"
install -d "$appdir/app" "$appdir/licenses"
cp -a "$bundle/." "$appdir/app/"
install -m 755 "$here/AppRun" "$appdir/AppRun"
install -m 644 "$here/$id.desktop" "$here/$id.png" "$appdir/"
ln -s "$id.png" "$appdir/.DirIcon"

# The engine and its libraries come from a clean container of this system's release, not
# from this machine: its own copies may be builds whose source is not public (Ubuntu Pro
# updates), and the packed ones must be the release's own.
. /etc/os-release
# The .deb's list names what the app needs installed.
packages="$(echo "$depends" | sed 's/([^)]*)//g; s/|[^,]*//g; s/,/ /g')"
# The files go in and come out through pipes: a snap's docker cannot see /tmp.
tar -c -C "$bundle/.." --transform 's|^bundle|app|' bundle -C "$here" system-libs.txt engine-libs.sh \
  | docker run --rm -i --network host -e PACKAGES="$packages" "$ID:$VERSION_ID" \
      bash -c 'mkdir /in && tar -x -C /in && exec bash /in/engine-libs.sh' > "$work/engine.tar" 2> "$work/engine.log" \
  || { tail -5 "$work/engine.log" >&2; fail "the engine's libraries could not be collected (log: $work/engine.log)"; }
rm -rf "$work/engine" && mkdir "$work/engine" && tar -x -C "$work/engine" -f "$work/engine.tar"
cp -a "$work/engine/lib/." "$appdir/app/lib/"
cp -a "$work/engine/licenses/." "$appdir/licenses/"
{
  echo "This AppImage holds the WTV desktop app and the mpv engine with the libraries it needs."
  echo
  echo "WTV desktop: GNU General Public License, version 3."
  echo "Source: https://github.com/BloodyDeathRoll/wtv, folder desktop/."
  echo "The licences of the Flutter engine and the Dart packages built into the app are in"
  echo "app/data/flutter_assets/NOTICES.Z (gzip)."
  echo
  echo "The libraries below are unchanged copies from the packages of $(cat "$work/engine/SYSTEM")."
  echo "Each package's licence is in this folder, in <package>.txt. The source of each, at"
  echo "this exact version, is published by the system's maker:"
  echo "    apt source <source package>=<version>"
  [ "$ID" = ubuntu ] && echo "    https://launchpad.net/ubuntu/+source/<source package>/<version>"
  echo
  printf '%-34s %-28s %-24s %s\n' library package "source package" version
  cat "$work/engine/SOURCES.rows"
} > "$appdir/licenses/SOURCES.txt"
# media_kit looks for libmpv.so first: without this name a system copy would be loaded instead.
ln -s libmpv.so.2 "$appdir/app/lib/libmpv.so"

if ! { [ -f "$work/runtime-x86_64" ] && echo "$runtime_sha  $work/runtime-x86_64" | sha256sum --check --status; }; then
  curl -fsSL -o "$work/runtime-x86_64" "$runtime_url"
  echo "$runtime_sha  $work/runtime-x86_64" | sha256sum --check --status || fail "the AppImage runtime's checksum is wrong"
fi
mksquashfs "$appdir" "$work/app.squashfs" -root-owned -noappend -comp zstd -quiet -no-progress
appimage="$out/wtv-desktop-$version-x86_64.AppImage"
cat "$work/runtime-x86_64" "$work/app.squashfs" > "$appimage"
chmod +x "$appimage"

ls -lh "$out"
