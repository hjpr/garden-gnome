import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

/// Decodes [bytes] in the browser, scaled to [width] × [height] pixels when
/// given, and builds the image from its raw RGBA pixels.
Future<ui.Image> decodePicture(
  Uint8List bytes, {
  int? width,
  int? height,
}) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final options = web.ImageBitmapOptions(
    imageOrientation: 'from-image',
    premultiplyAlpha: 'none',
  );
  if (width != null && height != null) {
    options
      ..resizeWidth = width
      ..resizeHeight = height
      ..resizeQuality = 'high';
  }
  final bitmap = await web.window.createImageBitmap(blob, options).toDart;
  final w = bitmap.width, h = bitmap.height;
  final canvas = web.OffscreenCanvas(w, h);
  final context =
      canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
  context.drawImage(bitmap, 0, 0);
  bitmap.close();
  final pixels = context.getImageData(0, 0, w, h).data.toDart;

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.view(pixels.buffer, pixels.offsetInBytes, pixels.lengthInBytes),
    w,
    h,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}
