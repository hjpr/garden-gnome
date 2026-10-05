import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../application/texture_library.dart';
import '../../application/texture_pixels.dart';
import '../../platform/picture_decoder.dart';

/// Prepares an imported picture with the browser-safe decoder: checks it
/// is square, brings its repeat to 5 ft, resizes it to 1024 px and makes
/// it seamless, then stores it as PNG.
class UiTexturePreparer implements TexturePreparer {
  const UiTexturePreparer();

  /// Width / height may differ by this share and still count as square
  /// (the extra is cropped off).
  static const double squareTolerance = 0.02;

  @override
  Future<Uint8List> prepare(
    Uint8List bytes, {
    double feetPerRepeat = TextureLibrary.feetPerRepeat,
  }) async {
    final ui.Image probe;
    try {
      probe = await decodePicture(bytes);
    } catch (_) {
      throw const TextureImportError('not a picture this app can read');
    }
    final w = probe.width, h = probe.height;
    probe.dispose();
    if ((w - h).abs() > math.max(w, h) * squareTolerance) {
      throw const TextureImportError('textures must be square (1:1)');
    }
    if (math.min(w, h) < 256) {
      throw const TextureImportError('textures must be at least 256 px');
    }
    const tile = TexturePixels.tile;
    final feet = TextureLibrary.feetPerRepeat;
    Uint8List rgba;
    if (feetPerRepeat >= feet) {
      // The picture covers more ground than one repeat: keep its middle
      // 5 ft square.
      final side = (tile * feetPerRepeat / feet).round();
      final full = await _pixels(bytes, side);
      rgba = TexturePixels.makePeriodic(_crop(full, side, tile), tile);
    } else {
      // Less ground: repeat it (a whole number of times, so it still
      // wraps) after making the small copy seamless.
      final times = math.max(1, (feet / feetPerRepeat).round());
      final small = tile ~/ times;
      final once = TexturePixels.makePeriodic(
        await _pixels(bytes, small),
        small,
      );
      rgba = _repeat(once, small, tile);
    }
    return _png(rgba, tile);
  }

  /// [bytes] decoded at [side] × [side]; a picture up to 2% off square is
  /// stretched that little to fit.
  static Future<Uint8List> _pixels(Uint8List bytes, int side) async {
    final image = await decodePicture(bytes, width: side, height: side);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static Uint8List _crop(Uint8List rgba, int size, int keep) {
    final start = (size - keep) ~/ 2;
    final out = Uint8List(keep * keep * 4);
    for (var y = 0; y < keep; y++) {
      out.setRange(
        y * keep * 4,
        (y + 1) * keep * 4,
        rgba,
        ((start + y) * size + start) * 4,
      );
    }
    return out;
  }

  static Uint8List _repeat(Uint8List rgba, int size, int target) {
    final out = Uint8List(target * target * 4);
    for (var y = 0; y < target; y++) {
      for (var x = 0; x < target; x++) {
        final s = ((y % size) * size + x % size) * 4;
        out.setRange((y * target + x) * 4, (y * target + x) * 4 + 4, rgba, s);
      }
    }
    return out;
  }

  static Future<Uint8List> _png(Uint8List rgba, int size) async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      size,
      size,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final image = await done.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }
}
