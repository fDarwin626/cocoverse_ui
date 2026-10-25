import 'dart:math' as math;

/// A minimal immutable 3D vector used by the effect math.
class Vec3 {
  /// Creates a vector from its components.
  const Vec3(this.x, this.y, this.z);

  /// The zero vector.
  static const Vec3 zero = Vec3(0, 0, 0);

  /// X component (right is positive).
  final double x;

  /// Y component (up is positive).
  final double y;

  /// Z component (toward the viewer is positive).
  final double z;

  /// Component-wise sum.
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  /// Component-wise difference.
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  /// Scales every component by [scalar].
  Vec3 operator *(double scalar) => Vec3(x * scalar, y * scalar, z * scalar);

  /// Dot product with [other].
  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  /// Euclidean length.
  double get length => math.sqrt(x * x + y * y + z * z);

  /// This vector scaled to length 1, or [zero] if its length is 0.
  Vec3 normalized() {
    final l = length;
    return l == 0 ? zero : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}