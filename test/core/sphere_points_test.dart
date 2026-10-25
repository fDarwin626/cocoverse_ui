import 'package:cocoverse_ui/src/core/sphere_points.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every point sits on the unit sphere', () {
    final points = fibonacciSphere(500);
    expect(points.length, 500);
    for (final p in points) {
      expect(p.length, closeTo(1, 1e-9));
    }
  });

  test('points are balanced between the two hemispheres', () {
    final points = fibonacciSphere(500);
    final sumY = points.fold<double>(0, (sum, p) => sum + p.y);
    expect(sumY, closeTo(0, 1e-9));
  });

  test('zero or negative counts give an empty list', () {
    expect(fibonacciSphere(0), isEmpty);
    expect(fibonacciSphere(-3), isEmpty);
  });
}