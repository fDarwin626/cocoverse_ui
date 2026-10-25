import 'dart:ui';

import 'package:cocoverse_ui/src/core/color_ramp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  const red = Color(0xFFFF0000);

  test('the ends of the ramp are the first and last colours', () {
    final ramp = ColorRamp(const [black, white]);
    expect(ramp.at(0), black);
    expect(ramp.at(1), white);
  });

  test('the middle blends the two colours', () {
    final mid = ColorRamp(const [black, white]).at(0.5);
    expect(mid.r, closeTo(0.5, 0.01));
    expect(mid.g, closeTo(0.5, 0.01));
    expect(mid.b, closeTo(0.5, 0.01));
  });

  test('three colours pass through the middle colour', () {
    final ramp = ColorRamp(const [black, red, white]);
    expect(ramp.at(0.5).r, closeTo(1, 0.01));
    expect(ramp.at(0.5).g, closeTo(0, 0.01));
  });

  test('values outside 0 to 1 are clamped', () {
    final ramp = ColorRamp(const [black, white]);
    expect(ramp.at(-5), black);
    expect(ramp.at(5), white);
    expect(ramp.at(double.nan), black);
  });

  test('one colour gives a flat ramp, and no colours gives white', () {
    expect(ColorRamp(const [red]).at(0.7), red);
    expect(ColorRamp(const []).at(0.3), white);
  });

  test('resolution sets the number of steps', () {
    expect(ColorRamp(const [black, white], resolution: 64).steps, 64);
  });
}