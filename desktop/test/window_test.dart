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
    // Held down, it toggles once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    expect(calls, hasLength(3));
  });

  testWidgets('in full screen, as the runner reports, Esc leaves it and is not Back; out of it Esc is Back', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('wtv/window'), (call) async {
      calls.add(call.method);
      return null;
    });
    watchFullScreen();
    addTearDown(() => fullScreen.value = false);
    var backs = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Actions(
          actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => backs++)},
          child: FullScreenKeys(child: Focus(focusNode: focus, autofocus: true, child: const SizedBox())),
        ),
      ),
    );
    Future<void> report(bool full) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'wtv/window',
      const StandardMethodCodec().encodeMethodCall(MethodCall('fullScreen', full)),
      (_) {},
    );

    await report(true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect((calls.length, backs), (1, 0));
    // A second Esc before the runner reports is Back already.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect((calls.length, backs), (1, 1));
    await report(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect((calls.length, backs), (1, 2));
  });
}
