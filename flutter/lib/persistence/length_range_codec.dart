import '../domain/grow/crop.dart';

/// The existing `[min, max]` JSON shape, without rounding inch values.
List<num>? encodeLengthRange(LengthRange? range) =>
    range == null ? null : [range.min, range.max];

/// Tolerant catalog reader: accepts a number or a pair, sorts the ends,
/// and leaves absent or unreadable values unset.
LengthRange? decodeLengthRange(Object? raw) {
  if (raw is num) return raw.isFinite ? LengthRange.single(raw) : null;
  if (raw is! List || raw.length != 2) return null;
  final a = raw[0], b = raw[1];
  if (a is! num || b is! num || !a.isFinite || !b.isFinite) return null;
  return a <= b ? LengthRange(a, b) : LengthRange(b, a);
}

/// Strict saved-record reader. Integer pairs remain valid; fractional
/// pairs are retained, but malformed or reversed ranges are refused.
LengthRange? strictLengthRange(Object? raw) {
  if (raw == null) return null;
  if (raw is List && raw.length == 2) {
    final a = raw[0], b = raw[1];
    if (a is num && b is num && a.isFinite && b.isFinite && a <= b) {
      return LengthRange(a, b);
    }
  }
  throw const FormatException('a length range is not readable');
}
