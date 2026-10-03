import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/farm.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/presentation/garden/grow_screen.dart';
import 'package:garden_gnome/presentation/garden/timeline.dart';

import '../support/grow_fixtures.dart';
import '../support/ground_fixtures.dart' as map;
import '../support/memory_garden_record_store.dart';
import '../support/widget_harness.dart';

/// A garden whose farm has one planting layer, planted with bush beans
/// when [planBeans], and a vault holding beans and lettuce.
Future<(GardenController, String)> _garden({required bool planBeans}) async {
  final farm = DetachedFarm();
  final garden = GardenController(
    store: MemoryGardenRecordStore(),
    toasts: ToastCenter(),
    catalog: testCatalog,
    clock: () => DateTime(2026, 4, 20),
    farm: farm,
  );
  await garden.load();
  final bean = garden.addVariety('bush-bean', 'Provider');
  garden.addVariety('lettuce', 'Little Gem');
  final (editor, _, _, grow) = map.garden(GroundType.flat);
  if (planBeans) {
    editor.setSeed(
      grow,
      ZoneSeed(
        varietyId: bean,
        name: 'Provider · Bush Beans',
        size: map.seed().size,
        spacing: map.seed().spacing,
      ),
    );
  }
  farm.changeFarm('Map', (_) => editor.document);
  return (garden, grow);
}

void main() {
  test(
    'only planting layers with a seed and nothing sown can be sown',
    () async {
      final (garden, grow) = await _garden(planBeans: true);
      final planned = garden.plannedSowings().single;
      expect(planned.layerId, grow);
      expect(planned.profile.variety.name, 'Provider');
      expect(planned.plants, greaterThan(0));

      garden.sowPlanting(grow, on: DateTime(2026, 4, 25));
      expect(garden.plannedSowings(), isEmpty);
      final sown = garden.directSowings().single.planting;
      expect(sown.layerId, grow);
      expect(sown.sownOn, DateTime.utc(2026, 4, 25));
      expect(garden.farm.farm.currentPlantingOf(grow)!.id, sown.id);
    },
  );

  testWidgets('Grow sows planned plantings; unplanned ones are greyed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (garden, grow) = await _garden(planBeans: true);
    await tester.pumpWidget(
      testApp(
        child: ListenableBuilder(
          listenable: garden,
          builder: (_, _) => GrowBody(garden: garden),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Growing (nothing sown yet) sits above Upcoming, and Upcoming runs
    // soonest sowing first, planned and unplanned together.
    expect(find.text('GROWING  0'), findsOneWidget);
    expect(find.text('Nothing sown.'), findsOneWidget);
    final upcomingTop = tester.getTopLeft(find.textContaining('UPCOMING')).dy;
    expect(
      tester.getTopLeft(find.text('GROWING  0')).dy,
      lessThan(upcomingTop),
    );
    final order = [
      for (final r in garden.recommendations())
        if (r.window.kind.name == 'directSow') r,
    ]..sort((a, b) => a.window.ideal.start.compareTo(b.window.ideal.start));
    // One row per variety, placed at its soonest window.
    final titles = {for (final r in order) r.profile.displayName}.toList();
    expect(
      find.descendant(
        of: find.byType(Timeline),
        matching: find.text('Little Gem · Lettuce'),
      ),
      findsOneWidget,
      reason: 'spring and fall windows share one row',
    );
    double top(String title) => tester
        .getTopLeft(
          find.descendant(
            of: find.byType(Timeline),
            matching: find.text(title),
          ),
        )
        .dy;
    for (var i = 1; i < titles.length; i++) {
      expect(top(titles[i - 1]), lessThan(top(titles[i])));
    }

    // Lettuce has a window but no planting: greyed, with the reason.
    expect(find.textContaining('not planned'), findsWidgets);
    final lettuceSow = find.byTooltip(GrowBody.planFirst);
    expect(lettuceSow, findsWidgets);

    // Beans are planned: Sow opens the dialog fixed to that planting.
    await tester.tap(find.byTooltip('Sow Provider').first);
    await tester.pumpAndSettle();
    expect(find.text('Sow Provider · Bush Beans'), findsOneWidget);
    final plants = garden.plannedPlantsOf(grow)!;
    expect(find.text('$plants plants'), findsOneWidget);
    expect(find.text('Apr 20, 2026'), findsOneWidget, reason: 'today');
    await tester.tap(find.widgetWithText(FilledButton, 'Sow'));
    await tester.pumpAndSettle();
    expect(garden.directSowings(), hasLength(1));
    expect(find.text('Sown'), findsOneWidget);

    // Nothing left to plan: Add plant is greyed.
    final add = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add plant'),
    );
    expect(add.onPressed, isNull);
    await tester.pump(const Duration(seconds: 10));
  });
}
