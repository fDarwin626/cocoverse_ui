import 'dart:math' as math;

import 'vec3.dart';

/// The golden angle in radians, used to spread points evenly.
final double _goldenAngle = math.pi * (3 - math.sqrt(5));

/// Returns [count] points spread evenly over a sphere of radius 1.
///
/// Uses a Fibonacci spiral, so no points bunch up at the poles.
List<Vec3> fibonacciSphere(int count) {
  if (count <= 0) return <Vec3>[];
  return List<Vec3>.generate(count, (i) {
    final y = 1 - 2 * (i + 0.5) / count;
    final radius = math.sqrt(math.max(0.0, 1 - y * y));
    final theta = _goldenAngle * i;
    return Vec3(math.cos(theta) * radius, y, math.sin(theta) * radius);
  });
}