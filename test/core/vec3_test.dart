import 'package:cocoverse_ui/src/core/vec3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds, subtracts and scales', () {
    const a = Vec3(1, 2, 3);
    const b = Vec3(4, 5, 6);
    final sum = a + b;
    expect([sum.x, sum.y, sum.z], [5, 7, 9]);
    final diff = b - a;
    expect([diff.x, diff.y, diff.z], [3, 3, 3]);
    final scaled = a * 2;
    expect([scaled.x, scaled.y, scaled.z], [2, 4, 6]);
  });

  test('dot product and length', () {
    expect(const Vec3(1, 2, 3).dot(const Vec3(4, 5, 6)), 32);
    expect(const Vec3(3, 4, 0).length, closeTo(5, 1e-9));
  });

  test('normalized has length 1, and zero stays zero', () {
    expect(const Vec3(0, 3, 4).normalized().length, closeTo(1, 1e-9));
    expect(Vec3.zero.normalized().length, 0);
  });
}