import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Colour tokens, the same as the TV app's (`ui/theme/Color.kt`).
abstract final class WtvColors {
  /// Page background: near-black with a blue cast.
  static const background = Color(0xFF0F171E);
  static const surface = Color(0xFF1A242F);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFC7CBD1);
  static const textMuted = Color(0xFF8197A4);

  /// Highlight line under the title (awards, "New episode").
  static const accent = Color(0xFFFFA900);

  /// Focus ring on cards and buttons.
  static const focus = Color(0xFFFFFFFF);

  /// An unselected chip: a little lighter than [surface].
  static const chip = Color(0xFF253241);

  /// A selected chip: darker than an unselected one.
  static const chipSelected = Color(0xFF131B23);

  /// Rating badges ("TV-14", "16+").
  static const badge = Color(0xFF33373D);

  /// Tags on the title line ("TRENDING", "NEW").
  static const tag = Color(0xFFE6E6E6);
  static const onTag = Color(0xFF0F171E);
}

TextStyle _style(double size, double line, FontWeight weight) =>
    TextStyle(fontSize: size, height: line / size, fontWeight: weight, color: WtvColors.textPrimary);

/// The TV app's sizes (`ui/theme/Type.kt`); [DesignScale] fits them to the window.
final wtvTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: WtvColors.textPrimary,
    onPrimary: WtvColors.background,
    surface: WtvColors.background,
    onSurface: WtvColors.textPrimary,
  ),
  textTheme: TextTheme(
    // Title in the header.
    displayMedium: _style(36, 42, FontWeight.bold),
    // The sign-in code.
    displaySmall: _style(36, 44, FontWeight.normal),
    // Person name, big page titles.
    headlineMedium: _style(28, 34, FontWeight.bold),
    // Questions in a dialog.
    headlineSmall: _style(24, 32, FontWeight.normal),
    // Row titles ("Viewers also liked").
    titleMedium: _style(16, 22, FontWeight.w600),
    // Meta line, highlight line.
    titleSmall: _style(15, 20, FontWeight.w500),
    // Synopsis.
    bodyLarge: _style(15, 22, FontWeight.normal),
    bodyMedium: _style(13, 18, FontWeight.normal),
    // Badges and card labels.
    labelLarge: _style(14, 18, FontWeight.w600),
    labelMedium: _style(12, 16, FontWeight.bold),
  ),
);

/// The TV app is laid out for a 960 x 540 screen. The window shows that layout
/// scaled to fit, so a size in this app is the TV app's number. A window of
/// another shape gets more room on one side, never less than the TV's screen.
class DesignScale extends StatelessWidget {
  const DesignScale({super.key, required this.child});

  static const screen = Size(960, 540);
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // A minimised window has no size to scale to.
      if (box.biggest.isEmpty) return const SizedBox.shrink();
      final scale = math.min(box.maxWidth / screen.width, box.maxHeight / screen.height);
      final canvas = box.biggest / scale;
      final media = MediaQuery.of(context);
      return FittedBox(
        child: SizedBox.fromSize(
          size: canvas,
          child: MediaQuery(
            data: media.copyWith(size: canvas, devicePixelRatio: media.devicePixelRatio * scale),
            child: child,
          ),
        ),
      );
    },
  );
}
