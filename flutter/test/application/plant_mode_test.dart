import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/alignment.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/curve_handles.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/planting.dart';
import 'package:garden_gnome/application/selection_box.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/plant_layout.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

import '../support/grow_fixtures.dart';
import '../support/editor_input.dart';
import '../support/ground_fixtures.dart';

const inch = 0.0254;

void main() {
  group('Ground tool functions', () {
    test('Fallow clears a bed, and no ground turns a bed into a planting', () {
      final (editor, input, soil, grow) = garden(GroundType.flat);
      editor.selectLayer(soil);
      editor.selectTool(Tool.ground);
      editor.selectFunction(ToolFunction.clearGround);
      click(input, 3, 3);
      expect(editor.undoLabel, 'Fallow ground');
      expect(editor.document.layers[soil]!.role, LayerRole.bed);
      expect(
        (editor.document.layers[soil]!.properties as ZoneProperties).ground,
        isNull,
      );
      expect(
        ToolFunction.values.where((f) => f.groundType == GroundType.grow),
        isEmpty,
      );
      editor.setGround(soil, GroundType.grow);
      expect(editor.isGrowZone(soil), isFalse);
      expect(editor.notice, 'Add a planting in Layers to plant here');

      // The Ground tool leaves plantings alone.
      editor.selectLayer(grow);
      click(input, 6, 6);
      expect(editor.notice, CanvasInput.groundNeedsBed);
      expect(editor.isGrowZone(grow), isTrue);
    });
  });

  group('Plant layout', () {
    test('zero gap tiles flat ground with touching footprints', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(size: 0.5, spacing: 0));
      final layout = editor.document.plantLayoutOf(grow)!;
      expect(layout.count, 96); // Eight lines of twelve touching plants.
      expect(
        layout.positions.map((p) => p.x).reduce((a, b) => a < b ? a : b),
        4.25,
      );
      final before = editor.document;
      editor.setSeed(grow, seed(size: 0.5, spacing: -0.1));
      expect(editor.document, same(before));
      expect(editor.notice, contains('spacing'));
    });

    test('one footprint fits without needing a trailing empty gap', () {
      final (editor, _, flat, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(size: 4, spacing: 100));
      expect(editor.document.plantLayoutOf(grow)!.positions, [const Vec(6, 7)]);
      editor.setSeed(grow, seed(size: 4.01, spacing: 100));
      expect(editor.document.plantLayoutOf(grow)!.count, 0);
      editor.setRows(flat, const RowSpec(direction: 90));
      editor.setSeed(grow, seed(size: 5, spacing: 100));
      // Across span is 6 m, but the 4 m run cannot fit a 5 m diameter.
      expect(editor.document.plantLayoutOf(grow)!.count, 0);
    });

    test('dense planting retains the existing storage and line limits', () {
      final (editor, _, soil, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(size: 0.01, spacing: 0));
      final grid = editor.document.plantLayoutOf(grow)!;
      expect(grid.count, 240000); // 400 lines * 600 plants.
      expect(grid.positions.length, PlantLayout.maxPositions);
      editor.setSeed(grow, seed(size: 0.0009, spacing: 0));
      expect(editor.document.plantLayoutOf(grow)!.count, 0);
      editor.setGround(soil, GroundType.row);
      editor.setRows(soil, const RowSpec(width: 1, spacing: 0));
      editor.setSeed(grow, seed(size: 0.01, spacing: 0));
      expect(editor.document.plantLayoutOf(grow)!.lines.length, 48);
    });

    test('empty spacing increases centre pitch even on a single-line bed', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      editor.setRows(soil, const RowSpec(width: 0.5, spacing: 0.5));
      editor.setSeed(grow, seed(size: 0.5, spacing: 1));
      final layout = editor.document.plantLayoutOf(grow)!;
      // Four beds cross the grow zone. A 6 m run fits four 0.5 m
      // footprints with three 1 m empty gaps (5 m occupied in total).
      expect(layout.count, 16);
      for (final line in layout.lines) {
        final ys =
            layout.positions
                .where((p) => p.x == line.start.x)
                .map((p) => p.y)
                .toList()
              ..sort();
        expect(ys, [4.75, 6.25, 7.75, 9.25]);
      }
      editor.setSeed(grow, seed(size: 0.5, spacing: 0));
      expect(editor.document.plantLayoutOf(grow)!.count, 48);
      editor.undo();
      expect(editor.document.plantLayoutOf(grow)!.count, 16);
      editor.redo();
      expect(editor.document.plantLayoutOf(grow)!.count, 48);
    });

    test('a bed fits whole diameters with gaps only between lines', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      editor.setRows(soil, const RowSpec(width: 1.25, spacing: 0.75));
      editor.setSeed(grow, seed(size: 0.5, spacing: 0.25));
      final layout = editor.document.plantLayoutOf(grow)!;
      // Two 0.5 m footprints plus one 0.25 m gap fit exactly per bed.
      // Two beds cross the grow zone; 8 plants fit each 6 m line.
      expect(layout.count, 32);
      // Unbordered beds start at x=2 and repeat every 2 m. The two
      // relevant bed centres are 4.625 and 6.625, with lines ±0.375 m.
      expect(layout.positions.map((p) => p.x).toSet(), {4.25, 5, 6.25, 7});
    });

    test('a plant wider than its bed is not planted', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      editor.setRows(soil, const RowSpec(width: 0.25, spacing: 0.75));
      editor.setSeed(grow, seed(size: 0.5, spacing: 0));
      expect(editor.document.plantLayoutOf(grow)!.count, 0);
    });

    test('flat footprints fit endpoints and use the same gap in both axes', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(size: 0.5, spacing: 1));
      final layout = editor.document.plantLayoutOf(grow)!;
      expect(layout.positions.map((p) => p.x).toSet(), {4.5, 6, 7.5});
      expect(layout.positions.map((p) => p.y).toSet(), {
        4.75,
        6.25,
        7.75,
        9.25,
      });
      for (final p in layout.positions) {
        expect(p.x - 0.25, greaterThanOrEqualTo(4));
        expect(p.x + 0.25, lessThanOrEqualTo(8));
        expect(p.y - 0.25, greaterThanOrEqualTo(4));
        expect(p.y + 0.25, lessThanOrEqualTo(10));
      }
    });

    test(
      'row borders reduce plant counts and keep every planting line clear',
      () {
        final (editor, _, soil, grow) = garden(GroundType.row);
        editor.setRows(soil, const RowSpec(width: 1, spacing: 1));
        editor.setSeed(grow, seed(size: 0.25, spacing: 0.25));
        final before = editor.document.plantLayoutOf(grow)!;
        editor.setRows(soil, const RowSpec(width: 1, spacing: 1, border: 3));
        final layout = editor.document.plantLayoutOf(grow)!;
        // Centred rows at x=6 and x=8: two lines on the first, one on
        // the second inside the grow zone (which ends at x=8).
        expect(layout.count, (2 + 1) * 8);
        expect(layout.count, lessThan(before.count));
        for (final p in layout.positions) {
          expect(p.x, inInclusiveRange(5, 9));
          expect(p.y, inInclusiveRange(5, 9));
        }
        editor.undo();
        expect(editor.document.plantLayoutOf(grow)!.count, before.count);
      },
    );

    test('over Row ground, plants go only along the rows', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      // Rows run north–south, 1 m wide with no path, so each is one line
      // of 0.5 m plants separated by 1 m empty gaps.
      editor.setRows(soil, const RowSpec(width: 1, spacing: 0, direction: 0));
      editor.setSeed(grow, seed(size: 0.5, spacing: 1));
      final layout = editor.document.plantLayoutOf(grow)!;
      // The grow zone is x 4–8 (4 rows, centres 4.5..7.5) and y 4–10
      // (6 m of row each): 4 plants per row (0.5 + 3 * 1.5 = 5 m).
      expect(layout.soils, {GroundType.row});
      expect(layout.count, 16);
      final xs = layout.positions.map((p) => p.x).toSet();
      expect(xs, {4.5, 5.5, 6.5, 7.5}, reason: 'on the row centres only');
    });

    test('Lines caps the plant lines on each row, centred, and survives a '
        'save', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      // One 3 m row fits 5 lines of 0.5 m plants 0.1 m apart.
      editor.setRows(soil, const RowSpec(width: 3, spacing: 0, direction: 0));
      editor.setSeed(grow, seed(size: 0.5, spacing: 0.1));
      final all = editor.document.plantLayoutOf(grow)!;
      editor.setSeed(
        grow,
        seed(size: 0.5, spacing: 0.1).copyWith(lines: () => 2),
      );
      final two = editor.document.plantLayoutOf(grow)!;
      expect(two.count, lessThan(all.count));
      final linesPerRow = all.lines.length ~/ two.lines.length;
      expect(linesPerRow, greaterThan(1));
      // Lines stop at what the spacing fits: 5 lines on a 3 m row.
      expect(
        editor.document.maxLinesOf(grow, seed(size: 0.5, spacing: 0.1)),
        5,
      );
      editor.setSeed(
        grow,
        seed(size: 0.5, spacing: 0.1).copyWith(lines: () => 99),
      );
      ZoneSeed stored() =>
          (editor.document.layers[grow]!.properties as ZoneProperties).seed!;
      expect(stored().lines, 5);
      expect(editor.document.plantLayoutOf(grow)!.count, all.count);
      // Widening the spacing brings Lines down with it.
      editor.setSeed(grow, stored().copyWith(spacing: 0.5));
      expect(stored().lines, 3);

      final reopened = decodeGgnome(encodeGgnome(editor.document));
      final props = reopened.layers[grow]!.properties as ZoneProperties;
      expect(props.seed!.lines, 3);
      expect(seed().copyWith(lines: () => 0).problem, isNotNull);
    });

    test('a wide row takes several lines at the seed spacing', () {
      final (editor, _, soil, grow) = garden(GroundType.row);
      editor.setRows(soil, const RowSpec(width: 1, spacing: 0, direction: 0));
      editor.setSeed(grow, seed(size: 0.25, spacing: 0.25));
      final layout = editor.document.plantLayoutOf(grow)!;
      // Two 0.25 m footprints and a 0.25 m gap per 1 m bed;
      // twelve plants occupy 0.25 + 11 * 0.5 = 5.75 m per line.
      expect(layout.count, 96);
    });

    test('over Flat ground, plants go on a grid inside the grow zone', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(size: 0.5, spacing: 1));
      final layout = editor.document.plantLayoutOf(grow)!;
      // Three lines occupy 3.5 m across; four plants occupy 5 m along.
      expect(layout.soils, {GroundType.flat});
      expect(layout.count, 12);
      for (final p in layout.positions) {
        expect(p.x, inInclusiveRange(4, 8));
        expect(p.y, inInclusiveRange(4, 10));
      }
    });

    test('only the part of the grow zone over soil is planted', () {
      final (editor, input, _, _) = garden(GroundType.flat);
      // A second grow zone half over the 2–12 flat zone, half off it.
      final property = editor.document.propertyIds.single;
      editor.selectLayer(property);
      final half = rectangleLayer(
        editor,
        input,
        LayerKind.zone,
        10,
        4,
        14,
        6,
        role: LayerRole.planting,
      );
      editor.setSeed(half, seed(size: 0.5, spacing: 1));
      final layout = editor.document.plantLayoutOf(half)!;
      // Lines at 10.5, 12 and 13.5; only 10.5 is inside soil.
      // Two 0.5 m footprints plus one 1 m gap fit the 2 m run exactly.
      expect(layout.count, 2);
      expect(layout.positions.every((p) => p.x < 12), isTrue);
    });

    test('over plain dirt nothing is planted', () {
      final (editor, _, soil, grow) = garden(GroundType.flat);
      editor.setGround(soil, null);
      editor.setSeed(grow, seed());
      expect(editor.document.plantLayoutOf(grow)!.count, 0);
    });
  });

  group('Plant mode', () {
    test(
      'rejects stale geometry commits and ground changes through Properties',
      () {
        final (editor, _, _, grow) = garden(GroundType.flat);
        final before = editor.document;
        final (candidate, _) = editor.tryGeometryEdit(
          grow,
          (geometry) => geometry.addPoint(const Vec(5, 5)),
        );
        editor.setMode(EditMode.plant);
        editor.commit('Stale drawing', candidate!);
        expect(editor.document, same(before));
        expect(editor.notice, EditorController.plantModeNotice);
        final properties = before.layers[grow]!.properties as ZoneProperties;
        editor.updateProperties(
          grow,
          properties.copyWith(ground: () => GroundType.flat),
        );
        expect(editor.document, same(before));
        editor.updateProperties(
          grow,
          properties.copyWith(crop: () => 'Lettuce'),
        );
        expect(
          (editor.document.layers[grow]!.properties as ZoneProperties).crop,
          'Lettuce',
        );
      },
    );

    test('history cannot cross a layout change while planting', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      final before = editor.document;
      final point = before.geometryOf(grow).points.keys.first;
      final (moved, _) = editor.tryGeometryEdit(
        grow,
        (geometry) => geometry.movePoint(point, const Vec(5, 5)),
      );
      editor.commit('Move', moved!);
      editor.setMode(EditMode.plant);
      expect(editor.canUndo, isFalse);
      editor.undo();
      expect(editor.document, same(moved));
      editor.setSeed(grow, seed());
      expect(editor.canUndo, isTrue);
      editor.undo();
      expect(editor.document, same(moved));
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isTrue);
      editor.redo();
      expect(
        (editor.document.layers[grow]!.properties as ZoneProperties).seed,
        isNotNull,
      );
      editor.undo();
      editor.setMode(EditMode.build);
      editor.undo();
      expect(editor.document, same(before));
      editor.setMode(EditMode.plant);
      expect(editor.canRedo, isFalse);
      editor.redo();
      expect(editor.document, same(before));
      editor.setMode(EditMode.build);
      expect(editor.canRedo, isTrue);
      editor.redo();
      expect(editor.document, same(moved));
    });

    test('hides curve handles while keeping grow zones selectable', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      final line = editor.document.geometryOf(grow).lines.values.first;
      final (curved, _) = editor.tryGeometryEdit(
        grow,
        (geometry) => geometry.lines[line.id] = line.withHandles(
          const Vec(1, 1),
          Vec.zero,
        ),
      );
      editor.commit('Curve', curved!);
      editor.selectObject(grow, line.id);
      expect(visibleCurveHandles(editor), isNotEmpty);
      editor.setMode(EditMode.plant);
      expect(editor.selectedLayerId, grow);
      expect(visibleCurveHandles(editor), isEmpty);
      editor.setMode(EditMode.build);
      expect(visibleCurveHandles(editor), isNotEmpty);
    });

    test('rejects geometry edits even when a grow zone is selected', () {
      final (editor, input, _, grow) = garden(GroundType.flat);
      click(input, 6, 6);
      final before = editor.document;
      editor.setMode(EditMode.plant);
      final (next, problem) = editor.tryGeometryEdit(
        grow,
        (geometry) => geometry.delete(editor.selection),
      );
      expect(next, isNull);
      expect(problem, EditorController.plantModeNotice);
      expect(editor.canDeleteSelection, isFalse);
      editor.deleteSelection();
      expect(editor.document, same(before));
      final geometry = editor.document.geometryOf(grow);
      editor.selectItems(grow, geometry.points.keys.take(2).toSet());
      expect(editor.alignBlocker, EditorController.plantModeNotice);
      expect(editor.booleanBlocker, EditorController.plantModeNotice);
      editor.runAlign(AlignEdge.left);
      editor.runBoolean(BooleanOperation.union);
      expect(editor.document, same(before));
    });

    test('selects grow zones without moving them', () {
      final (editor, input, _, grow) = garden(GroundType.flat);
      editor.setMode(EditMode.plant);
      final before = editor.document;
      input.press(at(6, 6), shift: false);
      input.move(at(7, 7));
      input.release(at(7, 7));
      expect(editor.selectedLayerId, grow);
      expect(editor.document, same(before));
    });

    test('hides transform handles on selected grow zones until Build', () {
      final (editor, input, _, grow) = garden(GroundType.flat);
      click(input, 6, 6);
      expect(selectionBoxOf(editor), isNotNull);
      editor.setMode(EditMode.plant);
      expect(editor.selectedLayerId, grow);
      expect(selectionBoxOf(editor), isNull);
      final before = editor.document;
      input.press(at(4, 4), shift: false);
      input.move(at(3, 3));
      input.release(at(3, 3));
      expect(editor.document, same(before));
      editor.setMode(EditMode.build);
      click(input, 6, 6);
      expect(selectionBoxOf(editor), isNotNull);
    });

    test('allows planting only in unlocked grow zones', () {
      final (editor, input, soil, grow) = garden(GroundType.flat);
      editor.setMode(EditMode.plant);
      expect(editor.lockNotice(soil), EditorController.plantModeNotice);
      expect(editor.lockNotice(grow), isNull);

      // A click on the soil zone's inside (outside the grow zone) passes
      // through; one inside the grow zone picks it.
      click(input, 3, 3);
      expect(editor.selectedLayerId, isNull);
      click(input, 6, 6);
      expect(editor.selectedLayerId, grow);

      editor.renameLayer(soil, 'Nope');
      expect(editor.document.layers[soil]!.name, isNot('Nope'));
      expect(editor.notice, EditorController.plantModeNotice);
    });

    test('offers only selection and restores drawing tools in Build', () {
      final (editor, _, _, _) = garden(GroundType.flat);
      editor.selectTool(Tool.polygon);
      editor.setMode(EditMode.plant);
      expect(editor.tool, Tool.select);
      for (final tool in Tool.values) {
        editor.selectTool(tool);
        expect(editor.tool, Tool.select);
        expect(tool.availableIn(EditMode.plant), tool == Tool.select);
      }
      editor.setMode(EditMode.build);
      editor.selectTool(Tool.polygon);
      expect(editor.tool, Tool.polygon);
    });

    test('cannot add or delete layers in Plant mode', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      final before = editor.document;
      editor.setMode(EditMode.plant);
      for (final kind in LayerKind.values) {
        expect(editor.addLayerBlocker(kind), EditorController.plantModeNotice);
        editor.addLayer(kind);
        expect(editor.document, same(before));
      }
      expect(editor.deleteLayerBlocker(grow), EditorController.plantModeNotice);
      editor.deleteLayer(grow);
      expect(editor.document, same(before));
      editor.setMode(EditMode.build);
      expect(editor.addLayerBlocker(LayerKind.zone), isNull);
      expect(editor.deleteLayerBlocker(grow), isNull);
    });
  });

  group('Dropping seeds', () {
    test(
      'catalog defaults clamp overlapping and broadcast recommendations',
      () {
        for (final (inRow, between, size) in [(8, 4, 8.0), (0, 0, 0.5)]) {
          final planted = seedFromProfile(
            VarietyProfile(
              Variety(
                id: 'v',
                cropId: 'lettuce',
                name: 'Test',
                inRowSpacingIn: LengthRange.single(inRow),
                betweenRowSpacingIn: LengthRange.single(between),
              ),
              testLettuce,
            ),
          );
          expect(planted.size, closeTo(size * inch, 1e-9));
          expect(planted.spacing, 0);
          expect(planted.problem, isNull);
        }
      },
    );

    final profile = VarietyProfile(
      const Variety(id: 'variety-7', cropId: 'lettuce', name: 'Buttercrunch'),
      testLettuce,
    );

    test(
      'lands on the grow zone under the pointer at its smallest spacing',
      () {
        final (editor, _, _, grow) = garden(GroundType.flat);
        editor.setMode(EditMode.plant);
        expect(dropSeed(editor, profile, const Vec(6, 6)), isTrue);
        final planted =
            (editor.document.layers[grow]!.properties as ZoneProperties).seed!;
        expect(planted.varietyId, 'variety-7');
        expect(planted.name, 'Buttercrunch · Lettuce');
        expect(planted.size, closeTo(8 * inch, 1e-9));
        expect(planted.spacing, closeTo(4 * inch, 1e-9));
        expect(planted.pitch, closeTo(12 * inch, 1e-9));
        expect(editor.selectedLayerId, grow);
        expect(editor.undoLabel, 'Plant Buttercrunch · Lettuce');
      },
    );

    test('outside a grow zone plants nothing', () {
      final (editor, _, _, _) = garden(GroundType.flat);
      editor.setMode(EditMode.plant);
      expect(dropSeed(editor, profile, const Vec(3, 3)), isFalse);
      expect(editor.notice, 'Drop seeds inside a planting');
    });

    test('dropping the same variety again keeps changed spacings', () {
      final (editor, _, _, grow) = garden(GroundType.flat);
      dropSeed(editor, profile, const Vec(6, 6));
      final wider = (editor.document.layers[grow]!.properties as ZoneProperties)
          .seed!
          .copyWith(size: 0.5);
      editor.setSeed(grow, wider);
      dropSeed(editor, profile, const Vec(6, 6));
      expect(
        (editor.document.layers[grow]!.properties as ZoneProperties).seed,
        wider,
      );
    });
  });
}
