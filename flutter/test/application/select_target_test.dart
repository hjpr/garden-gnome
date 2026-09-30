import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/alignment.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/reference_image.dart';
import 'package:garden_gnome/domain/vec.dart';

/// Select must find the same thing under the pointer whether it hovers,
/// clicks or starts a drag there, and a feature, an image and land must
/// not each keep their own idea of what is selected.
void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  final image = ReferenceImage(
    id: 'image-1',
    bytes: png,
    mimeType: 'image/png',
    pixelWidth: 100,
    pixelHeight: 100,
    topLeft: Vec.zero,
    metresPerPixel: 1,
  );
  final bed = Feature.placed(
    'feature-1',
    FeatureKind.raisedBed,
    const Vec(5, 5),
  );

  (EditorController, CanvasInput) editorWith({GardenDocument? document}) {
    final editor = EditorController(document: document);
    addTearDown(editor.dispose);
    return (editor, CanvasInput(editor));
  }

  void click(CanvasInput input, Offset at) {
    input.hover(at);
    input.press(at, shift: false);
    input.release(at);
  }

  void drag(CanvasInput input, Offset from, Offset to) {
    input.press(from, shift: false);
    input.move(from + const Offset(6, 0));
    input.move(to);
    input.release(to);
  }

  test('a feature over an image is what a hover, click and drag pick', () {
    final (editor, input) = editorWith(
      document: GardenDocument(id: 'd', references: [image], features: [bed]),
    );
    final at = editor.camera.toScreen(bed.centre);
    input.hover(at);
    expect(editor.preview, isA<FeatureHoverPreview>());
    click(input, at);
    expect(editor.selectedFeature?.id, bed.id);
    drag(input, at, at + const Offset(30, 0));
    expect(editor.document.references.single.topLeft, image.topLeft);
    expect(editor.document.features.single.centre, const Vec(6, 5));
    expect(editor.selectedFeature?.id, bed.id);
  });

  test('switching to the Feature tool keeps the selected feature', () {
    final (editor, _) = editorWith();
    editor.addFeature(FeatureKind.raisedBed, const Vec(5, 5));
    final id = editor.selectedFeature!.id;
    editor.selectTool(Tool.feature);
    expect(editor.selectedFeature?.id, id);
    editor.selectTool(Tool.line);
    expect(editor.selectedFeature, isNull);
  });

  test('selecting an image drops the feature, and the other way round', () {
    final (editor, _) = editorWith(
      document: GardenDocument(id: 'd', references: [image], features: [bed]),
    );
    editor.selectFeature(bed.id);
    editor.selectReference(image.id);
    expect(editor.selectedFeature, isNull);
    expect(editor.selectedImage?.id, image.id);
    editor.selectFeature(bed.id);
    expect(editor.selectedImage, isNull);
    expect(editor.selectedFeature?.id, bed.id);
    editor.escape();
    expect(editor.selectedFeature, isNull);
  });

  test(
    'Delete is offered for a selected feature or image, not for nothing',
    () {
      final (editor, _) = editorWith(
        document: GardenDocument(id: 'd', references: [image], features: [bed]),
      );
      expect(editor.canDeleteSelection, isFalse);
      editor.selectFeature(bed.id);
      expect(editor.canDeleteSelection, isTrue);
      editor.deleteSelection();
      expect(editor.document.features, isEmpty);
      editor.selectReference(image.id);
      expect(editor.canDeleteSelection, isTrue);
      editor.deleteSelection();
      expect(editor.document.references, isEmpty);
      expect(editor.canDeleteSelection, isFalse);
    },
  );

  test('leaving an Align button clears only its own preview', () {
    final (editor, _) = editorWith();
    editor.previewAlign(AlignEdge.left);
    editor.cancelOperation();
    const other = PointPreview(Vec(1, 2), valid: true);
    editor.setPreview(other);
    editor.previewAlign(null);
    expect(editor.preview, same(other));
    editor.previewBoolean(null);
    expect(editor.preview, same(other));
  });

  test('cross-layer hits keep each layer\'s own order among ties', () {
    var n = 0;
    final (base, layerId) = GardenDocument(
      id: 'd',
    ).addLayer(LayerKind.property, newId: () => 'id-${++n}');
    final geometry = Geometry(
      id: base.geometryOf(layerId).id,
      ownerLayerId: layerId,
      points: {for (var i = 1; i <= 40; i++) 'point-$i': Vec.zero},
    );
    final document = base.withGeometry(geometry);
    const camera = Camera();
    final withinLayer = [
      for (final hit in hitsAt(geometry, camera, Offset.zero)) hit.id,
    ];
    final acrossLayers = [
      for (final hit in hitsAcrossLayers(document, camera, Offset.zero))
        hit.itemId,
    ];
    expect(acrossLayers, withinLayer);
    expect(withinLayer.first, 'point-1');
  });
}
