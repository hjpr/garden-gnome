import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes [bytes], scaled to [width] × [height] pixels when given.
Future<ui.Image> decodePicture(
  Uint8List bytes, {
  int? width,
  int? height,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
  );
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  return image;
}
