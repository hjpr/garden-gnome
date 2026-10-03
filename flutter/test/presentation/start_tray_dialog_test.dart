import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/presentation/garden/start_tray_dialog.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';
import '../support/widget_harness.dart';

void main() {
  testWidgets('a greenhouse start can be dated ahead of today', (tester) async {
    final garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      catalog: testCatalog,
      clock: () => DateTime(2026, 4, 1),
    );
    await garden.load();
    final tomato = garden.addVariety('tomatoes', 'Big Beef');
    await tester.pumpWidget(
      testApp(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showStartTrayDialog(context, garden, varietyId: tomato),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-Start date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Apr 4, 2026'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    final tray = garden.inGreenhouse().single.planting;
    expect(tray.sownOn, DateTime.utc(2026, 4, 4));
    expect(tray.container, GrowContainer.flat);
    await tester.pump(const Duration(seconds: 10));
  });
}
