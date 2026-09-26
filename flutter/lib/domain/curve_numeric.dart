import 'dart:math' as math;

/// Real roots of a quadratic, using the cancellation-free q formulation.
/// This is a floating-point roundoff guard, not a geometric distance tolerance.
List<double> quadraticRoots(
  double a,
  double b,
  double c, {
  double? discriminant,
}) {
  if (a == 0) return b == 0 ? const [] : [-c / b];
  final scale = math.max(a.abs(), math.max(b.abs(), c.abs()));
  a /= scale;
  b /= scale;
  c /= scale;
  if (discriminant == null) {
    final product = 4 * a * c;
    final square = b * b;
    discriminant = square - product;
    final error = 16 * 2.220446049250313e-16 * (square + product.abs());
    if (discriminant.abs() <= error) discriminant = 0;
  } else {
    discriminant = discriminant / scale / scale;
  }
  if (discriminant < 0) return const [];
  if (discriminant == 0) return [-b / (2 * a)];
  final root = math.sqrt(discriminant);
  final q = -0.5 * (b + (b < 0 ? -root : root));
  final roots = [q / a, c / q]..sort();
  return roots;
}
