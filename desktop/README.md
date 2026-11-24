# WTV desktop

The WTV TV app as a desktop app, Linux first. The plan is `docs/PLAN-DESKTOP.md`.

## Build

Flutter 3.50.1, and on Ubuntu:

```
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

Then, in this folder:

```
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

`flutter build linux --release` puts the app in `build/linux/x64/release/bundle/`.

## Notes

- **Layout.** The window shows the TV app's 960 x 540 layout scaled to fit
  (`DesignScale` in `lib/ui/theme.dart`), so a size in this code is the TV
  app's number.
- **Strings.** `lib/l10n/app_en.arb` and `app_he.arb` hold the TV app's strings
  (`android/app/src/main/res/values*/strings.xml`). `flutter pub get` builds
  the Dart classes from them.
- **Keys and mouse.** Arrow keys move the focus, Enter or Space presses, Esc or
  the mouse's back button goes back. The pointer moves the focus too.

## Licence

GNU General Public License, version 3 (`LICENSE`). It covers this folder only.
