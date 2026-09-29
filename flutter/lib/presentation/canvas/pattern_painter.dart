import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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

/// How one hatch repeats: the tile's side in logical pixels, and how to
/// draw its marks inside a square of that side with the world origin at
/// the tile's corner. Marks that cross an edge are drawn on both sides,
/// so tiles join without seams.
class _TileSpec {
  const _TileSpec(this.key, this.side, this.draw);

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

/// One drawn tile: a hatch in one colour at one screen density.
class _Tile {
  _Tile(this.spec, this.color, this.devicePixelRatio);

  final _TileSpec spec;
  final Color color;
  final double devicePixelRatio;

  String get key => '${spec.key}|${color.toARGB32()}|$devicePixelRatio';
}

/// Tiles already drawn. There are only a few hatch colours, so this stays
/// small.
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
