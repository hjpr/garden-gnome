import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/texture_library.dart';
import '../../application/texture_pixels.dart';
import '../../domain/feature.dart';
import '../../platform/picture_decoder.dart';

/// How much ground one texture repeat covers: 5 ft, so at full zoom one
/// repeat fills the 10 × 10 half-foot grid. Every ground shares it, so
/// clods, blades and leaves keep their relative sizes.
const double _tileMetres = 5 * 0.3048;

/// The ground textures of the Render view.
enum RenderTexture {
  /// Open land outside every property: grass with weeds and flowers.
  wildGrass(
    TextureGround.wildGrass,
    _tileMetres,
    seed: 11,
    edge: 0,
    variation: 0.07,
    tint: Color(0x268FA850),
  ),

  /// A property's land: a neat lawn.
  lawn(
    TextureGround.lawn,
    _tileMetres,
    seed: 23,
    edge: 0.35,
    edgeNoise: 0.9,
    variation: 0.05,
    tint: Color(0x1A7FB040),
  ),

  /// A zone with no ground set: tidy, raked dirt.
  dirt(
    TextureGround.dirt,
    _tileMetres,
    seed: 37,
    edge: 0.2,
    edgeNoise: 0.45,
    variation: 0.06,
    tint: Color(0x26805A38),
  ),

  /// A zone with flat ground: prepared soil.
  preppedSoil(
    TextureGround.preppedSoil,
    _tileMetres,
    seed: 41,
    edge: 0.2,
    edgeNoise: 0.45,
    variation: 0.05,
    tint: Color(0x1F704028),
  ),

  /// The planted strips of a zone with row ground.
  loam(
    TextureGround.loam,
    _tileMetres,
    seed: 53,
    edge: 0,
    variation: 0.06,
    tint: Color(0x00000000),
  ),

  /// Representative flowering canopy, only for the crimson-clover crop.
  crimsonClover(
    TextureGround.crimsonClover,
    _tileMetres,
    seed: 67,
    edge: 0.2,
    edgeNoise: 0.45,
    variation: 0.05,
    tint: Color(0x00000000),
  );

  const RenderTexture(
    this.ground,
    this.metres, {
    required this.seed,
    required this.edge,
    this.edgeNoise = 1,
    required this.variation,
    required this.tint,
  });

  /// Which ground's chosen textures (Preferences > Textures) it paints.
  final TextureGround ground;

  /// How much ground one repeat of the texture covers, in metres.
  final double metres;

  /// Gives each ground its own cell pattern, so grass and dirt side by
  /// side do not break up in the same places.
  final double seed;

  /// How wide, in metres, the ragged band is where a patch of this
  /// ground blends into the ground around it (0 = a clean cut).
  final double edge;

  /// The size, in metres, of the wobbles along that ragged edge.
  final double edgeNoise;

  /// How strongly the brightness drifts across the ground (0 = none).
  final double variation;

  /// The colour patches drift toward (dry grass, damp soil); its alpha
  /// is how far.
  final Color tint;
}

/// The pieces a high tunnel is built from, each drawn as 5 ft of tunnel.
enum TunnelPiece {
  leftEnd('tunnel_end_left.png'),
  middle('tunnel_mid.png'),
  rightEnd('tunnel_end_right.png');

  const TunnelPiece(this.file);

  final String file;
}

/// The Render view's pictures: ground textures and feature illustrations,
/// loaded once from the app's assets and shared by every canvas.
///
/// Loading is asynchronous; listeners are told as pictures arrive, and
/// the painter draws plain colours until then.
class RenderAssets extends ChangeNotifier {
  RenderAssets({AssetBundle? bundle, TextureLibrary? textures})
    : _bundle = bundle ?? rootBundle,
      _library = textures {
    _library?.addListener(_texturesChanged);
  }

  static final RenderAssets instance = RenderAssets(
    textures: AppTextures.instance,
  );
  final AssetBundle _bundle;
  final TextureLibrary? _library;
  final Map<RenderTexture, ui.Size> _grids = {};
  Future<void>? _groundLoading;

  /// The selection each ground was last built from, so a change in
  /// Preferences > Textures rebuilds only the grounds it touched.
  final Map<RenderTexture, String> _builtFrom = {};
  Future<void> _rebuilding = Future.value();

  /// N × 1 for N chosen textures side by side (1 × 1 for one).
  ui.Size atlasGrid(RenderTexture texture) =>
      _grids[texture] ?? const ui.Size(1, 1);

  /// The atlas shrunk 4× and 16×, for zoomed-out views; null when they
  /// were not built (the shader then reads only the full-size picture).
  (ui.Image, ui.Image)? smallCopies(RenderTexture texture) => _small[texture];

  final Map<RenderTexture, ui.Image> _textures = {};
  final Map<RenderTexture, (ui.Image, ui.Image)> _small = {};
  final Map<String, ui.Image> _plants = {};
  final Set<String> _plantsAsked = {};
  final Map<FeatureKind, ui.Image> _features = {};
  final Map<TunnelPiece, ui.Image> _tunnel = {};
  final Map<RenderTexture, ui.FragmentShader> _groundShaders = {};
  final Map<RenderTexture, List<double>> _means = {};
  final Map<RenderTexture, ui.FragmentShader> _edgeShaders = {};
  ui.FragmentProgram? _program;
  bool _started = false;
  bool _disposed = false;

  ui.Image? texture(RenderTexture texture) => _textures[texture];

  /// The non-repeating ground shader for [texture], bound to its picture;
  /// null until both have loaded, or when the page is opened with
  /// `?ground=tiled` to compare against plain tiling.
  ui.FragmentShader? groundShader(RenderTexture texture) =>
      _plainTiling ? null : _groundShaders[texture];

  /// A second copy of [texture]'s ground shader, used to paint the
  /// ragged mask where a patch of it meets the ground around it.
  ui.FragmentShader? edgeShader(RenderTexture texture) =>
      _plainTiling ? null : _edgeShaders[texture];

  /// The average colour of [texture] as r, g, b in 0..1; the shader
  /// needs it to keep contrast where its samples blend.
  List<double> meanColour(RenderTexture texture) =>
      _means[texture] ?? const [0.5, 0.5, 0.5];

  static final bool _plainTiling =
      Uri.base.queryParameters['ground'] == 'tiled';

  /// The picture of a raised bed or greenhouse. High tunnels are built
  /// from [tunnel] pieces instead, so this is null for them.
  ui.Image? feature(FeatureKind kind) => _features[kind];

  ui.Image? tunnel(TunnelPiece piece) => _tunnel[piece];

  /// The overhead picture of plant [kind] (see PlantArt), or null until it
  /// has loaded. The first ask starts loading it, so only plants actually
  /// on the farm take memory; listeners hear when it arrives.
  ui.Image? plant(String kind) {
    final image = _plants[kind];
    if (image != null || !_plantsAsked.add(kind)) return image;
    _load('plants/${kind}_1.png', (image) => _plants[kind] = image);
    return null;
  }

  /// Whether every tunnel piece has loaded.
  bool get tunnelReady => _tunnel.length == TunnelPiece.values.length;

  static String? featureFile(FeatureKind kind) => switch (kind) {
    FeatureKind.raisedBed => 'raised_bed.png',
    FeatureKind.greenhouse => 'greenhouse.png',
    FeatureKind.highTunnel => null,
  };

  /// Starts loading on first use; later calls do nothing.
  void ensureLoaded() {
    if (_started) return;
    _started = true;
    loadGround();
    for (final kind in FeatureKind.values) {
      final file = featureFile(kind);
      if (file != null) _load(file, (image) => _features[kind] = image);
    }
    for (final piece in TunnelPiece.values) {
      _load(piece.file, (image) => _tunnel[piece] = image);
    }
  }

  /// Loads once. Grounds are built one after another, which bounds the
  /// raw pixels held at any moment to one ground's tiles.
  Future<void> loadGround() => _groundLoading ??= _loadGround();

  Future<void> _loadGround() async {
    if (!_plainTiling) {
      try {
        _program = await ui.FragmentProgram.fromAsset('shaders/ground.frag');
      } catch (error) {
        debugPrint('Ground shader unavailable: $error');
      }
    }
    final library = _library;
    if (library == null) return;
    await library.load();
    // Builds run one at a time through one queue: load() itself signals a
    // change, and two builds racing could each skip the other's work.
    _rebuilding = _rebuilding.then((_) => _buildChanged(library));
    await _rebuilding;
  }

  /// Completes once every texture change heard so far has been built.
  @visibleForTesting
  Future<void> get rebuilt => _rebuilding;

  void _texturesChanged() {
    final library = _library;
    if (library == null || _groundLoading == null) return;
    _rebuilding = _rebuilding.then((_) => _buildChanged(library));
  }

  /// Rebuilds every ground whose chosen textures differ from what it was
  /// built from.
  Future<void> _buildChanged(TextureLibrary library) async {
    for (final texture in RenderTexture.values) {
      if (_disposed) return;
      final key = library.selectionKey(texture.ground);
      if (_builtFrom[texture] == key) continue;
      _builtFrom[texture] = key;
      try {
        await _build(texture, await library.selectedTiles(texture.ground));
      } catch (error) {
        debugPrint('Texture ${texture.name} not built: $error');
      }
    }
  }

  /// Builds [texture]'s atlas from [tiles] (each a square picture): the
  /// tiles side by side, later ones matched to the first's colour so the
  /// blend shows no blotches, plus the 4× and 16× smaller copies.
  ///
  /// Without the shader only the first tile is used, as a plain repeat
  /// (an atlas cannot be wrapped tile by tile without it).
  Future<void> _build(RenderTexture texture, List<Uint8List> tiles) async {
    if (tiles.isEmpty) return;
    const size = TexturePixels.tile;
    final program = _program;
    final used = program == null ? tiles.take(1) : tiles;
    final pixels = <Uint8List>[];
    for (final bytes in used) {
      final rgba = await _rgba(bytes, size);
      pixels.add(
        pixels.isEmpty ? rgba : TexturePixels.matchColour(rgba, pixels.first),
      );
    }
    final count = pixels.length;
    final atlas = await _image(
      TexturePixels.packRow(pixels, size),
      size * count,
      size,
    );
    (ui.Image, ui.Image)? small;
    if (program != null) {
      const step = TexturePixels.levelStep;
      final mid = [for (final p in pixels) TexturePixels.shrink(p, size, step)];
      final far = [
        for (final p in mid) TexturePixels.shrink(p, size ~/ step, step),
      ];
      small = (
        await _image(
          TexturePixels.packRow(mid, size ~/ step),
          size ~/ step * count,
          size ~/ step,
        ),
        await _image(
          TexturePixels.packRow(far, size ~/ (step * step)),
          size ~/ (step * step) * count,
          size ~/ (step * step),
        ),
      );
    }
    if (_disposed) {
      atlas.dispose();
      small?.$1.dispose();
      small?.$2.dispose();
      return;
    }
    // Swap in, then let the old pictures go.
    final oldAtlas = _textures[texture];
    final oldSmall = _small[texture];
    _textures[texture] = atlas;
    _grids[texture] = ui.Size(count.toDouble(), 1);
    if (small != null) {
      _small[texture] = small;
    } else {
      _small.remove(texture);
    }
    _means[texture] = TexturePixels.mean(pixels.first);
    if (program != null) {
      _groundShaders[texture] ??= program.fragmentShader();
      _edgeShaders[texture] ??= program.fragmentShader();
    }
    notifyListeners();
    oldAtlas?.dispose();
    oldSmall?.$1.dispose();
    oldSmall?.$2.dispose();
  }

  static Future<Uint8List> _rgba(Uint8List bytes, int size) async {
    final image = await decodePicture(bytes, width: size, height: size);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<ui.Image> _image(Uint8List rgba, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _library?.removeListener(_texturesChanged);
    for (final shader in [..._groundShaders.values, ..._edgeShaders.values]) {
      shader.dispose();
    }
    for (final image in [
      ..._textures.values,
      for (final (mid, far) in _small.values) ...[mid, far],
      ..._features.values,
      ..._tunnel.values,
      ..._plants.values,
    ]) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _load(String file, void Function(ui.Image) store) async {
    try {
      final data = await _bundle.load('assets/render/$file');
      // The same browser-safe decoder as reference pictures.
      store(await decodePicture(data.buffer.asUint8List()));
      notifyListeners();
    } catch (_) {
      // A missing picture leaves the plain colour in its place.
    }
  }
}
