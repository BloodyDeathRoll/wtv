import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wtv/ui/components/rows.dart';

void main() {
  Future<ScrollController> row(WidgetTester tester, TextDirection direction) async {
    late ScrollController controller;
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 100,
            child: SideArrows(
              builder: (c) => ListView(
                controller: controller = c,
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 20; i++) SizedBox(width: 100, child: Text('$i'))],
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Future<void> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(SideArrows)));
    await tester.pump();
  }

  for (final direction in TextDirection.values) {
    testWidgets('$direction: arrows show on hover, only towards where the row can scroll, and page it', (tester) async {
      final controller = await row(tester, direction);
      expect(find.byType(Icon), findsNothing);

      await hover(tester);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(controller.offset, 320);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(controller.offset, 0);

      // To the end: the forward arrow goes.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });
  }

  testWidgets('the arrows take no focus', (tester) async {
    await row(tester, TextDirection.ltr);
    await hover(tester);
    final focusable = tester.widgetList<Focus>(find.descendant(of: find.byType(SideArrows), matching: find.byType(Focus)));
    expect(focusable, isEmpty);
  });
}
