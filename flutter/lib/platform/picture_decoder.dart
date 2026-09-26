/// Decodes a reference picture into an image the canvas can draw.
///
/// In the browser this goes through plain pixels: the browser decodes the
/// file into a 2D canvas, the RGBA pixels are read back, and Flutter builds
/// the image from them. That avoids Chrome's WebCodecs image decoder, whose
/// GPU-backed frames draw as nothing on some Chrome and graphics-driver
/// combinations (an empty outline where the picture should be). Elsewhere,
/// Flutter's own decoder is used.
library;

export 'picture_decoder_stub.dart'
    if (dart.library.js_interop) 'picture_decoder_web.dart';
