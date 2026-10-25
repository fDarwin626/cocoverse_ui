import 'dart:ui';

import 'package:cocoverse_ui/src/core/color_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const red = Color(0xFFFF0000);

  test('scales the opacity', () {
    expect(scaleAlpha(red, 0.5).a, closeTo(0.5, 1e-6));
  });

  test('the factor is clamped to 0 through 1', () {
    expect(scaleAlpha(red, 2).a, closeTo(1, 1e-6));
    expect(scaleAlpha(red, -1).a, closeTo(0, 1e-6));
  });

  test('the colour itself is unchanged', () {
    final faded = scaleAlpha(red, 0.5);
    expect(faded.r, closeTo(1, 1e-6));
    expect(faded.g, closeTo(0, 1e-6));
  });
}