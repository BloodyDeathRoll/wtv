import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const _window = MethodChannel('wtv/window');

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

/// F11, anywhere in the app, toggles full screen.
class FullScreenKeys extends StatelessWidget {
  const FullScreenKeys({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.f11): toggleFullScreen}, child: child);
}
