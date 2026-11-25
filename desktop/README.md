# WTV desktop

The WTV TV app as a desktop app: Linux first, then Mac. The plan is `docs/PLAN-DESKTOP.md`.

## Build

Flutter 3.50.1, and on Ubuntu:

```
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev
```

Then, in this folder:

```
flutter pub get
flutter analyze
flutter test
flutter run -d linux --dart-define-from-file=.env
```

`flutter build linux --release --dart-define-from-file=.env` puts the app in
`build/linux/x64/release/bundle/`.

## Keys

The app's own keys are read at build time from `desktop/.env`, which git
ignores. Take only these six names from the project's key file:

```
grep -E '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|GOOGLE_TV_CLIENT_ID|GOOGLE_TV_CLIENT_SECRET|WTW_SUPABASE_URL|WTW_SUPABASE_ANON_KEY)=' /path/to/.env.local > .env
```

Never pass the whole key file to a build: every value in it would go into the
app. `GOOGLE_TV_CLIENT_SECRET` is not a real secret: Google's device flow has
every app carry it, as the TV app's build does. A build without `.env` starts, and says which setting is missing when it
needs one.

## Packages

```
packaging/package.sh
```

puts a `.deb` and an AppImage in `build/packages/`. It needs `docker`,
`dpkg-dev`, `binutils`, `squashfs-tools`, `rsync` and `curl` besides the build packages.

- **`.deb`:** the app in `/opt/wtv-desktop`. The system installs the mpv
  engine (`libmpv2`) with it.
- **AppImage:** one file with the mpv engine and its libraries inside. They are
  taken from a clean container of this machine's Ubuntu release, so they are
  the release's own builds and their source is public. `licenses/SOURCES.txt`
  in the AppImage names each library's package, source package and version.
- The AppImage needs this machine's C library or a newer one: built on Ubuntu
  26.04, it does not start on 24.04. The `.deb` uses the system's libraries and
  was checked on both. The script works on Ubuntu only.
- The libraries inside the AppImage include GPL and LGPL ones (mpv, ffmpeg).
  `SOURCES.txt` points to their source; before a build is published, the
  source offer has to be settled.
- Builds go on a draft GitHub release, which only people with write access to
  the repository can see or download. A signed-out download of a draft's file was checked to fail
  (HTTP 404) on 2026-11-24.

## Mac

The Mac app is built on GitHub's Mac machines; no Mac is needed to build it.

- **Every pull request** builds it without keys (the `desktop-macos` job of
  `.github/workflows/ci.yml`). That build starts and says which setting is
  missing.
- **A build with keys** comes from the "Desktop Mac release" workflow
  (`.github/workflows/desktop-mac-release.yml`), started by hand:
  `gh workflow run desktop-mac-release.yml -f tag=desktop-v0.1.0`. It attaches
  `wtv-desktop-<version>-macos.zip` to that draft release. It reads the six key
  names above from the repository's secrets.
- **Unsigned.** The app has no Apple signature. On first open macOS blocks it:
  open System Settings → Privacy & Security and choose Open Anyway.
- **Session and provider login** are kept in the Mac's login keychain.

On a Mac, `flutter build macos --release --dart-define-from-file=.env` puts the
app in `build/macos/Build/Products/Release/WTV.app`.

## Notes

- **Layout.** The window shows the TV app's 960 x 540 layout scaled to fit
  (`DesignScale` in `lib/ui/theme.dart`), so a size in this code is the TV
  app's number. The system's text size is not applied: a bigger window makes
  everything bigger, text included.
- **Strings.** `lib/l10n/app_en.arb` and `app_he.arb` hold the TV app's strings
  (`android/app/src/main/res/values*/strings.xml`). `flutter pub get` builds
  the Dart classes from them.
- **Keys and mouse.** Arrow keys move the focus, Enter or Space presses, Esc or
  the mouse's back button goes back. The pointer moves the focus too. Under the
  arrow keys the focused row of cards goes to the top; the mouse does not
  scroll that way, its wheel does.
- **Images.** Posters and backdrops are kept in memory only, so each start
  loads them again.
- **Session and provider login.** The signed-in session and the provider login
  typed in Settings are kept in the system keyring (libsecret on Linux), not in a file.
  The provider login is sent to the provider only.

## Licence

GNU General Public License, version 3 (`LICENSE`). It covers this folder only.
