import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/planting.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/domain/vec.dart';

import '../support/editor_input.dart';
import '../support/ground_fixtures.dart';

void main() {
  test('hiding is a view choice, not an Undo step', () {
    final (editor, _, soil, _) = garden(GroundType.flat);
    final before = editor.document;
    final undo = editor.undoLabel;
    editor.setLayerHidden(soil, true);
    expect(editor.isLayerHidden(soil), isTrue);
    expect(editor.settings.hiddenLayers, {soil});
    expect(identical(editor.document, before), isTrue);
    expect(editor.undoLabel, undo);
    editor.setLayerHidden(soil, false);
    expect(editor.isLayerHidden(soil), isFalse);
  });

  test('a hidden layer cannot be clicked, picked or drawn on', () {
    final (editor, input, soil, grow) = garden(GroundType.flat);
    editor.setLayerHidden(grow, true);
    // Inside the planting: the click falls through to the bed under it.
    click(input, 6, 6);
    expect(editor.selectedLayerId, soil);

    editor.selectLayer(grow);
    editor.selectTool(Tool.point);
    editor.selectFunction(ToolFunction.place);
    final document = editor.document;
    click(input, 5, 5);
    expect(identical(editor.document, document), isTrue);
    expect(editor.notice, contains('is hidden'));
  });

  test('hiding a property hides its beds and plantings with it', () {
    final (editor, input, soil, grow) = garden(GroundType.flat);
    final property = editor.document.propertyIds.single;
    editor.setLayerHidden(property, true);
    expect(editor.isLayerHidden(soil), isTrue);
    expect(editor.isLayerHidden(grow), isTrue);
    expect(editor.hiddenLayerIds, {property, soil, grow});
    editor.selectTool(Tool.select);
    click(input, 6, 6);
    expect(editor.selectedLayerId, isNull);
  });

  test('seeds cannot be dropped on a hidden planting', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setMode(EditMode.plant);
    expect(growZoneAt(editor, const Vec(6, 6)), grow);
    editor.setLayerHidden(grow, true);
    expect(growZoneAt(editor, const Vec(6, 6)), isNull);
  });

  test('a hidden Reference layer cannot be measured', () {
    final editor = EditorController();
    addTearDown(editor.dispose);
    editor.selectTool(Tool.reference);
    editor.setLayerHidden(EditorController.referenceLayerKey, true);
    expect(editor.referenceHidden, isTrue);
    expect(editor.referenceBlocker, contains('Reference is hidden'));
  });

  test('beds start Flat and plantings are named on their own', () {
    final (editor, input) = newEditor();
    rectangleLayer(editor, input, LayerKind.property, 0, 0, 20, 20);
    final property = editor.selectedLayerId!;
    editor.addLayer(LayerKind.zone, role: LayerRole.bed);
    final bed = editor.selectedLayerId!;
    expect(editor.document.layers[bed]!.role, LayerRole.bed);
    expect(editor.document.storedGroundOf(bed), GroundType.flat);
    expect(editor.undoLabel, 'Add Bed');
    editor.selectLayer(property);
    editor.addLayer(LayerKind.zone, role: LayerRole.planting);
    final planting = editor.selectedLayerId!;
    expect(editor.document.layers[planting]!.name, 'Planting 1');
    expect(editor.document.layers[planting]!.role, LayerRole.planting);
    expect(editor.isGrowZone(planting), isTrue);
  });
}
