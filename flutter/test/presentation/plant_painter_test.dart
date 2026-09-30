import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/plant_layout.dart';
import 'package:garden_gnome/presentation/canvas/scene_painter.dart';
import 'package:garden_gnome/presentation/canvas/scene_state.dart';

import '../support/editor_input.dart';
import '../support/ground_fixtures.dart';

Future<Uint8List> raster(GardenDocument document) async {
  final recorder = PictureRecorder();
  ScenePainter(SceneState(
    document: document,
    camera: const Camera(),
    appearance: const Appearance(),
    selectedLayerId: null,
    selection: const {},
    preview: null,
    lineAnchor: null,
  )).paint(Canvas(recorder), const Size(360, 360));
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 360);
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

List<int> pixel(Uint8List image, int x, int y) =>
    image.sublist((y * 360 + x) * 4, (y * 360 + x) * 4 + 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plant diameter is Size and stays visible with zero empty gap', () async {
    final (editor, input, _, _) = garden(GroundType.flat);
    editor.selectLayer(editor.document.propertyIds.single);
    final grow = rectangleLayer(editor, input, LayerKind.zone, 4, 4, 6, 6);
    editor.setGround(grow, GroundType.grow);
    final blank = await raster(editor.document);
    editor.setSeed(grow, seed(size: 2, spacing: 0));
    expect(editor.document.plantLayoutOf(grow)!.count, 1);
    final touching = await raster(editor.document);
    // Diameter 2 m at 30 px/m: radius 30 px, centred at (150, 150).
    expect(pixel(touching, 177, 150), isNot(pixel(blank, 177, 150)));
    expect(pixel(touching, 183, 150), pixel(blank, 183, 150));

    editor.setSeed(grow, seed(size: 2, spacing: 3));
    expect(editor.document.plantLayoutOf(grow)!.count, 1);
    final separated = await raster(editor.document);
    expect(separated, orderedEquals(touching));

    editor.setSeed(grow, seed(size: 1, spacing: 3));
    final smaller = await raster(editor.document);
    expect(pixel(smaller, 177, 150), pixel(blank, 177, 150));
    expect(pixel(smaller, 160, 150), isNot(pixel(blank, 160, 150)));
  });
}
