import 'dart:math' as math;
import 'dart:typed_data';

import 'vec.dart';

/// Largest image file accepted, so saved drawings stay a sensible size.
const int maxReferenceBytes = 20 * 1024 * 1024;

/// Largest decoded image accepted, in pixels.
const int maxReferencePixels = 40 * 1000 * 1000;

/// The picture type from a file's first bytes: 'image/png', 'image/jpeg'
/// or 'image/webp', or null for anything else. The file name is not
/// trusted.
String? imageMimeType(Uint8List bytes) {
  bool starts(List<int> magic, [int at = 0]) =>
      bytes.length >= at + magic.length &&
      [for (var i = 0; i < magic.length; i++) bytes[at + i]].join(',') ==
          magic.join(',');
  if (starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}

/// A picture (site plan, aerial photo, sketch) shown under the land to
/// trace over. It is not land: it has no area and breaks no rules.
///
/// Positions are in metres like the rest of the drawing. The image is
/// placed by its top-left corner and scaled by [metresPerPixel], always
/// keeping its shape. A reference line drawn across the image, together
/// with the real distance it spans, calibrates that scale so traced land
/// comes out the right size.
///
/// Immutable: every change returns a new image, so Undo can keep old ones.
/// The picture is copied once, when the image is made from uploaded or
/// loaded bytes; every later copy shares that read-only picture.
class ReferenceImage {
  ReferenceImage({
    required this.id,
    this.label,
    this.fileName,
    required Uint8List bytes,
    required this.mimeType,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.topLeft,
    required this.metresPerPixel,
    this.lineStart,
    this.lineEnd,
    this.knownDistance,
    this.opacity = 0.6,
    this.locked = false,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  const ReferenceImage._({
    required this.id,
    required this.label,
    required this.fileName,
    required this.bytes,
    required this.mimeType,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.topLeft,
    required this.metresPerPixel,
    required this.lineStart,
    required this.lineEnd,
    required this.knownDistance,
    required this.opacity,
    required this.locked,
  });

  /// Stable identity, such as "image-3". Never reused in a drawing.
  final String id;

  /// A name the user gave the image, or null for the automatic one.
  final String? label;

  /// The name of the file it was uploaded from, if known.
  final String? fileName;

  /// The user's name for the image, else its file name without the
  /// extension, else "Image N" from its ID.
  String get displayName =>
      label ??
      _withoutExtension(fileName) ??
      'Image ${id.substring(id.lastIndexOf('-') + 1)}';

  static String? _withoutExtension(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// The image file exactly as uploaded (PNG, JPEG or WebP).
  final Uint8List bytes;
  final String mimeType;
  final int pixelWidth;
  final int pixelHeight;

  /// World position of the image's top-left corner, in metres.
  final Vec topLeft;

  /// How many metres one image pixel covers.
  final double metresPerPixel;

  /// Ends of the reference line, in image pixels from the top-left, so
  /// they stay on the same spot of the picture when it moves or scales.
  final Vec? lineStart;
  final Vec? lineEnd;

  /// The real length of the reference line in metres, once entered.
  final double? knownDistance;

  /// 0 (invisible) to 1 (solid).
  final double opacity;

  /// A locked image cannot be selected, moved or scaled on the canvas.
  final bool locked;

  double get worldWidth => pixelWidth * metresPerPixel;
  double get worldHeight => pixelHeight * metresPerPixel;
  Vec get bottomRight => topLeft + Vec(worldWidth, worldHeight);
  Vec get centre => topLeft + Vec(worldWidth, worldHeight) / 2;

  /// Corners clockwise from the top-left, in world metres.
  List<Vec> get corners => [
    topLeft,
    topLeft + Vec(worldWidth, 0),
    bottomRight,
    topLeft + Vec(0, worldHeight),
  ];

  Vec toWorld(Vec pixel) => topLeft + pixel * metresPerPixel;
  Vec toPixel(Vec world) => (world - topLeft) / metresPerPixel;

  bool containsWorld(Vec world) {
    final p = toPixel(world);
    return p.x >= 0 && p.y >= 0 && p.x <= pixelWidth && p.y <= pixelHeight;
  }

  bool get hasLine => lineStart != null && lineEnd != null;

  /// The reference line's length on the drawing now, in metres.
  double? get lineLength =>
      hasLine ? lineStart!.distanceTo(lineEnd!) * metresPerPixel : null;

  /// Whether the scale was set from a known distance and not changed by
  /// hand since.
  bool get isCalibrated =>
      hasLine && knownDistance != null && knownDistance! > 0;

  /// A freshly uploaded image, scaled to fit within [fraction] of the
  /// visible area ([viewWidth] by [viewHeight] metres) and centred on
  /// [viewCentre]. It starts uncalibrated.
  static ReferenceImage fitted({
    required String id,
    String? fileName,
    required Uint8List bytes,
    required String mimeType,
    required int pixelWidth,
    required int pixelHeight,
    required Vec viewCentre,
    required double viewWidth,
    required double viewHeight,
    double fraction = 0.8,
  }) {
    final scale = math.min(
      viewWidth * fraction / pixelWidth,
      viewHeight * fraction / pixelHeight,
    );
    final size = Vec(pixelWidth.toDouble(), pixelHeight.toDouble()) * scale;
    return ReferenceImage(
      id: id,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      topLeft: viewCentre - size / 2,
      metresPerPixel: scale,
    );
  }

  /// Moving keeps the calibration: the scale is unchanged.
  ReferenceImage movedBy(Vec delta) => _copy(topLeft: topLeft + delta);

  /// Scales to [newScale] metres per pixel, keeping the world point
  /// [fixed] where it is (for example the corner opposite the one
  /// dragged). A hand-set scale is no longer calibrated, so the known
  /// distance is cleared; the line stays on the picture.
  ReferenceImage scaledAbout(Vec fixed, double newScale) {
    if (!newScale.isFinite || newScale <= 0) {
      throw ArgumentError('The scale must be above zero');
    }
    final pixel = toPixel(fixed);
    return _copy(
      topLeft: fixed - pixel * newScale,
      metresPerPixel: newScale,
      clearDistance: true,
    );
  }

  /// A new reference line between two image pixels. The old distance
  /// belonged to the old line, so it is cleared.
  ReferenceImage withLine(Vec start, Vec end) =>
      _copy(lineStart: start, lineEnd: end, clearDistance: true);

  /// Scales the image so the reference line is [metres] long, keeping
  /// the line's first end where it is on the drawing.
  ReferenceImage calibratedTo(double metres) {
    if (!hasLine) throw StateError('Draw a reference line first');
    if (!metres.isFinite || metres <= 0) {
      throw ArgumentError('The distance must be above zero');
    }
    final pixels = lineStart!.distanceTo(lineEnd!);
    final fixed = toWorld(lineStart!);
    final scale = metres / pixels;
    return _copy(
      topLeft: fixed - lineStart! * scale,
      metresPerPixel: scale,
      knownDistance: metres,
    );
  }

  ReferenceImage withOpacity(double value) =>
      _copy(opacity: value.clamp(0.0, 1.0));

  ReferenceImage withLocked(bool value) => _copy(locked: value);

  /// Renamed; null or blank goes back to the automatic name.
  ReferenceImage withLabel(String? value) {
    final clean = value?.trim();
    return _copy(label: () => clean == null || clean.isEmpty ? null : clean);
  }

  ReferenceImage _copy({
    String? Function()? label,
    Vec? topLeft,
    double? metresPerPixel,
    Vec? lineStart,
    Vec? lineEnd,
    double? knownDistance,
    bool clearDistance = false,
    double? opacity,
    bool? locked,
  }) => ReferenceImage._(
    id: id,
    label: label == null ? this.label : label(),
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    topLeft: topLeft ?? this.topLeft,
    metresPerPixel: metresPerPixel ?? this.metresPerPixel,
    lineStart: lineStart ?? this.lineStart,
    lineEnd: lineEnd ?? this.lineEnd,
    knownDistance: clearDistance ? null : (knownDistance ?? this.knownDistance),
    opacity: opacity ?? this.opacity,
    locked: locked ?? this.locked,
  );

  /// Same picture, placement and settings. The picture is compared by
  /// identity: an upload always makes new bytes.
  @override
  bool operator ==(Object other) =>
      other is ReferenceImage &&
      other.id == id &&
      other.label == label &&
      other.fileName == fileName &&
      identical(other.bytes, bytes) &&
      other.mimeType == mimeType &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight &&
      other.topLeft == topLeft &&
      other.metresPerPixel == metresPerPixel &&
      other.lineStart == lineStart &&
      other.lineEnd == lineEnd &&
      other.knownDistance == knownDistance &&
      other.opacity == opacity &&
      other.locked == locked;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    identityHashCode(bytes),
    topLeft,
    metresPerPixel,
    lineStart,
    lineEnd,
    knownDistance,
    opacity,
    locked,
  );
}
