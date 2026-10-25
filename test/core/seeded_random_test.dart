import 'package:cocoverse_ui/src/core/seeded_random.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same seed gives the same sequence', () {
    final a = SeededRandom(42);
    final b = SeededRandom(42);
    for (var i = 0; i < 20; i++) {
      expect(a.nextDouble(), b.nextDouble());
    }
  });

  test('different seeds give different sequences', () {
    expect(SeededRandom(1).nextDouble(), isNot(SeededRandom(2).nextDouble()));
  });

  test('values stay inside their range, even for seed 0', () {
    final r = SeededRandom(0);
    for (var i = 0; i < 1000; i++) {
      final v = r.nextDouble();
      expect(v, inInclusiveRange(0, 0.9999999999));
      expect(r.range(5, 10), inInclusiveRange(5, 10));
      expect(r.nextInt(7), inInclusiveRange(0, 6));
    }
  });
}