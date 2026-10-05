import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/planting.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/persistence/crop_catalog_codec.dart';
import 'package:garden_gnome/persistence/garden_record_codec.dart';
import 'package:garden_gnome/presentation/garden/commit_field.dart';
import 'package:garden_gnome/presentation/garden/variety_detail.dart';
import 'package:garden_gnome/presentation/theme.dart';

import '../support/memory_garden_record_store.dart';

CropCatalog catalog() =>
    decodeCropCatalog(File('assets/catalog/crops.json').readAsStringSync());

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is CommitField && w.label == label),
  matching: find.byType(TextField),
);

void main() {
  for (final (id, low, high) in [
    ('arugula', 0.5, 1),
    ('carrots', 0.75, 2),
    ('peas', 1.5, 2),
  ]) {
    test('real $id asset retains fractional spacing through seed defaults', () {
      final crop = catalog()[id]!;
      expect(crop.inRowSpacingIn.min, low);
      expect(crop.inRowSpacingIn.max, high);
      expect(crop.daysToMaturity.min, isA<int>());
      expect(crop.plantOutWeeks.min, isA<int>());
      final profile = Variety(id: 'v', cropId: id, name: 'Test').resolve(crop);
      final seed = seedFromProfile(profile);
      expect(seed.inRow, closeTo(low * metresPerInch, 1e-12));
      expect(
        seed.betweenRows,
        closeTo(crop.betweenRowSpacingIn.min * metresPerInch, 1e-12),
      );
    });
  }

  test('fractional overrides round-trip in the existing JSON pair shape', () {
    final source = jsonEncode({
      'version': 1,
      'counter': 1,
      'varieties': [
        {
          'id': 'variety-1',
          'crop': 'arugula',
          'name': 'Test',
          'in_row_spacing_in': [0.75, 1.5],
          'between_row_spacing_in': [2.25, 6.5],
          'days_to_maturity': [21, 40],
          'weeks_to_transplant': [3, 4],
        },
      ],
    });
    final record = decodeGardenRecord(source);
    final encoded = encodeGardenRecord(record);
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final values = (json['varieties'] as List).single as Map;
    expect(values['in_row_spacing_in'], [0.75, 1.5]);
    expect(values['between_row_spacing_in'], [2.25, 6.5]);
    final back = decodeGardenRecord(encoded).varieties['variety-1']!;
    expect(back.inRowSpacingIn!.min, 0.75);
    expect(back.betweenRowSpacingIn!.min, 2.25);
    expect(back.daysToMaturity!.min, isA<int>());
    expect(back.weeksToTransplant!.min, isA<int>());
    final profile = back.resolve(catalog()['arugula']!);
    final seed = seedFromProfile(profile);
    expect(seed.inRow, closeTo(0.75 * metresPerInch, 1e-12));
    expect(seed.betweenRows, closeTo(2.25 * metresPerInch, 1e-12));
    final defaults = back
        .copyWith(inRowSpacingIn: () => null, betweenRowSpacingIn: () => null)
        .resolve(profile.crop);
    expect(defaults.inRowSpacingIn.min, 0.5);
    expect(defaults.betweenRowSpacingIn.min, 2);
  });

  testWidgets(
    'variety spacing inputs save fractions and clear to crop defaults',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryGardenRecordStore(
        GardenRecord(
          varieties: {
            'variety-1': const Variety(
              id: 'variety-1',
              cropId: 'arugula',
              name: 'Test',
            ),
          },
        ),
      );
      final toasts = ToastCenter();
      final garden = GardenController(
        store: store,
        toasts: toasts,
        catalog: catalog(),
      );
      await garden.load();
      addTearDown(garden.dispose);
      addTearDown(toasts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: garden,
              builder: (context, child) => VarietyDetail(
                garden: garden,
                profile: garden.profileOf('variety-1')!,
              ),
            ),
          ),
        ),
      );
      for (final (label, input, low, high) in [
        ('In-row', '.75 to 1.5', 0.75, 1.5),
        ('Between rows', '6.5–2.25', 2.25, 6.5),
      ]) {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), input);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final saved = (await store.load()).varieties['variety-1'];
        final range = label == 'In-row'
            ? saved?.inRowSpacingIn
            : saved?.betweenRowSpacingIn;
        expect(range?.min, low);
        expect(range?.max, high);
      }
      for (final label in ['Maturity', 'In trays']) {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), '1.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('Enter a number or a range like 5–7'), findsOneWidget);
        await tester.enterText(field(label), '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      for (final label in ['In-row', 'Between rows']) {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      final profile = garden.profileOf('variety-1')!;
      expect(profile.variety.inRowSpacingIn, isNull);
      expect(profile.variety.betweenRowSpacingIn, isNull);
      expect(profile.inRowSpacingIn.min, 0.5);
      expect(
        tester.widget<TextField>(field('In-row')).decoration!.hintText,
        '0.5–1 in',
      );
      expect(
        seedFromProfile(profile).inRow,
        closeTo(0.5 * metresPerInch, 1e-12),
      );
    },
  );
}
