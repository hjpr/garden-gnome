import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/layer.dart';

/// Draws a decorative [pattern] inside [area].
///
/// Spacing is in screen pixels so the pattern stays readable at any zoom.
/// [anchor] is the screen position of the world origin: tying the pattern
/// to it keeps the marks still while the view pans.
///
/// The marks are drawn once into a small repeating tile, and the area is
/// filled with that tile in one draw. Drawing each mark through a clip
/// shaped like the area was far slower, most of all zoomed in.
void paintFillPattern(
  Canvas canvas,
  Path area,
  FillPattern pattern,
  Color color,
  Offset anchor, {
  double devicePixelRatio = 1,
}) {
  final spec = _specs[pattern]!;
  canvas.drawPath(
    area,
    _tilePaint(_Tile(spec, color, devicePixelRatio), anchor),
  );
}

/// Light grey diagonal lines [step] pixels apart along x, filling
/// [region], with [phase] fixing where the lines fall.
void paintHatch(
  Canvas canvas,
  Path region,
  Color color,
  double step,
  Offset phase, {
  double devicePixelRatio = 1,
}) {
  canvas.drawPath(
    region,
    _tilePaint(_Tile(_TileSpec.hatch(step), color, devicePixelRatio), phase),
  );
}

/// Straight line pieces collected so they are drawn in one call. Each
/// piece is still drawn on its own, so crossings look exactly as they did
/// with one drawLine per piece.
class LineBatch {
  final List<double> _coordinates = [];

  bool get isEmpty => _coordinates.isEmpty;

  void add(Offset from, Offset to) =>
      _coordinates.addAll([from.dx, from.dy, to.dx, to.dy]);

  void draw(Canvas canvas, Paint paint) {
    if (isEmpty) return;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.fromList(_coordinates),
      paint,
    );
  }
}

// --------------------------------------------------------------- tiles

/// How one pattern repeats: the tile's side in logical pixels, and how to
/// draw its marks inside a square of that side with the world origin at
/// the tile's corner. Marks that cross an edge are drawn on both sides,
/// so tiles join without seams.
class _TileSpec {
  const _TileSpec(this.key, this.side, this.draw);

  /// Diagonals [spacing] apart. Their repeat along x is spacing·√2, which
  /// is not a whole number of pixels, so the tile holds several repeats
  /// and the spacing is stretched by well under a hundredth of a pixel to
  /// fit exactly.
  factory _TileSpec.diagonal(
    String key,
    double spacing, {
    required int repeats,
    bool crossed = false,
  }) {
    final side = (spacing * math.sqrt2 * repeats).roundToDouble();
    final step = side / repeats;
    return _TileSpec(key, side, (canvas, color) {
      final lines = LineBatch();
      for (var k = -side; k <= 2 * side + 0.001; k += step) {
        // x + y = k (rising) across the tile, from top to bottom.
        lines.add(Offset(k, 0), Offset(k - side, side));
        // x − y = k (falling).
        if (crossed) lines.add(Offset(k - side, 0), Offset(k, side));
      }
      lines.draw(canvas, _stroke(color));
    });
  }

  /// The grey hatch on inactive land: rising lines [step] apart along x.
  factory _TileSpec.hatch(double step) =>
      _TileSpec('hatch$step', step, (canvas, color) {
        final lines = LineBatch();
        for (var k = 0.0; k <= 2 * step + 0.001; k += step) {
          lines.add(Offset(k, 0), Offset(k - step, step));
        }
        lines.draw(canvas, _stroke(color));
      });

  final String key;
  final double side;
  final void Function(Canvas canvas, Color color) draw;
}

Paint _stroke(Color color) => Paint()
  ..color = color
  ..strokeWidth = 1
  ..style = PaintingStyle.stroke;

final Map<FillPattern, _TileSpec> _specs = {
  FillPattern.diagonal: _TileSpec.diagonal('diagonal', 10, repeats: 7),
  FillPattern.crosshatch: _TileSpec.diagonal(
    'crosshatch',
    12,
    repeats: 35,
    crossed: true,
  ),
  FillPattern.rows: _TileSpec('rows', 9, (canvas, color) {
    LineBatch()
      ..add(const Offset(0, 0), const Offset(9, 0))
      ..add(const Offset(0, 9), const Offset(9, 9))
      ..draw(canvas, _stroke(color));
  }),
  FillPattern.grid: _TileSpec('grid', 12, (canvas, color) {
    final lines = LineBatch();
    for (final at in [0.0, 12.0]) {
      lines
        ..add(Offset(0, at), Offset(12, at))
        ..add(Offset(at, 0), Offset(at, 12));
    }
    lines.draw(canvas, _stroke(color));
  }),
  // One dot in the middle of each 10 px cell.
  FillPattern.dots: _TileSpec('dots', 10, (canvas, color) {
    canvas.drawCircle(const Offset(5, 5), 1.8, Paint()..color = color);
  }),
  // One small cross in the middle of each 14 px cell.
  FillPattern.crosses: _TileSpec('crosses', 14, (canvas, color) {
    LineBatch()
      ..add(const Offset(4, 7), const Offset(10, 7))
      ..add(const Offset(7, 4), const Offset(7, 10))
      ..draw(canvas, _stroke(color));
  }),
};

/// One drawn tile: a pattern in one colour at one screen density.
class _Tile {
  _Tile(this.spec, this.color, this.devicePixelRatio);

  final _TileSpec spec;
  final Color color;
  final double devicePixelRatio;

  String get key => '${spec.key}|${color.toARGB32()}|$devicePixelRatio';
}

/// Tiles already drawn. There are only a few patterns and layer colours,
/// so this stays small.
final Map<String, Image> _tiles = {};

/// A paint that fills with [tile], repeated, with a tile corner at
/// [origin] so the marks keep their place as the view moves.
Paint _tilePaint(_Tile tile, Offset origin) {
  final side = tile.spec.side;
  // Drawn at the screen's own density so marks stay as sharp as before.
  final pixels = math.max(1, (side * tile.devicePixelRatio).round());
  final image = _tiles[tile.key] ??= () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixels / side);
    tile.spec.draw(canvas, tile.color);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(pixels, pixels);
    picture.dispose();
    return image;
  }();
  final scale = side / pixels;
  // A tile corner on a whole screen pixel keeps the marks crisp.
  final ratio = tile.devicePixelRatio;
  origin = Offset(
    (origin.dx * ratio).roundToDouble() / ratio,
    (origin.dy * ratio).roundToDouble() / ratio,
  );
  return Paint()
    ..filterQuality = FilterQuality.low
    ..shader = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList([
        scale, 0, 0, 0, //
        0, scale, 0, 0,
        0, 0, 1, 0,
        origin.dx, origin.dy, 0, 1,
      ]),
    );
}
