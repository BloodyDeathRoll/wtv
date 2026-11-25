import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wtv/window.dart';

void main() {
  testWidgets('F11 asks the window for full screen, each time', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('wtv/window'), (call) async {
      calls.add(call.method);
      return null;
    });
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(home: FullScreenKeys(child: Focus(focusNode: focus, autofocus: true, child: const SizedBox()))));
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(calls, ['toggleFullScreen', 'toggleFullScreen']);
  });
}
