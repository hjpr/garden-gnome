import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/curve_edge.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/canvas/curve_paths.dart';
import 'package:garden_gnome/presentation/canvas/scene_painter.dart';

Future<Uint8List> raster(
  GardenDocument document, {
  String? layer,
  Set<String> selection = const {},
  Preview? preview,
}) async {
  final recorder = PictureRecorder();
  ScenePainter(
    SceneState(
      document: document,
      camera: const Camera(),
      appearance: const Appearance(),
      selectedLayerId: layer,
      selection: selection,
      preview: preview,
      lineAnchor: null,
    ),
  ).paint(Canvas(recorder), const Size(360, 360));
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 360);
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

List<int> pixel(Uint8List raster, int x, int y) =>
    raster.sublist((y * 360 + x) * 4, (y * 360 + x) * 4 + 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invalid dashed curves do not fall back to endpoint chords', () async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final layer = editor.selectedLayerId!;
    final (next, _) = editor.tryGeometryEdit(layer, (e) {
      e.connect(
        e.addPoint(const Vec(2, 8)),
        e.addPoint(const Vec(10, 8)),
        bulge: 1,
      );
      e.connect(e.addPoint(const Vec(6, 2)), e.addPoint(const Vec(6, 6)));
    });
    final blank = await raster(GardenDocument(id: 'blank'));
    final painted = await raster(next!, layer: layer);
    for (var x = 100; x < 260; x++) {
      expect(pixel(painted, x, 240), pixel(blank, x, 240));
    }
    expect(pixel(painted, 180, 120), isNot(pixel(blank, 180, 120)));
  });

  test('inactive land hatching is clipped away from holes', () async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final property = editor.selectedLayerId!;
    final (closed, _) = editor.tryGeometryEdit(property, (e) {
      final ids = [
        for (final point in [
          const Vec(0, 0),
          const Vec(12, 0),
          const Vec(12, 12),
          const Vec(0, 12),
        ])
          e.addPoint(point),
      ];
      for (var i = 0; i < ids.length; i++) {
        e.connect(ids[i], ids[(i + 1) % ids.length]);
      }
    });
    editor.commit('Property', closed!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    final (withHole, _) = editor.tryGeometryEdit(zone, (e) {
      e.addCircle(e.addPoint(const Vec(6, 6)), 5);
      final cutter = e.addCircle(e.addPoint(const Vec(6, 6)), 2);
      e.boolean(cutter, BooleanOperation.subtract);
    });
    editor.commit('Zone', withHole!);
    final (opened, _) = editor.tryGeometryEdit(
      property,
      (e) => e.delete(['line-1']),
    );
    final blank = await raster(GardenDocument(id: 'blank'));
    final painted = await raster(opened!);
    expect(pixel(painted, 177, 177), pixel(blank, 177, 177));
    expect(pixel(painted, 177, 70), isNot(pixel(blank, 177, 70)));
  });

  test('regionPath follows real circular bounds and even-odd holes', () {
    final region = const DiscRegion(
      Vec(6, 6),
      5,
    ).combine(const DiscRegion(Vec(6, 6), 2), BooleanOperation.subtract);
    final path = regionPath(region, const Camera());
    expect(path.fillType, PathFillType.evenOdd);
    expect(path.contains(const Offset(180, 180)), isFalse);
    expect(path.contains(const Offset(180, 60)), isTrue);
    expect(path.contains(const Offset(35, 35)), isFalse);
    expect(path.getBounds(), const Rect.fromLTRB(30, 30, 330, 330));
    expect(path.computeMetrics().length, 2);
  });

  test(
    'curvePath includes the arc crown and has circular length, not chord length',
    () {
      final arc = CurveEdge.through(
        const Vec(2, 8),
        const Vec(6, 4),
        const Vec(10, 8),
      )!;
      final path = curvePath(arc, const Camera());
      expect(path.getBounds().top, closeTo(120, 1e-4));
      expect(path.getBounds().bottom, closeTo(240, 1e-4));
      expect(path.computeMetrics().single.length, closeTo(math.pi * 4 * 30, 1));
    },
  );

  test('arc normal, selected and hover strokes do not draw a chord', () async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final layer = editor.selectedLayerId!;
    final (next, _) = editor.tryGeometryEdit(layer, (e) {
      e.connect(
        e.addPoint(const Vec(2, 8)),
        e.addPoint(const Vec(10, 8)),
        bulge: 1,
      );
    });
    editor.commit('Arc', next!);
    final line = next.geometryOf(layer).lines.values.single.id;
    final blank = await raster(GardenDocument(id: 'blank'));
    for (final mode in ['normal', 'selected', 'hover']) {
      final painted = await raster(
        next,
        layer: layer,
        selection: mode == 'selected' ? {line} : {},
        preview: mode == 'hover' ? HoverPreview(line, layerId: layer) : null,
      );
      expect(
        pixel(painted, 180, 120),
        isNot(pixel(blank, 180, 120)),
        reason: '$mode paints the arc crown',
      );
      expect(
        pixel(painted, 180, 240),
        pixel(blank, 180, 240),
        reason: '$mode must not paint the chord',
      );
    }
  });

  test('move and Arc previews keep true curvature', () async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final layer = editor.selectedLayerId!;
    final before = editor.document;
    final (next, _) = editor.tryGeometryEdit(layer, (e) {
      e.connect(
        e.addPoint(const Vec(2, 8)),
        e.addPoint(const Vec(10, 8)),
        bulge: 1,
      );
    });
    final geometry = next!.geometryOf(layer);
    final curve = geometry.lines.values.single.curve(geometry.points);
    final blank = await raster(GardenDocument(id: 'blank'));
    final arc = await raster(
      before,
      layer: layer,
      preview: ArcPreview(
        start: curve.start,
        through: curve.pointAt(0.5),
        end: curve.end,
        curve: curve,
        valid: true,
      ),
    );
    expect(pixel(arc, 180, 120), isNot(pixel(blank, 180, 120)));
    expect(pixel(arc, 180, 240), pixel(blank, 180, 240));
    final moved = await raster(
      before,
      layer: layer,
      preview: MovePreview(
        document: next,
        moved: {layer: geometry.points.keys.toSet()},
        valid: true,
      ),
    );
    expect(pixel(moved, 180, 120), isNot(pixel(blank, 180, 120)));
    expect(pixel(moved, 180, 240), pixel(blank, 180, 240));
  });

  test(
    'fill, selection, hover and Boolean previews leave hole pixels untouched',
    () async {
      final editor = EditorController()..addLayer(LayerKind.property);
      addTearDown(editor.dispose);
      final layer = editor.selectedLayerId!;
      String? operand;
      final (staged, _) = editor.tryGeometryEdit(layer, (e) {
        e.addCircle(e.addPoint(const Vec(6, 6)), 5);
        operand = e.addCircle(e.addPoint(const Vec(6, 6)), 2);
      });
      editor.commit('Circles', staged!);
      String? boundary;
      final (next, _) = editor.tryGeometryEdit(layer, (e) {
        boundary = e.boolean(operand!, BooleanOperation.subtract).single;
      });
      final blank = await raster(GardenDocument(id: 'blank'));
      final frames = [
        await raster(next!, layer: layer),
        await raster(next, layer: layer, selection: {boundary!}),
        await raster(
          next,
          layer: layer,
          preview: HoverPreview(boundary!, layerId: layer),
        ),
        await raster(
          staged,
          layer: layer,
          preview: BooleanPreview(
            layerId: layer,
            operandId: operand!,
            resultIds: [boundary!],
            document: next,
            valid: true,
          ),
        ),
      ];
      for (final image in frames) {
        expect(
          pixel(image, 177, 177),
          pixel(blank, 177, 177),
          reason: 'hole never receives a land fill or label',
        );
        expect(
          pixel(image, 177, 70),
          isNot(pixel(blank, 177, 70)),
          reason: 'land receives its fill',
        );
      }
    },
  );
}
