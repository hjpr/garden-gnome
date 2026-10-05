import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:garden_gnome/presentation/canvas/drawing_canvas.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/garden_controller.dart';
import 'package:garden_gnome/application/toasts.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/grow/garden_record.dart';
import 'package:garden_gnome/domain/grow/variety.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/presentation/canvas/render_cover.dart';
import 'package:garden_gnome/presentation/canvas/render_assets.dart';
import '../support/render_fixtures.dart';
import 'package:garden_gnome/presentation/canvas/scene_painter.dart';
import 'package:garden_gnome/presentation/canvas/scene_state.dart';

import '../support/ground_fixtures.dart';
import '../support/memory_garden_record_store.dart';
import '../support/texture_fixtures.dart';

Future<Uint8List> raster(
  GardenDocument document,
  Map<String, String> covers, {
  ViewMode mode = ViewMode.render,
  RenderAssets? assets,
  Map<String, String> plants = const {},
  bool close = false,
}) async {
  final recorder = ui.PictureRecorder();
  ScenePainter(
    SceneState(
      document: document,
      // Close enough that plants are drawn one by one.
      camera: close
          ? Camera(height: Camera.heightFor(metres: 1, pixels: 30))
          : const Camera(),
      plantCropIds: plants,
      appearance: const Appearance(),
      selectedLayerId: null,
      selection: const {},
      preview: null,
      lineAnchor: null,
      viewMode: mode,
      coverCropIds: covers,
      renderAssets: assets,
    ),
  ).paint(ui.Canvas(recorder), const ui.Size(360, 360));
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 360);
  final bytes = Uint8List.fromList(
    (await image.toByteData())!.buffer.asUint8List(),
  );
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'DrawingCanvas snapshots the vault and repaints after variety removal',
    (tester) async {
      final (editor, _, soil, _) = garden(GroundType.cover);
      editor.setCover(
        soil,
        const CoverSowing(varietyId: 'v1', name: 'Any name'),
      );
      final controller = GardenController(
        store: MemoryGardenRecordStore(
          GardenRecord(
            varieties: {
              'v1': const Variety(
                id: 'v1',
                cropId: 'crimson-clover',
                name: 'Any name',
              ),
            },
          ),
        ),
        toasts: ToastCenter(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingCanvas(editor: editor, garden: controller),
        ),
      );
      SceneState snapshot() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ScenePainter>()
          .single
          .scene;
      expect(snapshot().coverCropIds, {soil: 'crimson-clover'});
      controller.removeVariety('v1');
      await tester.pump();
      expect(snapshot().coverCropIds, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.toasts.dispose();
    },
  );

  test(
    'resolves cover variety IDs through vault, never names or IDs that look like crops',
    () {
      final (editor, _, soil, _) = garden(GroundType.cover);
      final controller = GardenController(
        store: MemoryGardenRecordStore(),
        toasts: ToastCenter(),
        clock: () => DateTime.utc(2026, 10, 4),
        record: GardenRecord(
          varieties: {
            'v1': const Variety(
              id: 'v1',
              cropId: 'crimson-clover',
              name: 'Any name',
            ),
            'v2': const Variety(
              id: 'v2',
              cropId: 'winter-rye',
              name: 'Crimson Clover',
            ),
          },
        ),
      );
      addTearDown(controller.dispose);
      expect(renderCoverCropIds(editor.document, controller), isEmpty);
      for (final (id, expected) in [
        ('v1', 'crimson-clover'),
        ('v2', 'winter-rye'),
        ('crimson-clover', null),
        ('missing', null),
      ]) {
        editor.setCover(
          soil,
          CoverSowing(varietyId: id, name: 'Crimson Clover'),
        );
        expect(renderCoverCropIds(editor.document, controller)[soil], expected);
      }
      editor.setCover(
        soil,
        CoverSowing(
          varietyId: 'v1',
          name: 'Clover',
          terminatedOn: DateTime.utc(2026, 10, 4),
        ),
      );
      expect(renderCoverCropIds(editor.document, controller), isEmpty);
      editor.setCover(
        soil,
        CoverSowing(
          varietyId: 'v1',
          name: 'Clover',
          terminatedOn: DateTime.utc(2026, 10, 5),
        ),
      );
      expect(
        renderCoverCropIds(editor.document, controller)[soil],
        'crimson-clover',
      );
      expect(renderCoverCropIds(editor.document, null), isEmpty);
      editor.setGround(soil, GroundType.flat);
      expect(renderCoverCropIds(editor.document, controller), isEmpty);
    },
  );

  test(
    'only resolved crimson-clover paints its loaded art in Render',
    () async {
      // Only the clover ground has a texture.
      final picture = await png(8, 8);
      final assets = RenderAssets(
        bundle: MemoryRenderBundle({}),
        textures: memoryLibrary(
          picture: picture.buffer.asUint8List(
            picture.offsetInBytes,
            picture.lengthInBytes,
          ),
          files: {
            'crimson_clover': ['clover-1.png'],
          },
        ),
      );
      addTearDown(assets.dispose);
      await assets.loadGround();
      expect(assets.texture(RenderTexture.crimsonClover), isNotNull);
      final (editor, _, soil, _) = garden(GroundType.cover);
      final generic = await raster(editor.document, {}, assets: assets);
      final clover = await raster(editor.document, {
        soil: 'crimson-clover',
      }, assets: assets);
      final at = (150 * 360 + 150) * 4;
      expect(clover.sublist(at, at + 3), isNot(generic.sublist(at, at + 3)));
      expect(
        await raster(editor.document, {soil: 'winter-rye'}, assets: assets),
        orderedEquals(generic),
      );
      final wire = await raster(
        editor.document,
        {},
        assets: assets,
        mode: ViewMode.wireframe,
      );
      expect(
        await raster(
          editor.document,
          {soil: 'crimson-clover'},
          assets: assets,
          mode: ViewMode.wireframe,
        ),
        orderedEquals(wire),
      );
      editor.setGround(soil, GroundType.flat);
      expect(
        await raster(editor.document, {soil: 'crimson-clover'}, assets: assets),
        orderedEquals(await raster(editor.document, {}, assets: assets)),
      );
    },
  );

  test('a planting resolves its crop through the vault variety', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    final controller = GardenController(
      store: MemoryGardenRecordStore(),
      toasts: ToastCenter(),
      record: GardenRecord(
        varieties: {
          'variety-1': const Variety(
            id: 'variety-1',
            cropId: 'lettuce',
            name: 'Tomatoes',
          ),
        },
      ),
    );
    addTearDown(controller.dispose);
    expect(renderPlantCropIds(editor.document, controller), {grow: 'lettuce'});
    expect(renderPlantCropIds(editor.document, null), isEmpty);
    editor.setSeed(grow, null);
    expect(renderPlantCropIds(editor.document, controller), isEmpty);
  });

  test(
    'Render draws a crop with art as its picture, others as circles',
    () async {
      final (editor, _, _, grow) = garden(GroundType.flat);
      editor.setSeed(grow, seed(inRow: 1.0, betweenRows: 1.0));
      // A solid red picture, so it is easy to find in the result.
      final red = await solidPng(64, 64, const ui.Color(0xffff0000));
      final assets = RenderAssets(
        bundle: MemoryRenderBundle({'assets/render/plants/lettuce_1.png': red}),
      );
      addTearDown(assets.dispose);
      bool hasRed(Uint8List px) {
        for (var i = 0; i < px.length; i += 4) {
          if (px[i] > 200 && px[i + 1] < 60 && px[i + 2] < 60) return true;
        }
        return false;
      }

      final none = await raster(
        editor.document,
        {},
        assets: assets,
        close: true,
      );
      // The first ask starts the load; nothing is drawn from it yet.
      final asked = await raster(
        editor.document,
        {},
        assets: assets,
        close: true,
        plants: {grow: 'lettuce'},
      );
      expect(asked, orderedEquals(none));
      await pumpEventQueue();
      expect(assets.plant('lettuce'), isNotNull);
      final drawn = await raster(
        editor.document,
        {},
        assets: assets,
        close: true,
        plants: {grow: 'lettuce'},
      );
      expect(hasRed(drawn), isTrue);
      expect(hasRed(none), isFalse);
      // A crop without art keeps the circles.
      expect(
        await raster(
          editor.document,
          {},
          assets: assets,
          close: true,
          plants: {grow: 'no-such-crop'},
        ),
        orderedEquals(none),
      );
      // Wire never draws pictures.
      expect(
        hasRed(
          await raster(
            editor.document,
            {},
            assets: assets,
            close: true,
            mode: ViewMode.wireframe,
            plants: {grow: 'lettuce'},
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'unavailable artwork and nonclover retain generic green, Wire is unchanged',
    () async {
      final (editor, _, soil, _) = garden(GroundType.cover);
      final baseline = await raster(editor.document, {});
      expect(
        await raster(editor.document, {soil: 'winter-rye'}),
        orderedEquals(baseline),
      );
      expect(
        await raster(editor.document, {soil: 'crimson-clover'}),
        orderedEquals(baseline),
      );
      final wire = await raster(editor.document, {}, mode: ViewMode.wireframe);
      expect(
        await raster(editor.document, {
          soil: 'crimson-clover',
        }, mode: ViewMode.wireframe),
        orderedEquals(wire),
      );
    },
  );
}
