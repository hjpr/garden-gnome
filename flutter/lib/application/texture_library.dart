import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'identifiers.dart';

/// A ground that Render paints with a texture. [folder] names its folder
/// in assets/textures and in texture packs.
enum TextureGround {
  wildGrass('wild_grass', 'Wild grass'),
  lawn('lawn', 'Lawn'),
  dirt('dirt', 'Dirt'),
  preppedSoil('prepped_soil', 'Prepared soil'),
  loam('loam', 'Loam rows'),
  crimsonClover('crimson_clover', 'Crimson clover');

  const TextureGround(this.folder, this.label);

  final String folder;
  final String label;

  static TextureGround? byFolder(String folder) =>
      values.where((g) => g.folder == folder).firstOrNull;
}

/// Where a texture came from.
enum TextureOrigin { builtIn, pack, user }

/// One square ground picture the user can choose for a ground.
class TextureEntry {
  const TextureEntry({
    required this.id,
    required this.ground,
    required this.name,
    required this.origin,
    this.packId,
    this.packName,
  });

  /// `builtin:<ground>/<file>`, `pack:<packId>/<ground>/<file>` or
  /// `user:<uuid>`.
  final String id;
  final TextureGround ground;
  final String name;
  final TextureOrigin origin;
  final String? packId;
  final String? packName;

  /// What the Textures list shows under the picture.
  String get sourceLabel => switch (origin) {
    TextureOrigin.builtIn => 'Built-in',
    TextureOrigin.pack => packName ?? 'Pack',
    TextureOrigin.user => 'Your picture',
  };
}

/// A texture kept in storage: a prepared seamless square PNG.
class StoredTexture {
  const StoredTexture({
    required this.id,
    required this.ground,
    required this.name,
    required this.png,
    this.packId,
  });

  final String id;
  final TextureGround ground;
  final String name;
  final Uint8List png;
  final String? packId;
}

/// An installed texture pack.
class TexturePack {
  const TexturePack({required this.id, required this.name, this.author});

  final String id;
  final String name;
  final String? author;
}

/// Everything the store holds.
class StoredTextures {
  const StoredTextures({
    this.textures = const [],
    this.packs = const [],
    this.selection = const {},
  });

  /// Without picture bytes; read those with [TextureStore.bytes].
  final List<StoredTexture> textures;
  final List<TexturePack> packs;
  final Map<TextureGround, List<String>> selection;
}

/// App-wide storage for installed textures and the chosen ones; never in
/// a farm file.
abstract interface class TextureStore {
  Future<StoredTextures> load();
  Future<Uint8List?> bytes(String id);
  Future<void> putTextures(List<StoredTexture> textures);
  Future<void> deleteTextures(List<String> ids);
  Future<void> putPack(TexturePack pack);
  Future<void> deletePack(String packId);
  Future<void> saveSelection(Map<TextureGround, List<String>> selection);
}

/// Turns any square picture into a prepared texture tile.
abstract interface class TexturePreparer {
  /// A seamless 1024 px square PNG from picture [bytes], whose one repeat
  /// covers [feetPerRepeat] of ground (rescaled to the app's 5 ft).
  /// Throws [TextureImportError] for a picture it cannot use.
  Future<Uint8List> prepare(Uint8List bytes, {double feetPerRepeat});
}

/// The pictures in a texture pack file, read but not yet prepared.
class TexturePackContents {
  const TexturePackContents({
    required this.name,
    this.author,
    this.feetPerRepeat = TextureLibrary.feetPerRepeat,
    required this.pictures,
    this.ignored = 0,
  });

  final String name;
  final String? author;
  final double feetPerRepeat;
  final List<({TextureGround ground, String file, Uint8List bytes})> pictures;

  /// Files in the pack that are not pictures in a known ground folder.
  final int ignored;
}

class TextureImportError implements Exception {
  const TextureImportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The app's one texture library, set at startup (main.dart); null in
/// tests that do not need textures, where Render paints plain colours.
abstract final class AppTextures {
  static TextureLibrary? instance;
}

/// The textures each ground can use and which 1 to 3 of them it blends.
///
/// Built-in textures come with the app (assets/textures); packs and the
/// user's own pictures are prepared on import and kept app-wide. Render
/// listens and rebuilds a ground when its selection changes.
class TextureLibrary extends ChangeNotifier {
  TextureLibrary({
    required TextureStore store,
    required TexturePreparer preparer,
    required Future<Uint8List> Function(String asset) readAsset,
  }) : _store = store,
       _preparer = preparer,
       _readAsset = readAsset;

  /// Most textures a ground blends at once; the shader's atlas holds this
  /// many side by side.
  static const int maxSelected = 3;

  /// Ground covered by one repeat of every prepared texture.
  static const double feetPerRepeat = 5;

  final TextureStore _store;
  final TexturePreparer _preparer;
  final Future<Uint8List> Function(String asset) _readAsset;

  final Map<TextureGround, List<TextureEntry>> _entries = {
    for (final g in TextureGround.values) g: [],
  };
  final Map<TextureGround, List<String>> _defaults = {};
  final Map<TextureGround, List<String>> _selection = {};
  final Map<String, TexturePack> _packs = {};
  Future<void>? _loading;
  bool _loaded = false;

  bool get loaded => _loaded;

  List<TextureEntry> entries(TextureGround ground) =>
      List.unmodifiable(_entries[ground]!);

  List<TexturePack> get packs => List.unmodifiable(_packs.values);

  /// The ids [ground] blends, in order; the first is the colour the others
  /// are matched to.
  List<String> selected(TextureGround ground) =>
      List.unmodifiable(_selection[ground] ?? _defaults[ground] ?? const []);

  bool isDefault(TextureGround ground) =>
      listEquals(selected(ground), _defaults[ground]);

  /// Changes whenever [ground]'s blend changes; Render rebuilds on it.
  String selectionKey(TextureGround ground) => selected(ground).join('|');

  TextureEntry? entry(String id) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final index =
        jsonDecode(utf8.decode(await _readAsset('assets/textures/index.json')))
            as Map<String, Object?>;
    for (final ground in TextureGround.values) {
      final folder = index[ground.folder] as Map<String, Object?>? ?? {};
      for (final file
          in (folder['files'] as List? ?? const []).cast<String>()) {
        _entries[ground]!.add(
          TextureEntry(
            id: 'builtin:${ground.folder}/$file',
            ground: ground,
            name: _nameOf(file),
            origin: TextureOrigin.builtIn,
          ),
        );
      }
      _defaults[ground] = [
        for (final file
            in (folder['default'] as List? ?? const []).cast<String>())
          'builtin:${ground.folder}/$file',
      ];
    }
    try {
      final stored = await _store.load();
      for (final pack in stored.packs) {
        _packs[pack.id] = pack;
      }
      for (final t in stored.textures) {
        _entries[t.ground]!.add(_entryOf(t));
      }
      for (final MapEntry(key: ground, value: ids)
          in stored.selection.entries) {
        final known = [
          for (final id in ids)
            if (entry(id)?.ground == ground) id,
        ].take(maxSelected).toList();
        if (known.isNotEmpty) _selection[ground] = known;
      }
    } catch (error) {
      // Installed textures unavailable: built-ins still work.
      debugPrint('Textures store unavailable: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  TextureEntry _entryOf(StoredTexture t) => TextureEntry(
    id: t.id,
    ground: t.ground,
    name: t.name,
    origin: t.packId == null ? TextureOrigin.user : TextureOrigin.pack,
    packId: t.packId,
    packName: _packs[t.packId]?.name,
  );

  static String _nameOf(String file) {
    final base = file.contains('.')
        ? file.substring(0, file.lastIndexOf('.'))
        : file;
    return base.replaceAll(RegExp(r'[_-]+'), ' ');
  }

  /// The picture bytes of texture [id] (JPEG or PNG).
  Future<Uint8List> bytesOf(String id) async {
    if (id.startsWith('builtin:')) {
      return _readAsset('assets/textures/${id.substring(8)}');
    }
    final bytes = await _store.bytes(id);
    if (bytes == null) throw StateError('Texture $id is missing');
    return bytes;
  }

  /// The selected pictures of [ground], in blend order.
  Future<List<Uint8List>> selectedTiles(TextureGround ground) async => [
    for (final id in selected(ground)) await bytesOf(id),
  ];

  /// Ticks or unticks [id] on its ground. Returns why it was refused, or
  /// null when done.
  Future<String?> toggle(String id) async {
    final e = entry(id);
    if (e == null) return null;
    final current = [...selected(e.ground)];
    if (current.contains(id)) {
      if (current.length == 1) {
        return 'A ground needs at least one texture';
      }
      current.remove(id);
    } else {
      if (current.length >= maxSelected) {
        return 'At most $maxSelected textures blend at once. '
            'Untick one first';
      }
      current.add(id);
    }
    await _select(e.ground, current);
    return null;
  }

  /// Back to the textures [ground] ships with.
  Future<void> reset(TextureGround ground) async {
    _selection.remove(ground);
    await _saveSelection();
    notifyListeners();
  }

  Future<void> _select(TextureGround ground, List<String> ids) async {
    _selection[ground] = ids;
    await _saveSelection();
    notifyListeners();
  }

  Future<void> _saveSelection() => _store.saveSelection({
    for (final MapEntry(:key, :value) in _selection.entries) key: value,
  });

  /// Adds the user's own [pictures] to [ground] and ticks the first if
  /// there is room. Returns a message for the user.
  Future<String> addPictures(
    TextureGround ground,
    List<({String name, Uint8List bytes})> pictures,
  ) async {
    final added = <StoredTexture>[];
    final refused = <String>[];
    for (final picture in pictures) {
      try {
        added.add(
          StoredTexture(
            id: 'user:${newUuid()}',
            ground: ground,
            name: _nameOf(picture.name),
            png: await _preparer.prepare(picture.bytes),
          ),
        );
      } on TextureImportError catch (error) {
        refused.add('${picture.name}: ${error.message}');
      }
    }
    if (added.isNotEmpty) {
      await _store.putTextures(added);
      for (final t in added) {
        _entries[ground]!.add(_entryOf(t));
      }
      final current = selected(ground);
      if (current.length < maxSelected) {
        await _select(ground, [...current, added.first.id]);
      } else {
        notifyListeners();
      }
    }
    if (refused.isEmpty) {
      return added.length == 1
          ? 'Added ${added.first.name}'
          : 'Added ${added.length} textures';
    }
    return [
      if (added.isNotEmpty) 'Added ${added.length}.',
      'Not added: ${refused.join('; ')}',
    ].join(' ');
  }

  /// Installs (or replaces) a texture pack. [onProgress] hears each
  /// picture as it is prepared. Returns a message for the user.
  Future<String> installPack(
    TexturePackContents contents, {
    void Function(int done, int total)? onProgress,
  }) async {
    final id = _slug(contents.name);
    if (_packs.containsKey(id)) await removePack(id, notify: false);
    final pack = TexturePack(
      id: id,
      name: contents.name,
      author: contents.author,
    );
    final prepared = <StoredTexture>[];
    var skipped = 0;
    for (final (i, picture) in contents.pictures.indexed) {
      onProgress?.call(i, contents.pictures.length);
      try {
        prepared.add(
          StoredTexture(
            id: 'pack:$id/${picture.ground.folder}/${picture.file}',
            ground: picture.ground,
            name: _nameOf(picture.file),
            packId: id,
            png: await _preparer.prepare(
              picture.bytes,
              feetPerRepeat: contents.feetPerRepeat,
            ),
          ),
        );
      } on TextureImportError {
        skipped++;
      }
    }
    if (prepared.isEmpty) {
      return '${contents.name} has no square pictures to install';
    }
    await _store.putPack(pack);
    await _store.putTextures(prepared);
    _packs[id] = pack;
    for (final t in prepared) {
      _entries[t.ground]!.add(_entryOf(t));
    }
    notifyListeners();
    final grounds = prepared.map((t) => t.ground).toSet().length;
    final extra = skipped + contents.ignored;
    return 'Installed ${contents.name}: ${prepared.length} textures for '
        '$grounds ${grounds == 1 ? 'ground' : 'grounds'}'
        '${extra > 0 ? ' ($extra files skipped)' : ''}';
  }

  /// Removes pack [packId] and its textures; grounds using them fall back
  /// to what is left of their selection, or their built-ins.
  Future<void> removePack(String packId, {bool notify = true}) async {
    final ids = [
      for (final list in _entries.values)
        for (final e in list)
          if (e.packId == packId) e.id,
    ];
    await _store.deleteTextures(ids);
    await _store.deletePack(packId);
    _packs.remove(packId);
    await _forget(ids.toSet());
    if (notify) notifyListeners();
  }

  /// Removes one of the user's own pictures.
  Future<void> removeTexture(String id) async {
    final e = entry(id);
    if (e == null || e.origin != TextureOrigin.user) return;
    await _store.deleteTextures([id]);
    await _forget({id});
    notifyListeners();
  }

  Future<void> _forget(Set<String> ids) async {
    for (final list in _entries.values) {
      list.removeWhere((e) => ids.contains(e.id));
    }
    for (final ground in [..._selection.keys]) {
      final left = _selection[ground]!
          .where((id) => !ids.contains(id))
          .toList();
      left.isEmpty ? _selection.remove(ground) : _selection[ground] = left;
    }
    await _saveSelection();
  }

  static String _slug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'pack' : slug;
  }
}
