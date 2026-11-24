#!/bin/bash
# Run by package.sh inside a clean container of this system's release, not by hand.
# In /in: the built app (app/) and system-libs.txt. Installs the packages named in
# $PACKAGES and writes a tar to its output: lib/ (the mpv engine and every library
# that it and the app need and the system is not relied on for), licenses/ (each
# package's licence), SOURCES.rows (library, package, source package, version) and
# SYSTEM (the system's name).
set -euo pipefail
exec 3>&1 1>&2 # the output is the tar alone: everything else goes to the log
export DEBIAN_FRONTEND=noninteractive
fail() { echo "engine-libs.sh: $*"; exit 1; }

apt-get update -qq
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $PACKAGES > /dev/null
mkdir -p /out/lib /out/licenses

# A file's libraries, the whole chain, as ldd prints them; the app's own are found in its lib folder.
linked() { LD_LIBRARY_PATH=/in/app/lib ldd "$@" 2>/dev/null; }
# The same, as paths.
needs() { linked "$@" | awk '$2 == "=>" && $3 ~ "^/" { print $3 }' | sort -u; }
# A library's path, from its name.
lib() { ldconfig -p | awk -v name="$1" '$1 == name && /x86-64/ { print $NF; exit }'; }
# The app's own files. libdartjni.so is for Android (it needs Java) and is never loaded here.
mapfile -t own < <(find /in/app/wtv /in/app/lib -maxdepth 1 -type f ! -name libdartjni.so | sort)

engine="$(lib libmpv.so.2)"
gtk="$(lib libgtk-3.so.0)"
[ -n "$engine" ] && [ -n "$gtk" ] || fail "libmpv.so.2 or libgtk-3.so.0 is not installed"
if linked "${own[@]}" "$engine" | grep "not found"; then fail "a library is missing"; fi
# Left to the system: the names in system-libs.txt, and what GTK brings (the app cannot
# start without GTK, so those are there).
{ grep -v '^#' /in/system-libs.txt; { echo "$gtk"; needs "$gtk"; } | sed 's|.*/||'; } | sort -u > /tmp/system-libs
# The app's own libraries (under /in) are in the app already.
{ echo "$engine"; needs "$engine" "${own[@]}"; } | grep -v '^/in/' | sort -u | while read -r path; do
  name="${path##*/}"
  grep -qxF "$name" /tmp/system-libs && continue
  install -m 644 "$path" "/out/lib/$name"
  package="$(dpkg -S "$(readlink -f "$path")" | cut -d: -f1)"
  [ -n "$package" ] || fail "no package owns $path: its licence and source are unknown"
  printf '%-34s %-28s %s\n' "$name" "$package" "$(dpkg-query -W -f '${source:Package} ${source:Version}' "$package" | awk '{ printf "%-24s %s", $1, $2 }')" >> /out/SOURCES.rows
  [ -e "/out/licenses/$package.txt" ] || install -m 644 "/usr/share/doc/$package/copyright" "/out/licenses/$package.txt"
done
[ -e /out/lib/libmpv.so.2 ] || fail "the mpv engine was not packed"
. /etc/os-release
echo "$PRETTY_NAME" > /out/SYSTEM
tar -c -C /out . >&3
