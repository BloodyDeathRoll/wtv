import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const _window = MethodChannel('wtv/window');

/// Whether the window is in full screen, as the runner last reported it.
final fullScreen = ValueNotifier(false);

/// Keeps [fullScreen] up to date. Once, before the app runs.
void watchFullScreen() => _window.setMethodCallHandler((call) async {
  if (call.method == 'fullScreen') fullScreen.value = call.arguments as bool;
});

/// The window in or out of full screen. A nicety: without the runner's channel (tests) nothing happens.
Future<void> toggleFullScreen() async {
  try {
    await _window.invokeMethod<void>('toggleFullScreen');
  } on MissingPluginException {
    // No window to change.
  } on PlatformException catch (e) {
    debugPrint('Full screen: $e');
  }
}

/// F11, anywhere in the app, toggles full screen. A held key toggles it once.
/// In full screen Esc leaves it, and only that: out of full screen Esc is Back.
class FullScreenKeys extends StatelessWidget {
  const FullScreenKeys({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: fullScreen,
    builder: (context, full, child) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11, includeRepeats: false): toggleFullScreen,
        if (full)
          const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false): () {
            // At once, so a second Esc before the runner reports is Back, not full screen again.
            fullScreen.value = false;
            toggleFullScreen();
          },
      },
      child: child!,
    ),
    child: child,
  );
}
