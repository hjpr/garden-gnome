import 'dart:math' as math;
import 'dart:typed_data';

/// Ground-texture pixel work on square RGBA tiles (4 bytes a pixel, alpha
/// ignored and written opaque). Pure Dart, so the same code prepares a
/// picture on import and builds the blended atlas the shader reads.
///
/// makePeriodic and matchColour are ports of tools/render-art/
/// texture_banks.py; keep the two the same.
abstract final class TexturePixels {
  /// Side, in pixels, of every prepared tile: one repeat (5 ft of ground).
  static const int tile = 1024;

  /// Each zoomed-out copy is this much smaller than the one before; the
  /// shader (kLevelStep in shaders/ground.frag) must use the same.
  static const int levelStep = 4;

  /// Makes [rgba] (a [size] × [size] tile) wrap without a seam: near each
  /// edge it cross-fades into the picture shifted by half a tile, whose
  /// edges are the original's continuous middle. The middle is untouched.
  static Uint8List makePeriodic(Uint8List rgba, int size) {
    final px = Float32List(size * size * 3);
    for (var i = 0, j = 0; i < px.length; i += 3, j += 4) {
      px[i] = rgba[j].toDouble();
      px[i + 1] = rgba[j + 1].toDouble();
      px[i + 2] = rgba[j + 2].toDouble();
    }
    final weight = Float32List(size);
    final band = math.max(1.0, size * 0.12);
    for (var i = 0; i < size; i++) {
      final w = (math.min(i, size - 1 - i) / band).clamp(0.0, 1.0);
      weight[i] = w * w * (3 - 2 * w);
    }
    final half = size ~/ 2;
    for (final horizontal in [false, true]) {
      final out = Float32List(px.length);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final w = horizontal ? weight[x] : weight[y];
          final sx = horizontal ? (x + half) % size : x;
          final sy = horizontal ? y : (y + half) % size;
          final a = (y * size + x) * 3, b = (sy * size + sx) * 3;
          for (var c = 0; c < 3; c++) {
            out[a + c] = px[a + c] * w + px[b + c] * (1 - w);
          }
        }
      }
      // Opposite edges meet exactly.
      for (var k = 0; k < size; k++) {
        final first = horizontal ? (k * size) * 3 : k * 3;
        final last = horizontal
            ? (k * size + size - 1) * 3
            : ((size - 1) * size + k) * 3;
        for (var c = 0; c < 3; c++) {
          final join = (out[first + c] + out[last + c]) / 2;
          out[first + c] = join;
          out[last + c] = join;
        }
      }
      px.setAll(0, out);
    }
    return _toRgba(px);
  }

  /// Moves [rgba]'s per-channel mean and contrast onto [reference]'s, so
  /// tiles blended together do not show as lighter or darker blotches.
  /// The contrast gain is capped so a flat picture is not turned to noise.
  static Uint8List matchColour(
    Uint8List rgba,
    Uint8List reference, {
    double maxGain = 1.35,
  }) {
    final (meanS, sdS) = _stats(rgba);
    final (meanR, sdR) = _stats(reference);
    final gain = [
      for (var c = 0; c < 3; c++)
        (sdR[c] / math.max(sdS[c], 1e-3)).clamp(1 / maxGain, maxGain),
    ];
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        out[i + c] = ((rgba[i + c] - meanS[c]) * gain[c] + meanR[c])
            .round()
            .clamp(0, 255);
      }
      out[i + 3] = 255;
    }
    return out;
  }

  /// [rgba] ([size] square) shrunk by [factor], each pixel the average of
  /// a factor × factor block. A seamless tile stays seamless.
  static Uint8List shrink(Uint8List rgba, int size, int factor) {
    final small = size ~/ factor;
    final out = Uint8List(small * small * 4);
    final area = factor * factor;
    for (var y = 0; y < small; y++) {
      for (var x = 0; x < small; x++) {
        var r = 0, g = 0, b = 0;
        for (var dy = 0; dy < factor; dy++) {
          var i = ((y * factor + dy) * size + x * factor) * 4;
          for (var dx = 0; dx < factor; dx++, i += 4) {
            r += rgba[i];
            g += rgba[i + 1];
            b += rgba[i + 2];
          }
        }
        final o = (y * small + x) * 4;
        out[o] = (r / area).round();
        out[o + 1] = (g / area).round();
        out[o + 2] = (b / area).round();
        out[o + 3] = 255;
      }
    }
    return out;
  }

  /// [tiles] (each [size] square) side by side in one row.
  static Uint8List packRow(List<Uint8List> tiles, int size) {
    final width = size * tiles.length;
    final out = Uint8List(width * size * 4);
    for (var t = 0; t < tiles.length; t++) {
      for (var y = 0; y < size; y++) {
        out.setRange(
          (y * width + t * size) * 4,
          (y * width + t * size + size) * 4,
          tiles[t],
          y * size * 4,
        );
      }
    }
    return out;
  }

  /// Mean colour as r, g, b in 0..1.
  static List<double> mean(Uint8List rgba) => [
    for (final m in _stats(rgba).$1) m / 255,
  ];

  static (List<double>, List<double>) _stats(Uint8List rgba) {
    final sum = [0.0, 0.0, 0.0], sq = [0.0, 0.0, 0.0];
    for (var i = 0; i < rgba.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        final v = rgba[i + c].toDouble();
        sum[c] += v;
        sq[c] += v * v;
      }
    }
    final n = rgba.length / 4;
    final mean = [for (final s in sum) s / n];
    final sd = [
      for (var c = 0; c < 3; c++)
        math.sqrt(math.max(0, sq[c] / n - mean[c] * mean[c])),
    ];
    return (mean, sd);
  }

  static Uint8List _toRgba(Float32List px) {
    final out = Uint8List(px.length ~/ 3 * 4);
    for (var i = 0, j = 0; i < px.length; i += 3, j += 4) {
      out[j] = px[i].round().clamp(0, 255);
      out[j + 1] = px[i + 1].round().clamp(0, 255);
      out[j + 2] = px[i + 2].round().clamp(0, 255);
      out[j + 3] = 255;
    }
    return out;
  }
}
