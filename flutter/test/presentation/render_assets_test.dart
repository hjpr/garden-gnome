import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/texture_library.dart';
import 'package:garden_gnome/presentation/canvas/render_assets.dart';

import '../support/render_fixtures.dart';
import '../support/texture_fixtures.dart';

Future<Uint8List> picture(ui.Color colour, [int side = 64]) async {
  final data = await solidPng(side, side, colour);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each ground blends its chosen textures, with small copies', () async {
    final library = memoryLibrary(
      picture: await picture(const ui.Color(0xff804020)),
    );
    final assets = RenderAssets(
      bundle: MemoryRenderBundle({}),
      textures: library,
    );
    addTearDown(assets.dispose);
    await assets.loadGround();
    for (final t in RenderTexture.values) {
      expect(assets.atlasGrid(t), const ui.Size(3, 1));
      expect(assets.texture(t)!.width, 3072);
      expect(assets.texture(t)!.height, 1024);
      expect(assets.smallCopies(t)!.$1.width, 768);
      expect(assets.smallCopies(t)!.$2.width, 192);
      expect(assets.groundShader(t), isNotNull);
      expect(assets.meanColour(t)[0], closeTo(128 / 255, 0.01));
    }
  });

  test('changing a ground\'s textures rebuilds only that ground', () async {
    final library = memoryLibrary(
      picture: await picture(const ui.Color(0xff804020)),
    );
    final assets = RenderAssets(
      bundle: MemoryRenderBundle({}),
      textures: library,
    );
    addTearDown(assets.dispose);
    await assets.loadGround();
    final lawn = assets.texture(RenderTexture.lawn);
    final grass = assets.texture(RenderTexture.wildGrass);
    expect(await library.toggle('builtin:wild_grass/a-2.png'), isNull);
    await assets.rebuilt;
    expect(assets.atlasGrid(RenderTexture.wildGrass), const ui.Size(2, 1));
    expect(assets.texture(RenderTexture.wildGrass), isNot(same(grass)));
    expect(assets.texture(RenderTexture.lawn), same(lawn));
  });

  test('without a library the ground stays plain colour', () async {
    final assets = RenderAssets(bundle: MemoryRenderBundle({}));
    addTearDown(assets.dispose);
    await assets.loadGround();
    expect(assets.texture(RenderTexture.wildGrass), isNull);
  });

  test('a picture that will not decode leaves that ground plain', () async {
    final library = memoryLibrary(picture: Uint8List.fromList([1, 2, 3]));
    final assets = RenderAssets(
      bundle: MemoryRenderBundle({}),
      textures: library,
    );
    addTearDown(assets.dispose);
    await assets.loadGround();
    expect(assets.texture(RenderTexture.lawn), isNull);
    expect(TextureGround.values.length, RenderTexture.values.length);
  });
}
