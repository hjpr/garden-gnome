import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/selection_target.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/reference_image.dart';
import 'package:garden_gnome/domain/vec.dart';

void main() {
  final image = ReferenceImage(
    id: 'image-1',
    bytes: Uint8List(1),
    mimeType: 'image/png',
    pixelWidth: 100,
    pixelHeight: 100,
    topLeft: Vec.zero,
    metresPerPixel: 1,
  );
  final feature = Feature.placed(
    'feature-1',
    FeatureKind.raisedBed,
    const Vec(5, 5),
  );
  var nextId = 0;
  final (base, layerId) = GardenDocument(
    id: 'd',
    features: [feature],
    references: [image],
  ).addLayer(LayerKind.property, newId: () => 'id-${++nextId}');
  final geometry = base.geometryOf(layerId).edit((e) {
    final points = [
      for (final point in const [
        Vec(0, 0),
        Vec(10, 0),
        Vec(10, 10),
        Vec(0, 10),
      ])
        e.addPoint(point),
    ];
    for (var i = 0; i < points.length; i++) {
      e.connect(points[i], points[(i + 1) % points.length]);
    }
  });
  final document = base.withGeometry(geometry);
  const camera = Camera();

  test(
    'resolver preserves handle, outline, feature, land and image priority',
    () {
      final targets = SelectionTargets(
        document: document,
        camera: camera,
        isFrozen: (_) => false,
        overlaysEnabled: true,
      );
      expect(
        targets.at(camera.toScreen(const Vec(5, 5))),
        isA<FeatureTarget>(),
      );
      expect(targets.at(camera.toScreen(const Vec(0, 0))), isA<LandTarget>());
      expect(targets.at(camera.toScreen(const Vec(3, 3))), isA<LandTarget>());
      expect(
        targets.at(camera.toScreen(const Vec(20, 20))),
        isA<ImageTarget>(),
      );
      final withHandle = SelectionTargets(
        document: document,
        camera: camera,
        isFrozen: (_) => false,
        overlaysEnabled: true,
        selectedImage: image,
      );
      expect(withHandle.at(Offset.zero), isA<ImageHandleTarget>());
    },
  );

  test('locked layers and Plant-mode overlays cannot become targets', () {
    final frozen = SelectionTargets(
      document: document,
      camera: camera,
      isFrozen: (_) => true,
      overlaysEnabled: true,
    );
    expect(frozen.at(camera.toScreen(const Vec(3, 3))), isA<ImageTarget>());
    final plant = SelectionTargets(
      document: document,
      camera: camera,
      isFrozen: (_) => true,
      overlaysEnabled: false,
      selectedImage: image,
    );
    expect(plant.at(Offset.zero), isNull);
    expect(plant.at(camera.toScreen(feature.centre)), isNull);
  });

  test('Shift-click still adds land underneath a feature', () {
    final editor = EditorController(document: document);
    addTearDown(editor.dispose);
    final input = CanvasInput(editor);
    final point = camera.toScreen(feature.centre);
    input.press(point, shift: true);
    input.release(point);
    expect(editor.selection, contains(geometry.stack.single));
    expect(editor.selectedFeature, isNull);
  });

  test('selecting the current land layer clears an overlay selection', () {
    final editor = EditorController(document: document);
    addTearDown(editor.dispose);
    editor.selectLayer(layerId);
    editor.selectFeature(feature.id);
    editor.selectLayer(layerId);
    expect(editor.selectedFeature, isNull);
    editor.selectReference(image.id);
    editor.selectLayer(layerId);
    expect(editor.selectedImage, isNull);
  });

  test('locked geometry disables Delete without changing keyboard refusal', () {
    final editor = EditorController(document: document);
    addTearDown(editor.dispose);
    editor.setLayerLocked(layerId, true);
    editor.selectObject(layerId, geometry.stack.single);
    expect(editor.canDeleteSelection, isFalse);
    final before = editor.document;
    editor.deleteSelection();
    expect(editor.document, same(before));
    expect(editor.notice, contains('locked'));
  });

  test('Plant mode guards direct feature and reference mutation commands', () {
    final editor = EditorController(document: document);
    addTearDown(editor.dispose);
    editor.setMode(EditMode.plant);
    final before = editor.document;
    editor.addFeature(FeatureKind.greenhouse, Vec.zero);
    editor.updateFeature('Move', feature.copyWith(centre: Vec.zero));
    editor.removeFeature(feature.id);
    editor.updateReference('Move', image.movedBy(const Vec(1, 1)));
    editor.removeReference(image.id);
    editor.removeReferenceLayer();
    editor.selectReference(image.id);
    expect(editor.canDeleteSelection, isFalse);
    editor.deleteSelection();
    expect(editor.document, same(before));
  });

  test(
    'cross-layer interior ties keep the top of each geometry stack first',
    () {
      var counter = 0;
      final overlapping = geometry.edit((e) {
        for (var i = 0; i < 40; i++) {
          final points = [
            for (final point in const [
              Vec(0, 0),
              Vec(10, 0),
              Vec(10, 10),
              Vec(0, 10),
            ])
              e.addPoint(point),
          ];
          for (var j = 0; j < points.length; j++) {
            e.connect(points[j], points[(j + 1) % points.length]);
          }
          counter++;
        }
      });
      final at = camera.toScreen(const Vec(5, 5));
      final hits = hitsAcrossLayers(base.withGeometry(overlapping), camera, at);
      final within = hitsAt(overlapping, camera, at);
      expect(hits.map((h) => h.itemId), within.map((h) => h.id));
      expect(hits.first.itemId, overlapping.stack.last);
      expect(hits, hasLength(counter + 1));
    },
  );
}
