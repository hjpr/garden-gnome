import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/tool_prompts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/zone_ground.dart';

import '../support/editor_input.dart';
import '../support/ground_fixtures.dart';

void main() {
  group('Ground tool', () {
    test('clicking inside a zone sets its ground as one Undo step', () {
      final (editor, input, _, zone) = farm();
      editor.selectTool(Tool.ground);
      expect(editor.function, ToolFunction.clearGround, reason: 'Fallow first');
      click(input, 5, 5);
      expect(editor.document.storedGroundOf(zone), isNull);
      editor.selectFunction(ToolFunction.flatGround);
      click(input, 5, 5);
      expect(editor.document.storedGroundOf(zone), GroundType.flat);
      expect(editor.undoLabel, 'Flat ground');

      editor.selectFunction(ToolFunction.rowGround);
      click(input, 5, 5);
      expect(editor.document.storedGroundOf(zone), GroundType.row);
      editor.undo();
      expect(editor.document.storedGroundOf(zone), GroundType.flat);
      expect(editor.tool, Tool.ground, reason: 'the tool stays chosen');
    });

    test('outside the zone, or on a property, nothing changes', () {
      final (editor, input, property, zone) = farm();
      editor.selectTool(Tool.ground);
      click(input, 15, 15);
      expect(editor.document.storedGroundOf(zone), isNull);
      expect(editor.notice, contains('Click inside'));

      editor.selectLayer(property);
      expect(toolPrompt(editor), 'Ground is set on beds. Select a bed');
      click(input, 15, 15);
      expect(editor.notice, CanvasInput.groundNeedsBed);
    });

    test('Properties and the tool share one value; rows keep their sizes', () {
      final (editor, _, _, zone) = farm();
      editor.setGround(zone, GroundType.row);
      editor.setRows(
        zone,
        const RowSpec(width: 1, spacing: 0.5, direction: 90),
      );
      editor.setGround(zone, GroundType.flat);
      editor.setGround(zone, GroundType.row);
      expect(
        editor.document.rowsOf(zone),
        const RowSpec(width: 1, spacing: 0.5, direction: 90),
      );
      expect(RowSpec.normalDirection(-30), 150);
      expect(RowSpec.normalDirection(270), 90);
    });

    test('row sizes that cannot work are refused with a reason', () {
      final (editor, _, _, zone) = farm();
      final before = editor.document;
      editor.setRows(zone, const RowSpec(width: 0));
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, 'Row width must be above 0');
    });
  });

  test('each piece of a zone starts with a whole row at its edge', () {
    final (editor, input, _, zone) = farm();
    editor.selectTool(Tool.polygon);
    editor.selectFunction(ToolFunction.rectangle);
    // A second piece, 3.3 m to the right: not on the first piece's pitch.
    click(input, 15.3, 10);
    click(input, 18.3, 16);
    editor.setGround(zone, GroundType.row);
    editor.setRows(zone, const RowSpec(width: 1, spacing: 1));
    final layout = editor.document.rowLayoutOf(zone)!;
    // 10 m wide piece: 5 rows; 3 m wide piece: 2 rows.
    expect(layout.rowCount, 7);
    expect(layout.runs.map((r) => r.start.x).toSet(), containsAll([2.5, 15.8]));
  });

  group('Feature tool', () {
    test('a click places a feature at its usual size and selects it', () {
      final (editor, input) = newEditor();
      editor.selectTool(Tool.feature);
      editor.selectFunction(ToolFunction.greenhouse);
      click(input, 10, 10);
      final feature = editor.document.features.single;
      expect(feature.kind, FeatureKind.greenhouse);
      expect(feature.centre, const Vec(10, 10));
      expect(feature.length, FeatureKind.greenhouse.defaultLength);
      expect(feature.displayName, 'Greenhouse 1');
      expect(editor.selectedFeature, feature);
      expect(editor.showsFeature, isTrue);
      editor.undo();
      expect(editor.document.features, isEmpty);
      expect(editor.selectedFeature, isNull);
    });

    test('Select picks a feature over land and drags it', () {
      final (editor, input, property, _) = farm();
      editor.addFeature(FeatureKind.raisedBed, const Vec(15, 15));
      editor.selectLayer(property);
      editor.selectTool(Tool.select);
      click(input, 15, 15);
      expect(editor.selectedFeature?.kind, FeatureKind.raisedBed);

      input.press(at(15, 15), shift: false);
      input.move(at(16, 15));
      input.move(at(17, 16));
      input.release(at(17, 16));
      expect(editor.selectedFeature!.centre, const Vec(17, 16));
      expect(editor.undoLabel, 'Move Raised bed 1');
    });

    test('sizes, rotation and name change as Undo steps; Delete removes', () {
      final (editor, _) = newEditor();
      editor.addFeature(FeatureKind.highTunnel, Vec.zero);
      final feature = editor.selectedFeature!;
      editor.updateFeature(
        'Change length',
        feature.copyWith(length: 20, rotation: -90, label: () => 'Tomatoes'),
      );
      final changed = editor.selectedFeature!;
      expect(changed.length, 20);
      expect(changed.rotation, 270);
      expect(changed.displayName, 'Tomatoes');
      editor.updateFeature('Change width', changed.copyWith(width: 0));
      expect(editor.notice, 'Width must be above 0');
      expect(editor.selectedFeature!.width, feature.width);
      editor.deleteSelection();
      expect(editor.document.features, isEmpty);
      editor.undo();
      expect(editor.document.features.single.displayName, 'Tomatoes');
    });

    test('a rotated feature contains points along its turned length', () {
      final f = Feature.placed(
        'feature-1',
        FeatureKind.raisedBed,
        Vec.zero,
      ).copyWith(rotation: 90);
      expect(f.contains(Vec(0, f.length / 2 - 0.01)), isTrue);
      expect(f.contains(Vec(f.length / 2 - 0.01, 0)), isFalse);
    });

    test('a tunnel is drawn in whole 5 ft sections, ends included', () {
      const foot = 0.3048;
      expect(tunnelSections(79 * foot), 16, reason: '79 ft shows as 80 ft');
      expect(tunnelSections(77 * foot), 15, reason: '77 ft shows as 75 ft');
      expect(tunnelSections(30 * foot), 6);
      expect(tunnelSections(3 * foot), 2, reason: 'never fewer than 2 ends');
    });

    test('feature IDs are never reused after Undo', () {
      final (editor, _) = newEditor();
      editor.addFeature(FeatureKind.raisedBed, Vec.zero);
      editor.undo();
      editor.addFeature(FeatureKind.raisedBed, Vec.zero);
      expect(editor.document.features.single.id, 'feature-2');
    });
  });

  group('View mode', () {
    test('Render is a workspace choice, not an Undo step', () {
      final (editor, _) = newEditor();
      expect(editor.settings.viewMode, ViewMode.wireframe);
      editor.setViewMode(ViewMode.render);
      expect(editor.settings.viewMode, ViewMode.render);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
    });
  });
}
