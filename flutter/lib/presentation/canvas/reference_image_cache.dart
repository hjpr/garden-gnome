import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../platform/picture_decoder.dart';

/// The size of a decoded picture, in pixels.
typedef PixelSize = ({int width, int height});

/// Decodes a picture to read its size, or returns null when it cannot be
/// read as an image. Animated pictures use their first frame.
Future<PixelSize?> decodeImageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (width: frame.image.width, height: frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// Holds the decoded reference pictures so the painter can draw them every
/// frame without decoding again.
///
/// Decoding is asynchronous; listeners are told when a picture is ready.
/// Pictures are keyed by their bytes (an upload always makes new bytes),
/// and ones no longer in the drawing are released on the next [sync].
class ReferenceImageCache extends ChangeNotifier {
  final Map<Uint8List, ui.Image?> _images = Map.identity();

  /// Longest side, in pixels, of the copy drawn on screen. Browsers cannot
  /// draw a picture larger than their graphics texture limit (often 8192
  /// or 4096 pixels) and show nothing instead, so big pictures are drawn
  /// from a smaller copy. The saved file keeps its full size.
  static const int maxDrawnSide = 4096;

  bool _disposed = false;

  /// Keeps only the pictures for [pictures], starting decodes for new
  /// ones, and returns the decoded images (null while still decoding or
  /// if unreadable), keyed by bytes.
  Map<Uint8List, ui.Image?> sync(Iterable<Uint8List> pictures) {
    final wanted = Set<Uint8List>.identity()..addAll(pictures);
    for (final bytes in _images.keys.toList()) {
      if (!wanted.contains(bytes)) _images.remove(bytes)?.dispose();
    }
    for (final bytes in wanted) {
      if (!_images.containsKey(bytes)) {
        _images[bytes] = null;
        _decode(bytes);
      }
    }
    return Map.unmodifiable(Map.identity()..addAll(_images));
  }

  Future<void> _decode(Uint8List bytes) async {
    final ui.Image image;
    try {
      final size = await decodeImageSize(bytes);
      if (size == null) return;
      final longest = size.width > size.height ? size.width : size.height;
      final shrink = longest > maxDrawnSide ? maxDrawnSide / longest : 1.0;
      image = await decodePicture(
        bytes,
        width: shrink < 1 ? (size.width * shrink).round() : null,
        height: shrink < 1 ? (size.height * shrink).round() : null,
      );
    } catch (_) {
      return;
    }
    // Removed from the drawing, or the cache closed, while decoding.
    if (_disposed || !_images.containsKey(bytes)) {
      image.dispose();
      return;
    }
    _images[bytes] = image;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image?.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
