import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import '../application/texture_library.dart';
import '../platform/texture_storage.dart';

/// Installed textures, packs and the chosen textures, app-wide (never in a
/// farm file): IndexedDB in the browser, a database in the app's data
/// folder on desktop.
///
/// Picture bytes live in their own store, so listing textures does not
/// read every picture.
class IdbTextureStore implements TextureStore {
  IdbTextureStore({IdbFactory? factory})
    : _factory = factory ?? textureStorageFactory();

  static const _databaseName = 'garden_gnome_textures';
  static const _meta = 'texture_meta';
  static const _bytes = 'texture_bytes';
  static const _settings = 'settings';

  final IdbFactory _factory;
  Database? _database;

  Future<Database> _open() async => _database ??= await _factory.open(
    _databaseName,
    version: 1,
    onUpgradeNeeded: (event) {
      final db = event.database;
      for (final store in [_meta, _bytes, _settings]) {
        if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
      }
    },
  );

  @override
  Future<StoredTextures> load() async {
    final db = await _open();
    final txn = db.transaction([_meta, _settings], idbModeReadOnly);
    final metas = await txn.objectStore(_meta).getAll();
    final packs = await txn.objectStore(_settings).getObject('packs');
    final selection = await txn.objectStore(_settings).getObject('selection');
    await txn.completed;
    return StoredTextures(
      textures: [
        for (final m in metas.cast<Map>())
          if (TextureGround.byFolder(m['ground'] as String) case final ground?)
            StoredTexture(
              id: m['id'] as String,
              ground: ground,
              name: m['name'] as String,
              packId: m['pack'] as String?,
              png: Uint8List(0),
            ),
      ],
      packs: [
        if (packs is List)
          for (final p in packs.cast<Map>())
            TexturePack(
              id: p['id'] as String,
              name: p['name'] as String,
              author: p['author'] as String?,
            ),
      ],
      selection: {
        if (selection is Map)
          for (final MapEntry(:key, :value) in selection.entries)
            ?TextureGround.byFolder(key as String): (value as List)
                .cast<String>(),
      },
    );
  }

  @override
  Future<Uint8List?> bytes(String id) async {
    final db = await _open();
    final txn = db.transaction(_bytes, idbModeReadOnly);
    final data = await txn.objectStore(_bytes).getObject(id);
    await txn.completed;
    if (data is Uint8List) return data;
    if (data is List) return Uint8List.fromList(data.cast<int>());
    return null;
  }

  @override
  Future<void> putTextures(List<StoredTexture> textures) async {
    final db = await _open();
    final txn = db.transaction([_meta, _bytes], idbModeReadWrite);
    for (final t in textures) {
      await txn.objectStore(_meta).put({
        'id': t.id,
        'ground': t.ground.folder,
        'name': t.name,
        'pack': t.packId,
      }, t.id);
      await txn.objectStore(_bytes).put(t.png, t.id);
    }
    await txn.completed;
  }

  @override
  Future<void> deleteTextures(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _open();
    final txn = db.transaction([_meta, _bytes], idbModeReadWrite);
    for (final id in ids) {
      await txn.objectStore(_meta).delete(id);
      await txn.objectStore(_bytes).delete(id);
    }
    await txn.completed;
  }

  @override
  Future<void> putPack(TexturePack pack) => _editPacks(
    (packs) => [
      ...packs.where((p) => p['id'] != pack.id),
      {'id': pack.id, 'name': pack.name, 'author': pack.author},
    ],
  );

  @override
  Future<void> deletePack(String packId) =>
      _editPacks((packs) => [...packs.where((p) => p['id'] != packId)]);

  Future<void> _editPacks(List<Map> Function(List<Map>) edit) async {
    final db = await _open();
    final txn = db.transaction(_settings, idbModeReadWrite);
    final store = txn.objectStore(_settings);
    final current = await store.getObject('packs');
    await store.put(edit(current is List ? current.cast<Map>() : []), 'packs');
    await txn.completed;
  }

  @override
  Future<void> saveSelection(Map<TextureGround, List<String>> selection) async {
    final db = await _open();
    final txn = db.transaction(_settings, idbModeReadWrite);
    await txn.objectStore(_settings).put({
      for (final MapEntry(:key, :value) in selection.entries) key.folder: value,
    }, 'selection');
    await txn.completed;
  }
}
