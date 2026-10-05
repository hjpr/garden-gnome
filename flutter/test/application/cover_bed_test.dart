import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/farm.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/planting.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/plant_layout.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/persistence/document_json.dart';

import '../support/editor_input.dart';
import '../support/ground_fixtures.dart';
import '../support/grow_fixtures.dart';
import '../support/memory_garden_record_store.dart';

const _rye = CoverDrag(
  varietyId: 'variety-9',
  name: 'Winter Rye (Common) · Winter Rye',
);

CoverSowing? _coverOf(EditorController editor, String id) =>
    (editor.document.layers[id]!.properties as ZoneProperties).cover;

void main() {
  test('the Ground tool goes Fallow, Cover, Flat, Row and sets Cover', () {
    expect(Tool.ground.functions, [
      ToolFunction.clearGround,
      ToolFunction.coverGround,
      ToolFunction.flatGround,
      ToolFunction.rowGround,
    ]);
    final (editor, input, _, zone) = farm();
    editor.selectTool(Tool.ground);
    editor.selectFunction(ToolFunction.coverGround);
    click(input, 5, 5);
    expect(editor.document.storedGroundOf(zone), GroundType.cover);
    expect(editor.undoLabel, 'Cover ground');
  });

  test('a planting over a Cover bed plants nothing and refuses seed', () {
    final (editor, _, soil, grow) = garden(GroundType.cover);
    editor.setMode(EditMode.plant);
    final profile = VarietyProfile(
      const Variety(id: 'variety-7', cropId: 'lettuce', name: 'Buttercrunch'),
      testLettuce,
    );
    expect(editor.document.isOverCover(grow), isTrue);
    expect(dropTargetAt(editor, profile, const Vec(6, 6)), isNull);
    expect(dropSeed(editor, profile, const Vec(6, 6)), isFalse);
    expect(editor.notice, overCoverNotice);
    expect(
      (editor.document.layers[grow]!.properties as ZoneProperties).seed,
      isNull,
    );
    // A seed planted before the bed became Cover lays out nothing.
    editor.setMode(EditMode.build);
    editor.setGround(soil, GroundType.flat);
    editor.setSeed(grow, seed());
    expect(editor.document.plantLayoutOf(grow)!.count, greaterThan(0));
    editor.setGround(soil, GroundType.cover);
    expect(editor.document.plantLayoutOf(grow)?.count ?? 0, 0);
  });

  test('cover crops drop only on Cover beds, keeping their dates', () {
    final (editor, _, soil, _) = garden(GroundType.flat);
    editor.setMode(EditMode.plant);
    // Outside the planting, on the Flat bed: not a Cover bed.
    expect(dropCover(editor, _rye, const Vec(3, 3)), isFalse);
    expect(editor.notice, 'Drop cover crops inside a Cover bed');

    editor.setMode(EditMode.build);
    editor.setGround(soil, GroundType.cover);
    editor.setMode(EditMode.plant);
    expect(editor.isPlantable(soil), isTrue);
    expect(dropTargetAt(editor, _rye, const Vec(3, 3)), soil);
    expect(dropCover(editor, _rye, const Vec(3, 3)), isTrue);
    expect(editor.selectedLayerId, soil);
    expect(_coverOf(editor, soil)!.name, _rye.name);
    expect(editor.undoLabel, 'Sow ${_rye.name}');

    final sown = DateTime.utc(2026, 9, 10);
    editor.setCover(soil, _coverOf(editor, soil)!.copyWith(sownOn: () => sown));
    const clover = CoverDrag(varietyId: 'v-2', name: 'Crimson · Clover');
    dropCover(editor, clover, const Vec(3, 3));
    expect(_coverOf(editor, soil)!.varietyId, 'v-2');
    expect(_coverOf(editor, soil)!.sownOn, sown);

    // Terminated never runs before Sown.
    editor.setCover(
      soil,
      _coverOf(
        editor,
        soil,
      )!.copyWith(terminatedOn: () => DateTime.utc(2026, 9, 1)),
    );
    expect(editor.notice, 'Terminated cannot be before Sown');
  });

  test('a Cover bed and its dates survive saving', () {
    final (editor, _, soil, _) = garden(GroundType.cover);
    editor.setCover(
      soil,
      CoverSowing(
        varietyId: 'variety-9',
        name: 'Winter Rye',
        sownOn: DateTime.utc(2026, 9, 10),
        terminatedOn: DateTime.utc(2027, 5, 1),
      ),
    );
    final json = jsonDecode(jsonEncode(documentToJson(editor.document)));
    expect(json['schema_version'], schemaVersion);
    final back = documentFromJson(json);
    final props = back.layers[soil]!.properties as ZoneProperties;
    expect(props.ground, GroundType.cover);
    expect(props.cover, _coverOf(editor, soil));
  });

  test('Grow lists a dated cover crop until it is terminated', () async {
    final (editor, _, soil, _) = garden(GroundType.cover);
    GardenController growOn(CoverSowing cover) {
      editor.setCover(soil, cover);
      return GardenController(
        store: MemoryGardenRecordStore(),
        toasts: ToastCenter(),
        catalog: testCatalog,
        clock: () => DateTime(2026, 10, 3),
        farm: DetachedFarm(editor.document),
      );
    }

    const undated = CoverSowing(varietyId: 'variety-9', name: 'Winter Rye');
    expect(growOn(undated).coverBeds(), isEmpty, reason: 'not dated yet');
    final grow = growOn(
      undated.copyWith(sownOn: () => DateTime.utc(2026, 9, 1)),
    );
    expect(grow.coverBeds().single.layerId, soil);
    grow.terminateCover(soil);
    final after = grow.farm.farm.layers[soil]!.properties as ZoneProperties;
    expect(after.cover!.terminatedOn, DateTime.utc(2026, 10, 3));
    expect(grow.coverBeds(), isEmpty);
  });

  test('seed needed follows the chart rate and the bed area', () {
    final rate = SeedRate.parse('⅓–½ Lb.')!;
    expect(rate.min, closeTo(1 / 3, 1e-9));
    expect(rate.max, 0.5);
    // 100 m² is about 1,076 sq ft.
    expect(rate.amountFor(100), '≈ 0.4–0.5 lb');
    expect(SeedRate.parse('1½ Lb.')!.min, 1.5);
    // 1,000 m² is about 10,764 sq ft; ten pounds and over show no decimal.
    expect(SeedRate.parse('2–3 Lb.')!.amountFor(1000), '≈ 22–32 lb');
    expect(SeedRate.parse('¼ Lb.')!.amountFor(20), '≈ 0.9 oz');
    expect(SeedRate.parse('1,500 seeds')!.amountFor(10), '≈ 161 seeds');
    expect(SeedRate.parse('Various'), isNull);
    expect(testRye.seedRate!.max, 3);
  });
}
