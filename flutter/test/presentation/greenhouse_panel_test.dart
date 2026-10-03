import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/planting.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/presentation/panels/greenhouse_panel.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';
import '../support/widget_harness.dart';

void main() {
  testWidgets('Plant mode lists greenhouse sowings that are not ready yet, '
      'with their status, and each one drags', (tester) async {
    final garden = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      catalog: testCatalog,
      clock: () => DateTime(2026, 4, 1),
    );
    await garden.load();
    final tomato = garden.addVariety('tomatoes', 'Big Beef');
    garden.startInGreenhouse(
      tomato,
      container: GrowContainer.flat,
      containers: 2,
      cellsPerFlat: 50,
    );
    // Sown long ago with a Transplanted date still ahead: planned, but
    // still in the greenhouse.
    final planned = garden.sow(tomato, indoors: true, on: DateTime(2026, 2, 1));
    garden.updatePlanting(
      garden.plantings[planned]!.copyWith(
        plantedOutOn: () => DateTime.utc(2026, 4, 20),
      ),
    );

    await tester.pumpWidget(
      testApp(
        child: SingleChildScrollView(
          child: SizedBox(width: 260, child: GreenhouseBody(garden: garden)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Big Beef'), findsNWidgets(2));
    expect(find.text('Growing'), findsOneWidget);
    final ready = garden.inGreenhouse().last.plantOut.start;
    expect(
      find.textContaining('100 plants · ready ${formatDay(ready)}'),
      findsOneWidget,
    );
    expect(find.textContaining('out Apr 20'), findsOneWidget);
    expect(find.byType(Draggable<TrayDrag>), findsNWidgets(2));
    // Flats and pots are started in the Greenhouse tool only.
    expect(find.text('Flats or pots'), findsNothing);
    final drag = tester
        .widgetList<Draggable<TrayDrag>>(find.byType(Draggable<TrayDrag>))
        .last
        .data!;
    expect(drag.outOn, ready, reason: 'goes out when it is ready');
    // Let the "started in the greenhouse" toasts time out.
    await tester.pump(const Duration(seconds: 10));
  });
}
