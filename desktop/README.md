# WTV desktop

The WTV TV app as a desktop app, Linux first. The plan is `docs/PLAN-DESKTOP.md`.

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
ignores. Take only these four names from the project's key file:

```
grep -E '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|GOOGLE_TV_CLIENT_ID|GOOGLE_TV_CLIENT_SECRET)=' /path/to/.env.local > .env
```

Never pass the whole key file to a build: every value in it would go into the
app. A build without `.env` starts, and says which setting is missing when it
needs one.

## Notes

- **Layout.** The window shows the TV app's 960 x 540 layout scaled to fit
  (`DesignScale` in `lib/ui/theme.dart`), so a size in this code is the TV
  app's number.
- **Strings.** `lib/l10n/app_en.arb` and `app_he.arb` hold the TV app's strings
  (`android/app/src/main/res/values*/strings.xml`). `flutter pub get` builds
  the Dart classes from them.
- **Keys and mouse.** Arrow keys move the focus, Enter or Space presses, Esc or
  the mouse's back button goes back. The pointer moves the focus too.
- **Session.** The signed-in session is kept in the system keyring (libsecret),
  not in a file.

## Licence

GNU General Public License, version 3 (`LICENSE`). It covers this folder only.
