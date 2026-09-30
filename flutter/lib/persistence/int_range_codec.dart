import '../domain/grow/crop.dart';

/// How an [IntRange] is written in JSON: `[min, max]`, or null for none.
List<int>? encodeRange(IntRange? range) =>
    range == null ? null : [range.min, range.max];

/// A `[min, max]` pair (or a single number) as a range; null when absent
/// or unreadable. For the bundled catalog, where a bad value should cost
/// one field rather than the whole catalog.
IntRange? decodeRange(Object? raw) {
  if (raw is num) return IntRange.single(raw.round());
  if (raw is! List || raw.length != 2) return null;
  final a = raw[0], b = raw[1];
  if (a is! num || b is! num) return null;
  final lo = a.round(), hi = b.round();
  return lo <= hi ? IntRange(lo, hi) : IntRange(hi, lo);
}

/// A `[min, max]` pair as a range, or null when absent. Anything else
/// throws a [FormatException]. For the gardener's own record, where a
/// value that cannot be read must not quietly become "not set".
IntRange? strictRange(Object? raw) {
  if (raw == null) return null;
  if (raw is List && raw.length == 2) {
    final a = raw[0], b = raw[1];
    if (a is int && b is int && a <= b) return IntRange(a, b);
  }
  throw const FormatException('a range is not readable');
}
