import 'dart:math' as math;

/// A position or offset on the canvas, measured in metres.
///
/// The x axis grows to the right and the y axis grows downward.
class Vec {
  const Vec(this.x, this.y);

  static const zero = Vec(0, 0);

  final double x;
  final double y;

  Vec operator +(Vec other) => Vec(x + other.x, y + other.y);
  Vec operator -(Vec other) => Vec(x - other.x, y - other.y);
  Vec operator *(double factor) => Vec(x * factor, y * factor);
  Vec operator /(double divisor) => Vec(x / divisor, y / divisor);
  Vec operator -() => Vec(-x, -y);

  double dot(Vec other) => x * other.x + y * other.y;
  double cross(Vec other) => x * other.y - y * other.x;
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Vec other) => (this - other).length;
  bool get isFinite => x.isFinite && y.isFinite;

  @override
  bool operator ==(Object other) =>
      other is Vec && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec($x, $y)';
}
