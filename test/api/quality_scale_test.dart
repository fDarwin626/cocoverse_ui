import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/core/quality_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts scale with quality', () {
    expect(EffectQuality.low.scaleCount(100), 45);
    expect(EffectQuality.medium.scaleCount(100), 75);
    expect(EffectQuality.high.scaleCount(100), 100);
  });

  test('the minimum is respected', () {
    expect(EffectQuality.low.scaleCount(1, minimum: 3), 3);
  });
}