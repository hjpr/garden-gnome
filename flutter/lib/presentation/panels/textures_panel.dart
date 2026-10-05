import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../application/texture_library.dart';
import '../../persistence/texture_pack_codec.dart';
import '../theme.dart';
import '../widgets/property_controls.dart';

/// Preferences > Textures: which square pictures each ground blends, the
/// user's own pictures, and installed texture packs.
///
/// A ground blends 1 to [TextureLibrary.maxSelected] of its textures; a
/// thumbnail's number is its place in the blend (1 sets the colour the
/// others are matched to). Clicking a thumbnail ticks or unticks it.
class TexturesPanel extends StatefulWidget {
  const TexturesPanel({
    super.key,
    required this.library,
    required this.onNotice,
    this.pickPictures,
    this.pickPack,
  });

  final TextureLibrary library;

  /// Shows a message (status-line style) under the panel.
  final void Function(String message, {bool error}) onNotice;

  /// File pickers; tests replace them.
  final Future<List<({String name, Uint8List bytes})>> Function()? pickPictures;
  final Future<({String name, Uint8List bytes})?> Function()? pickPack;

  @override
  State<TexturesPanel> createState() => _TexturesPanelState();
}

class _TexturesPanelState extends State<TexturesPanel> {
  TextureGround _ground = TextureGround.wildGrass;
  bool _busy = false;
  final Map<String, Future<Uint8List>> _thumbs = {};

  TextureLibrary get _library => widget.library;

  @override
  void initState() {
    super.initState();
    _library.load();
  }

  Future<Uint8List> _thumb(String id) => _thumbs[id] ??= _library.bytesOf(id);

  Future<void> _toggle(String id) async {
    final refusal = await _library.toggle(id);
    if (refusal != null) widget.onNotice(refusal, error: true);
  }

  Future<void> _run(Future<String?> Function() job) async {
    setState(() => _busy = true);
    try {
      final message = await job();
      if (message != null) widget.onNotice(message);
    } on TextureImportError catch (error) {
      widget.onNotice(error.message, error: true);
    } catch (_) {
      widget.onNotice('Could not save textures in this browser', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPictures() => _run(() async {
    final pictures = await (widget.pickPictures ?? _pickPictures)();
    if (pictures.isEmpty) return null;
    return _library.addPictures(_ground, pictures);
  });

  Future<void> _installPack() => _run(() async {
    final file = await (widget.pickPack ?? _pickPack)();
    if (file == null) return null;
    final contents = readTexturePack(file.bytes, fileName: file.name);
    return _library.installPack(contents);
  });

  static const _pictures = XTypeGroup(
    label: 'Square pictures',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  static const _packs = XTypeGroup(
    label: 'Texture pack',
    extensions: ['ggtextures', 'zip'],
  );

  static Future<List<({String name, Uint8List bytes})>> _pickPictures() async =>
      [
        for (final f in await openFiles(acceptedTypeGroups: const [_pictures]))
          (name: f.name, bytes: await f.readAsBytes()),
      ];

  static Future<({String name, Uint8List bytes})?> _pickPack() async {
    final f = await openFile(acceptedTypeGroups: const [_packs]);
    return f == null ? null : (name: f.name, bytes: await f.readAsBytes());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _library,
    builder: (context, _) {
      final entries = _library.entries(_ground);
      final selected = _library.selected(_ground);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PropertyGroup(
            title: 'GROUND',
            children: [
              PropertyRow(
                label: 'Ground',
                child: CompactDropdown<TextureGround>(
                  label: 'Ground',
                  value: _ground,
                  items: {for (final g in TextureGround.values) g: g.label},
                  onChanged: (g) => setState(() => _ground = g),
                ),
              ),
            ],
          ),
          PropertyGroup(
            title: 'TEXTURES',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in entries)
                    _Thumb(
                      key: ValueKey(e.id),
                      entry: e,
                      order: selected.indexOf(e.id),
                      bytes: _thumb(e.id),
                      onTap: _busy ? null : () => _toggle(e.id),
                      onRemove: e.origin == TextureOrigin.user && !_busy
                          ? () => _library.removeTexture(e.id)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _addPictures,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add picture'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Back to the built-in textures',
                    child: IconButton(
                      onPressed: _busy || _library.isDefault(_ground)
                          ? null
                          : () => _library.reset(_ground),
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ),
                ],
              ),
            ],
          ),
          PropertyGroup(
            title: 'TEXTURE PACKS',
            children: [
              for (final pack in _library.packs)
                _PackRow(
                  pack: pack,
                  onRemove: _busy
                      ? null
                      : () => _run(() async {
                          await _library.removePack(pack.id);
                          return 'Removed ${pack.name}';
                        }),
                ),
              if (_library.packs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No packs installed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Palette.faint,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _installPack,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: const Text('Install pack'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// One texture: its picture, its place in the blend, where it came from.
class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.entry,
    required this.order,
    required this.bytes,
    required this.onTap,
    required this.onRemove,
  });

  static const double size = 96;

  final TextureEntry entry;

  /// Place in the blend from 0, or -1 when not used.
  final int order;
  final Future<Uint8List> bytes;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final used = order >= 0;
    final radius = BorderRadius.circular(Metrics.radius);
    return Semantics(
      button: true,
      selected: used,
      label: '${entry.name}, ${entry.sourceLabel}',
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: used ? Palette.accent : Palette.panelBorder,
                        width: used ? 3 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Metrics.radius - 1),
                      child: FutureBuilder<Uint8List>(
                        future: bytes,
                        builder: (context, snap) => snap.hasData
                            ? Image.memory(
                                snap.data!,
                                fit: BoxFit.cover,
                                cacheWidth: 192,
                                gaplessPlayback: true,
                              )
                            : const ColoredBox(color: Palette.field),
                      ),
                    ),
                  ),
                  if (used)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Palette.accent,
                        child: Text(
                          '${order + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Palette.paper,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (onRemove != null)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Tooltip(
                        message: 'Remove ${entry.name}',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          style: IconButton.styleFrom(
                            backgroundColor: Palette.paper.withValues(
                              alpha: 0.85,
                            ),
                          ),
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                entry.sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack, required this.onRemove});

  final TexturePack pack;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.inventory_2_outlined, size: 16, color: Palette.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          pack.author == null ? pack.name : '${pack.name} · ${pack.author}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      Tooltip(
        message: 'Remove ${pack.name}',
        child: IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    ],
  );
}
