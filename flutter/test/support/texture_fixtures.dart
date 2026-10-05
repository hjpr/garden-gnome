import 'dart:convert';
import 'dart:typed_data';

import 'package:garden_gnome/application/texture_library.dart';

/// Installed textures kept in memory, for tests.
class MemoryTextureStore implements TextureStore {
  final Map<String, StoredTexture> textures = {};
  final Map<String, TexturePack> packs = {};
  Map<TextureGround, List<String>> selection = {};

  @override
  Future<StoredTextures> load() async => StoredTextures(
    textures: [...textures.values],
    packs: [...packs.values],
    selection: selection,
  );

  @override
  Future<Uint8List?> bytes(String id) async => textures[id]?.png;

  @override
  Future<void> putTextures(List<StoredTexture> list) async {
    for (final t in list) {
      textures[t.id] = t;
    }
  }

  @override
  Future<void> deleteTextures(List<String> ids) async =>
      ids.forEach(textures.remove);

  @override
  Future<void> putPack(TexturePack pack) async => packs[pack.id] = pack;

  @override
  Future<void> deletePack(String packId) async => packs.remove(packId);

  @override
  Future<void> saveSelection(Map<TextureGround, List<String>> s) async =>
      selection = {
        for (final e in s.entries) e.key: [...e.value],
      };
}

/// Passes pictures through, refusing any whose first byte is 0 (a stand-in
/// for "not square").
class FakePreparer implements TexturePreparer {
  final List<double> feet = [];

  @override
  Future<Uint8List> prepare(Uint8List bytes, {double feetPerRepeat = 5}) async {
    feet.add(feetPerRepeat);
    if (bytes.isNotEmpty && bytes.first == 0) {
      throw const TextureImportError('textures must be square (1:1)');
    }
    return bytes;
  }
}

/// A library whose built-ins are [files] per ground folder (default = the
/// first [defaults] of each), each picture being [picture].
TextureLibrary memoryLibrary({
  required Uint8List picture,
  Map<String, List<String>>? files,
  int defaults = 3,
  MemoryTextureStore? store,
  TexturePreparer? preparer,
}) {
  final folders =
      files ??
      {
        for (final g in TextureGround.values)
          g.folder: ['a-1.png', 'a-2.png', 'a-3.png', 'b-1.png'],
      };
  final index = {
    for (final e in folders.entries)
      e.key: {'files': e.value, 'default': e.value.take(defaults).toList()},
  };
  return TextureLibrary(
    store: store ?? MemoryTextureStore(),
    preparer: preparer ?? FakePreparer(),
    readAsset: (asset) async => asset.endsWith('index.json')
        ? Uint8List.fromList(utf8.encode(jsonEncode(index)))
        : picture,
  );
}
