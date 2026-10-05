import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/presentation/canvas/render_assets.dart';

const colours = [
  ui.Color(0xffff0000),
  ui.Color(0xff00ff00),
  ui.Color(0xff0000ff),
];

Future<ui.Image> tileImage({required bool atlas, bool pattern = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final n = pattern ? 8 : 1;
  for (var t = 0; t < (atlas ? 3 : 1); t++) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final colour = pattern
            ? ui.Color.fromARGB(
                255,
                30 + x * 25,
                20 + y * 28,
                (x + y) % 2 * 200,
              )
            : colours[t];
        canvas.drawRect(
          ui.Rect.fromLTWH((t * n + x).toDouble(), y.toDouble(), 1, 1),
          ui.Paint()..color = colour,
        );
      }
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(n * (atlas ? 3 : 1), n);
  picture.dispose();
  return image;
}

Future<Uint8List> raster(
  ui.FragmentProgram program,
  ui.Image image, {
  bool atlas = true,
  int size = 128,
  ui.Offset origin = ui.Offset.zero,
  double ppm = 20,
  double rotate = 1,
  double seed = 11,
}) async {
  final shader = program.fragmentShader();
  final values = <double>[
    origin.dx,
    origin.dy,
    ppm,
    1,
    image.width.toDouble(),
    image.height.toDouble(),
    seed,
    rotate,
    0,
    0,
    0,
    0,
    0,
    0.5,
    0.5,
    0.5,
    0,
    1,
    atlas ? 3 : 1,
    1,
    1, // uLevels: full size only
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
  shader.setImageSampler(0, image);
  shader.setImageSampler(1, image);
  shader.setImageSampler(2, image);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(size, size);
  final bytes = (await result.toByteData())!.buffer.asUint8List();
  final copy = Uint8List.fromList(bytes);
  result.dispose();
  picture.dispose();
  shader.dispose();
  return copy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'actual shader selects all three solid tiles without bilinear neighbour bleed',
    () async {
      final program = await ui.FragmentProgram.fromAsset('shaders/ground.frag');
      final image = await tileImage(atlas: true);
      addTearDown(image.dispose);
      for (final material in RenderTexture.values) {
        final reached = <int>{};
        // At lattice vertices exactly one cell contributes. One-texel tiles
        // force every bilinear tap to wrap to that tile, never a neighbour.
        for (var y = -5; y <= 5; y++) {
          for (var x = -5; x <= 5; x++) {
            final centre = ui.Offset(
              (x + 0.5 * y) / (1.5 * 3.4641016),
              0.8660254 * y / (1.5 * 3.4641016),
            );
            final origin = const ui.Offset(0.5, 0.5) - centre * 20;
            final bytes = await raster(
              program,
              image,
              size: 1,
              origin: origin,
              seed: material.seed,
            );
            final index = colours.indexWhere(
              (c) =>
                  (c.r * 255 - bytes[0]).abs() <= 1 &&
                  (c.g * 255 - bytes[1]).abs() <= 1 &&
                  (c.b * 255 - bytes[2]).abs() <= 1,
            );
            expect(
              index,
              isNonNegative,
              reason: 'cell ($x,$y): ${bytes.toList()}',
            );
            reached.add(index);
          }
        }
        expect(reached, unorderedEquals([0, 1, 2]), reason: material.name);
      }
    },
  );

  test(
    'actual shader is deterministic and world anchored through pan and zoom',
    () async {
      final program = await ui.FragmentProgram.fromAsset('shaders/ground.frag');
      for (final patterned in [false, true]) {
        final atlas = await tileImage(atlas: true, pattern: patterned);
        addTearDown(atlas.dispose);
        final base = await raster(program, atlas);
        expect(await raster(program, atlas), orderedEquals(base));
        final pan = await raster(
          program,
          atlas,
          origin: const ui.Offset(13, 9),
        );
        // Zoom 2x with half-pixel shift maps exact pixel centres, not corners.
        final zoom = await raster(
          program,
          atlas,
          ppm: 40,
          origin: const ui.Offset(-0.5, -0.5),
        );
        for (var y = 0; y < 60; y++) {
          for (var x = 0; x < 60; x++) {
            for (var c = 0; c < 4; c++) {
              final value = base[(y * 128 + x) * 4 + c];
              expect(
                (pan[((y + 9) * 128 + x + 13) * 4 + c] - value).abs(),
                lessThanOrEqualTo(1),
              );
              expect(
                (zoom[((y * 2) * 128 + x * 2) * 4 + c] - value).abs(),
                lessThanOrEqualTo(1),
              );
            }
          }
        }
      }
    },
  );

  test(
    'actual atlas shader preserves legacy scale, rotation, wrap and blending',
    () async {
      final program = await ui.FragmentProgram.fromAsset('shaders/ground.frag');
      final atlas = await tileImage(atlas: true, pattern: true);
      final legacy = await tileImage(atlas: false, pattern: true);
      addTearDown(atlas.dispose);
      addTearDown(legacy.dispose);
      for (final rotate in [0.0, 1.0]) {
        final a = await raster(
          program,
          atlas,
          origin: const ui.Offset(37, -19),
          rotate: rotate,
        );
        final b = await raster(
          program,
          legacy,
          atlas: false,
          origin: const ui.Offset(37, -19),
          rotate: rotate,
        );
        for (var i = 0; i < a.length; i++) {
          expect((a[i] - b[i]).abs(), lessThanOrEqualTo(1));
        }
      }
    },
  );
}
