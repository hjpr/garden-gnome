import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/app_tools.dart';
import 'package:garden_gnome/application/document_session.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/day.dart';
import 'package:garden_gnome/domain/grow/planting.dart';
import 'package:garden_gnome/domain/grow/planting_windows.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import 'package:garden_gnome/persistence/drawing_library.dart';
import 'package:garden_gnome/persistence/workspace_store.dart';
import 'package:garden_gnome/presentation/app_shell.dart';
import 'package:garden_gnome/presentation/garden/calendar_presentation.dart';
import 'package:garden_gnome/presentation/garden/climate_bar.dart';
import 'package:garden_gnome/presentation/garden/commit_field.dart';
import 'package:garden_gnome/presentation/garden/crop_notes.dart';
import 'package:garden_gnome/presentation/garden/crop_range_field.dart';
import 'package:garden_gnome/presentation/garden/timeline.dart';
import 'package:garden_gnome/presentation/theme.dart';
import 'package:garden_gnome/presentation/tool_switcher.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';

Future<(AppNavigator, GardenController)> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final toasts = ToastCenter();
  final session = DocumentSession(
    library: BrowserDrawingLibrary(factory: newIdbFactoryMemory()),
    workspace: WorkspaceStore(),
    codec: const GgnomeCodec(),
  );
  final garden = GardenController(
    store: MemoryGardenRecordStore(),
    toasts: toasts,
    catalog: testCatalog,
    clock: () => DateTime(2026, 4, 1),
  );
  await garden.load();
  final navigator = AppNavigator();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: AppShell(navigator: navigator, session: session, garden: garden),
    ),
  );
  await tester.pumpAndSettle();
  return (navigator, garden);
}

final _todayButton = find.ancestor(
  of: find.widgetWithText(TextButton, 'Today'),
  matching: find.byType(Visibility),
);

Finder _gardenField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is CommitField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

void main() {
  test(
    'calendar presentation keeps the shared range, colours and timing copy',
    () {
      final today = DateTime.utc(2026, 4, 1);
      final range = calendarRange(today);
      expect(today.difference(range.start).inDays, 61);
      expect(range.end.difference(today).inDays, 61);
      expect(windowColor(WindowKind.directSow), Palette.directSow);
      expect(windowColor(WindowKind.greenhouseSow), Palette.greenhouse);
      expect(windowColor(WindowKind.plantOut), Palette.plantOut);

      final profile = const Variety(
        id: 'variety-1',
        cropId: 'tomatoes',
        name: 'Big Beef',
      ).resolve(testTomato);
      final window = PlantingWindow(
        profile: profile,
        kind: WindowKind.greenhouseSow,
        season: PlantingSeason.spring,
        span: DayWindow(DateTime.utc(2026, 4, 1), DateTime.utc(2026, 4, 30)),
        ideal: DayWindow(DateTime.utc(2026, 4, 10), DateTime.utc(2026, 4, 20)),
      );
      for (final (day, timing, detail, color) in [
        (
          DateTime.utc(2026, 3, 31),
          Timing.upcoming,
          'opens Apr 1',
          Palette.muted,
        ),
        (
          DateTime.utc(2026, 4, 1),
          Timing.early,
          'ideal from Apr 10',
          Palette.caution,
        ),
        (
          DateTime.utc(2026, 4, 10),
          Timing.ideal,
          'ideal until Apr 20',
          Palette.valid,
        ),
        (
          DateTime.utc(2026, 4, 21),
          Timing.late,
          'closes Apr 30',
          Palette.caution,
        ),
        (
          DateTime.utc(2026, 5, 1),
          Timing.passed,
          'closed Apr 30',
          Palette.faint,
        ),
      ]) {
        final recommendation = Recommendation(window, day);
        expect(recommendation.timing, timing);
        expect(timingDetail(recommendation), detail);
        expect(timingColor(timing), color);
      }
    },
  );

  test(
    'frost input accepts named and numeric dates and rejects unreadable text',
    () {
      for (final text in [
        'Apr 20',
        ' april 20 ',
        'Apr. 20',
        '4/20',
        '04-20',
        '4.20',
      ]) {
        expect(parseMonthDay(text), const MonthDay(4, 20), reason: text);
      }
      for (final text in ['', 'spring', 'Foo 20', '13/20', '4/32', '4/0']) {
        expect(parseMonthDay(text), isNull, reason: text);
      }
    },
  );

  testWidgets(
    'CommitField commits on Enter and blur and reverts errors on Escape',
    (tester) async {
      var value = 'Stored';
      final changes = <String>[];
      final otherFocus = FocusNode();
      addTearDown(otherFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  CommitField(
                    label: 'Name',
                    value: value,
                    commit: (text) {
                      if (text.trim().isEmpty) return 'Enter a name';
                      changes.add(text);
                      setState(() => value = text);
                      return null;
                    },
                  ),
                  TextField(focusNode: otherFocus),
                ],
              ),
            ),
          ),
        ),
      );
      final field = _gardenField('Name');
      await tester.enterText(field, 'Entered');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, 'Entered');

      await tester.enterText(field, 'Blurred');
      otherFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(value, 'Blurred');

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, 'Blurred');
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.tap(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Blurred');
      expect(find.text('Enter a name'), findsNothing);
      expect(changes, isNot(contains('')));
    },
  );

  testWidgets(
    'CommitField keeps focused text local and shows external values when idle',
    (tester) async {
      var value = 'Stored';
      var enabled = true;
      var commits = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CommitField(
                  label: 'Name',
                  value: value,
                  enabled: enabled,
                  commit: (text) {
                    commits++;
                    setState(() => value = text);
                    return null;
                  },
                );
              },
            ),
          ),
        ),
      );
      final field = _gardenField('Name');
      rebuild(() => value = 'External');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'External');

      await tester.enterText(field, 'Local draft');
      rebuild(() => value = 'Latest stored');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'Local draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Latest stored');
      expect(commits, 0);

      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).enabled, isFalse);
      await tester.tap(field);
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(commits, 0);
    },
  );

  testWidgets('crop ranges preserve input forms, errors and blank defaults', (
    tester,
  ) async {
    IntRange? value;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CropRangeField(
              label: 'Maturity',
              value: value,
              fallback: const IntRange(70, 80),
              unit: 'days',
              onCommitted: (range) => setState(() => value = range),
            ),
          ),
        ),
      ),
    );
    final field = _gardenField('Maturity');
    expect(tester.widget<TextField>(field).decoration!.hintText, '70–80 days');
    for (final (input, expected) in [
      ('5-7', const IntRange(5, 7)),
      ('8–9', const IntRange(8, 9)),
      ('11—10', const IntRange(10, 11)),
      (' 80 to 70 ', const IntRange(70, 80)),
      ('6', const IntRange.single(6)),
    ]) {
      await tester.enterText(field, input);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, expected, reason: input);
    }
    for (final input in ['soon', '-5', '1.5', '10000', '5-7-9']) {
      await tester.enterText(field, input);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, const IntRange.single(6), reason: input);
      expect(find.text('Enter a number or a range like 5–7'), findsOneWidget);
    }
    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('Enter a number or a range like 5–7'), findsNothing);
    expect(tester.widget<TextField>(field).decoration!.hintText, '70–80 days');
  });

  testWidgets('climate bar keeps frost overrides separate from zone defaults', (
    tester,
  ) async {
    final (navigator, garden) = await _pumpApp(tester);
    navigator.open(AppTool.grow);
    await tester.pumpAndSettle();
    final spring = _gardenField('Last frost');
    final fall = _gardenField('First frost');
    final defaultSpring = garden.climate.zone.lastSpringFrost.toString();
    expect(
      tester.widget<TextField>(spring).decoration!.hintText,
      defaultSpring,
    );
    await tester.enterText(spring, '4/20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(garden.climate.lastSpringFrost, const MonthDay(4, 20));

    await tester.enterText(fall, 'Oct 10');
    await tester.tap(spring);
    await tester.pumpAndSettle();
    expect(garden.climate.firstFallFrost, const MonthDay(10, 10));
    await tester.enterText(spring, 'not a date');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(garden.climate.lastSpringFrost, const MonthDay(4, 20));
    expect(find.text('e.g. Apr 20'), findsOneWidget);

    await tester.enterText(spring, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(garden.climate.lastSpringFrost, isNull);
    expect(
      tester.widget<TextField>(spring).decoration!.hintText,
      defaultSpring,
    );
    expect(garden.climate.firstFallFrost, const MonthDay(10, 10));
  });

  testWidgets(
    'crop notes render catalog facts, estimates, sections and source independently',
    (tester) async {
      final crop = Crop(
        id: 'notes',
        name: 'Notes crop',
        category: 'Vegetables',
        season: Season.cool,
        frostTolerance: FrostTolerance.hardy,
        sowing: SowingMethod.direct,
        daysToMaturity: const IntRange(30, 40),
        plantOutWeeks: const IntRange(-2, 1),
        inRowSpacingIn: const LengthRange.single(6),
        betweenRowSpacingIn: const LengthRange.single(12),
        harvestWindowDays: const IntRange.single(14),
        estimated: {'daysToMaturity'},
        sections: [const CropSection('Culture', 'Keep evenly moist.')],
        url: 'https://example.test/crop',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: CropNotes(crop: crop)),
        ),
      );
      expect(find.text('NOTES CROP GROWING NOTES'), findsOneWidget);
      expect(find.text('30–40 days*'), findsOneWidget);
      expect(find.byTooltip('Estimated'), findsOneWidget);
      expect(find.text('* Estimated'), findsOneWidget);
      expect(find.text('2 wk before – 1 wk after'), findsOneWidget);
      expect(find.text('CULTURE'), findsOneWidget);
      expect(find.text('Keep evenly moist.'), findsOneWidget);
      expect(find.text('Source: https://example.test/crop'), findsOneWidget);
    },
  );

  testWidgets(
    'add-variety dialog searches varieties and crops, cancels and submits on Enter',
    (tester) async {
      final (navigator, garden) = await _pumpApp(tester);
      navigator.open(AppTool.seedVault);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add variety'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );
      final search = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, '  ToM  ');
      await tester.pumpAndSettle();
      expect(find.text('Big Beef'), findsOneWidget);
      expect(find.text('Sun Gold'), findsOneWidget);
      expect(find.text('Lettuce'), findsNothing);
      await tester.enterText(search, 'gOlD');
      await tester.pumpAndSettle();
      expect(find.text('Sun Gold'), findsOneWidget);
      expect(find.text('Big Beef'), findsNothing);
      await tester.tap(find.text('Sun Gold'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(garden.record.varieties, isEmpty);

      await tester.tap(find.text('Add variety'));
      await tester.pumpAndSettle();
      expect(find.text('Little Gem'), findsOneWidget);
      await tester.tap(find.text('Little Gem'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(garden.record.varieties.values.single.name, 'Little Gem');
      expect(garden.record.varieties.values.single.cropId, 'lettuce');
      expect(find.text('LETTUCE GROWING NOTES'), findsOneWidget);
    },
  );

  testWidgets(
    'searching away from a selected variety cannot add the hidden result',
    (tester) async {
      final (navigator, garden) = await _pumpApp(tester);
      navigator.open(AppTool.seedVault);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add variety'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Big Beef'));
      final search = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'no such variety');
      await tester.pumpAndSettle();
      expect(find.text('No varieties match.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(garden.record.varieties, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(search, 'Vegetables');
      await tester.pumpAndSettle();
      expect(find.text('Big Beef'), findsOneWidget);
      expect(find.text('Little Gem'), findsOneWidget);
    },
  );

  testWidgets(
    'variety selection isolates overrides and removal clears the details',
    (tester) async {
      final (navigator, garden) = await _pumpApp(tester);
      final tomato = garden.addVariety('tomatoes', 'Big Beef');
      final lettuce = garden.addVariety('lettuce', 'Little Gem');
      navigator.open(AppTool.seedVault);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Big Beef'));
      await tester.pumpAndSettle();
      await tester.enterText(_gardenField('Maturity'), '68');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        garden.record.varieties[tomato]!.daysToMaturity,
        const IntRange.single(68),
      );
      await tester.tap(find.text('Little Gem'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_gardenField('Maturity')).controller!.text,
        '',
      );
      expect(
        tester.widget<TextField>(_gardenField('Maturity')).decoration!.hintText,
        '45–55 days',
      );
      expect(garden.record.varieties[lettuce]!.daysToMaturity, isNull);
      expect(find.text('LETTUCE GROWING NOTES'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Little Gem'));
      await tester.pumpAndSettle();
      expect(garden.record.varieties.containsKey(lettuce), isFalse);
      expect(garden.record.varieties.containsKey(tomato), isTrue);
      expect(find.text('Nothing selected.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    },
  );

  testWidgets('home lists the tools and opens one', (tester) async {
    final (navigator, _) = await _pumpApp(tester);
    for (final tool in AppTool.values) {
      expect(find.text(tool.label), findsOneWidget);
    }
    await tester.tap(find.text('Seed Vault'));
    await tester.pumpAndSettle();
    expect(navigator.current, AppTool.seedVault);
    expect(find.text('Add a variety to start.'), findsOneWidget);
  });

  testWidgets('add a variety in the Seed Vault and edit an override', (
    tester,
  ) async {
    final (navigator, garden) = await _pumpApp(tester);
    navigator.open(AppTool.seedVault);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add variety'));
    await tester.pumpAndSettle();
    expect(find.text('Big Beef'), findsOneWidget);
    expect(find.textContaining('Variety name'), findsNothing);
    final varietyText = tester.widget<Text>(find.text('Big Beef'));
    final cropText = tester.widget<Text>(find.text('Tomatoes').first);
    expect(cropText.style!.fontSize, lessThan(varietyText.style!.fontSize!));
    expect(cropText.style!.color, Palette.faint);
    expect(
      tester.getTopLeft(find.text('Tomatoes').first).dx,
      greaterThan(tester.getTopLeft(find.text('Big Beef')).dx),
    );
    await tester.tap(find.text('Big Beef'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final v = garden.record.varieties.values.single;
    expect(v.name, 'Big Beef');
    expect(v.cropId, 'tomatoes');
    expect(find.text('Tomatoes growing notes'.toUpperCase()), findsOneWidget);

    // Blank boxes show the crop's value as a hint; typing overrides it.
    final box = find.ancestor(
      of: find.text('70–80 days'),
      matching: find.byType(TextField),
    );
    expect(box, findsOneWidget);
    await tester.enterText(box, '68');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(garden.record.varieties[v.id]!.daysToMaturity!.min, 68);
  });

  testWidgets('Greenhouse lists what to start and records the sowing', (
    tester,
  ) async {
    final (navigator, garden) = await _pumpApp(tester);
    garden.addVariety('tomatoes', 'Big Beef');
    navigator.open(AppTool.greenhouse);
    await tester.pumpAndSettle();

    final range = tester.widget<Timeline>(find.byType(Timeline)).range;
    expect(range, calendarRange(garden.today));
    // Apr 1 in zone 6a: tomato trays are ideal to start now.
    // In the calendar's Upcoming section and in Start next.
    expect(find.textContaining('Spring · ideal until'), findsNWidgets(2));
    expect(find.text('GROWING  0'), findsOneWidget);
    expect(find.text('UPCOMING  1'), findsOneWidget);
    await tester.tap(find.byTooltip('Start in greenhouse'));
    await tester.pumpAndSettle();
    // Two flats of 50 cells.
    await tester.enterText(find.byKey(const ValueKey('tray-Flats')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('tray-Cells per flat')),
      '50',
    );
    await tester.pumpAndSettle();
    expect(find.text('100 plants to plant out'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final tray = garden.schedules(PlantingStage.greenhouse).single.planting;
    expect(tray.container, GrowContainer.flat);
    expect(tray.plants, 100);

    navigator.open(AppTool.greenhouse);
    await tester.pumpAndSettle();
    expect(tester.widget<Timeline>(find.byType(Timeline)).range, range);
    expect(find.textContaining('Sown Apr 1'), findsOneWidget);
    expect(find.textContaining('2 flats × 50 = 100 plants'), findsOneWidget);
    await tester.tap(find.byTooltip('Planted out today'));
    await tester.pumpAndSettle();

    // From Start next the seed is fixed; Add plant asks for it. Both
    // start today unless the date is changed.
    await tester.tap(find.byTooltip('Start in greenhouse'));
    await tester.pumpAndSettle();
    expect(find.text('Start Big Beef · Tomatoes'), findsOneWidget);
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Seed'),
      findsNothing,
    );
    expect(find.text('Apr 1, 2026'), findsOneWidget, reason: 'today');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add plant'));
    await tester.pumpAndSettle();
    expect(find.text('Start in greenhouse'), findsOneWidget);
    expect(find.text('Seed'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing in the greenhouse.'), findsOneWidget);

    // Dragging the chart moves through time; the wheel zooms; Today
    // brings the view back.
    expect(find.byKey(const ValueKey('calendar-today')), findsOneWidget);
    expect(find.text('Wednesday, Apr 1, 2026'), findsOneWidget);
    bool todayShown() => tester.widget<Visibility>(_todayButton).visible;
    expect(todayShown(), isFalse);
    final chart =
        tester.getCenter(find.byType(Timeline)) + const Offset(300, 0);
    await tester.dragFrom(chart, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(todayShown(), isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();
    expect(todayShown(), isFalse);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(chart));
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    }
    await tester.pumpAndSettle();
    expect(todayShown(), isTrue, reason: 'zoomed out');
    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();

    navigator.open(AppTool.harvest);
    await tester.pumpAndSettle();
    expect(find.textContaining('Planted out Apr 1'), findsOneWidget);
    expect(tester.widget<Timeline>(find.byType(Timeline)).range, range);
    await tester.tap(find.byTooltip('Harvest finished'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing planted yet.'), findsOneWidget);
    expect(garden.schedules(PlantingStage.inGround), isEmpty);
    // Let the "started in the greenhouse" toast time out.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'the shared switcher navigates every tool without a garden page',
    (tester) async {
      final navigator = AppNavigator();
      addTearDown(navigator.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: navigator,
              builder: (context, _) => Align(
                alignment: Alignment.topLeft,
                child: ToolSwitcher(navigator: navigator),
              ),
            ),
          ),
        ),
      );
      for (final tool in AppTool.values) {
        await tester.tap(find.byTooltip('Switch tool'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, tool.label));
        await tester.pumpAndSettle();
        expect(navigator.current, tool);
        expect(find.text(tool.label), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Switch tool'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Home'));
      await tester.pumpAndSettle();
      expect(navigator.current, isNull);
      expect(find.text('Garden Gnome'), findsOneWidget);
    },
  );

  testWidgets('the header switcher moves between tools and back home', (
    tester,
  ) async {
    final (navigator, _) = await _pumpApp(tester);
    navigator.open(AppTool.harvest);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch tool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grow').last);
    await tester.pumpAndSettle();
    expect(navigator.current, AppTool.grow);

    await tester.tap(find.byTooltip('Switch tool').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(navigator.current, isNull);
  });
}
