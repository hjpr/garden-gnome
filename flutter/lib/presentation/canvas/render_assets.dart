import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/feature.dart';
import '../../platform/picture_decoder.dart';

/// The ground textures of the Render view.
enum RenderTexture {
  /// Open land outside every property: grass with weeds and flowers.
  wildGrass(
    'wild_grass.jpg',
    7,
    seed: 11,
    edge: 0,
    variation: 0.07,
    tint: Color(0x268FA850),
  ),

  /// A property's land: a neat lawn.
  lawn(
    'lawn.jpg',
    6,
    seed: 23,
    edge: 0.7,
    edgeNoise: 1.8,
    variation: 0.05,
    tint: Color(0x1A7FB040),
  ),

  /// A zone with no ground set: tidy, raked dirt.
  dirt(
    'dirt.jpg',
    4,
    seed: 37,
    edge: 0.4,
    edgeNoise: 0.9,
    variation: 0.06,
    tint: Color(0x26805A38),
  ),

  /// A zone with flat ground: prepared soil.
  preppedSoil(
    'prepped_soil.jpg',
    4,
    seed: 41,
    edge: 0.4,
    edgeNoise: 0.9,
    variation: 0.05,
    tint: Color(0x1F704028),
  ),

  /// The planted strips of a zone with row ground.
  loam(
    'loam.jpg',
    2.4,
    seed: 53,
    edge: 0,
    variation: 0.06,
    tint: Color(0x00000000),
  );

  const RenderTexture(
    this.file,
    this.metres, {
    required this.seed,
    required this.edge,
    this.edgeNoise = 1,
    required this.variation,
    required this.tint,
  });

  final String file;

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
  RenderAssets._();

  static final RenderAssets instance = RenderAssets._();

  final Map<RenderTexture, ui.Image> _textures = {};
  final Map<FeatureKind, ui.Image> _features = {};
  final Map<TunnelPiece, ui.Image> _tunnel = {};
  final Map<RenderTexture, ui.FragmentShader> _groundShaders = {};
  final Map<RenderTexture, List<double>> _means = {};
  final Map<RenderTexture, ui.FragmentShader> _edgeShaders = {};
  bool _started = false;

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
    _loadGround();
    for (final kind in FeatureKind.values) {
      final file = featureFile(kind);
      if (file != null) _load(file, (image) => _features[kind] = image);
    }
    for (final piece in TunnelPiece.values) {
      _load(piece.file, (image) => _tunnel[piece] = image);
    }
  }

  /// Loads the ground textures, then gives each its own copy of the
  /// ground shader. The shader failing to load leaves plain tiling.
  Future<void> _loadGround() async {
    await Future.wait([
      for (final texture in RenderTexture.values)
        _load(texture.file, (image) => _textures[texture] = image),
    ]);
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/ground.frag');
      for (final MapEntry(key: texture, value: image) in _textures.entries) {
        _means[texture] = await _averageColour(image);
        _groundShaders[texture] = program.fragmentShader();
        _edgeShaders[texture] = program.fragmentShader();
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Ground shader unavailable: $error');
    }
  }

  static Future<List<double>> _averageColour(ui.Image image) async {
    final data = await image.toByteData();
    if (data == null) return const [0.5, 0.5, 0.5];
    final bytes = data.buffer.asUint8List();
    var r = 0, g = 0, b = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      r += bytes[i];
      g += bytes[i + 1];
      b += bytes[i + 2];
    }
    final n = bytes.length / 4 * 255;
    return [r / n, g / n, b / n];
  }

  Future<void> _load(String file, void Function(ui.Image) store) async {
    try {
      final data = await rootBundle.load('assets/render/$file');
      // The same browser-safe decoder as reference pictures.
      store(await decodePicture(data.buffer.asUint8List()));
      notifyListeners();
    } catch (_) {
      // A missing picture leaves the plain colour in its place.
    }
  }
}
