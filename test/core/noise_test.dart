import 'package:cocoverse_ui/src/core/noise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same input always gives the same output', () {
    expect(gradientNoise2(1.37, 2.91), gradientNoise2(1.37, 2.91));
  });

  test('values stay in a sensible range', () {
    for (var i = 0; i < 2000; i++) {
      final v = gradientNoise2(i * 0.173 - 100, i * 0.311 + 50);
      expect(v, inInclusiveRange(-1.5, 1.5));
    }
  });

  test('the noise is zero at whole-number lattice points', () {
    expect(gradientNoise2(3, 4), closeTo(0, 1e-9));
    expect(gradientNoise2(-7, 12), closeTo(0, 1e-9));
  });

  test('nearby inputs give nearby outputs', () {
    final a = gradientNoise2(5.5, 5.5);
    final b = gradientNoise2(5.501, 5.5);
    expect((a - b).abs(), lessThan(0.01));
  });
}