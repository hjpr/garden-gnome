import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/presentation/garden/timeline.dart';

void main() {
  testWidgets('the wheel zooms over the chart even when the list could '
      'scroll, and scrolls the list over the names', (tester) async {
    final today = DateTime.utc(2026, 4, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 400,
            child: Timeline(
              range: DayWindow(today, DateTime.utc(2026, 8, 1)),
              today: today,
              labelWidth: 300,
              rows: [
                for (var i = 0; i < 40; i++)
                  TimelineRow(
                    title: 'Row $i',
                    bars: [
                      TimelineBar(
                        span: DayWindow(today, DateTime.utc(2026, 5, 1)),
                        color: Colors.green,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final list = find.byType(Scrollable).last;
    double scrolled() => tester.state<ScrollableState>(list).position.pixels;
    bool zoomed() => tester
        .widget<Visibility>(
          find.ancestor(
            of: find.widgetWithText(TextButton, 'Today'),
            matching: find.byType(Visibility),
          ),
        )
        .visible;

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    Future<void> wheel(Offset at) async {
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();
    }

    // Over the chart: zoom, and the list stays where it is.
    await wheel(const Offset(700, 200));
    expect(zoomed(), isTrue);
    expect(scrolled(), 0);

    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();

    // Over the names: the list scrolls, the view does not zoom.
    await wheel(const Offset(100, 200));
    expect(scrolled(), greaterThan(0));
    expect(zoomed(), isFalse);
  });

  testWidgets('a mouse drag over the chart moves through time and '
      'through the rows', (tester) async {
    final today = DateTime.utc(2026, 4, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 400,
            child: Timeline(
              range: DayWindow(today, DateTime.utc(2026, 8, 1)),
              today: today,
              labelWidth: 300,
              rows: [
                for (var i = 0; i < 40; i++)
                  TimelineRow(title: 'Row $i', bars: const []),
              ],
            ),
          ),
        ),
      ),
    );
    final list = find.byType(Scrollable).last;
    double scrolled() => tester.state<ScrollableState>(list).position.pixels;
    bool moved() => tester
        .widget<Visibility>(
          find.ancestor(
            of: find.widgetWithText(TextButton, 'Today'),
            matching: find.byType(Visibility),
          ),
        )
        .visible;

    // Straight up: the rows move, the dates stay.
    final up = await tester.startGesture(
      const Offset(700, 300),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await up.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await up.up();
    await tester.pumpAndSettle();
    expect(scrolled(), greaterThan(50));
    expect(moved(), isFalse);

    // Down and right together: both move back.
    final before = scrolled();
    final diagonal = await tester.startGesture(
      const Offset(700, 150),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await diagonal.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    await diagonal.up();
    await tester.pumpAndSettle();
    expect(scrolled(), lessThan(before));
    expect(moved(), isTrue);
  });
}
