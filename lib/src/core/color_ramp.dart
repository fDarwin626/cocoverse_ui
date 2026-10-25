import 'dart:math' as math;
import 'dart:ui';

/// A multi-colour gradient that can be sampled very quickly.
///
/// Effects sample it once per particle or tile per frame, so the colours are
/// precomputed into steps and each lookup is a single array read.
class ColorRamp {
  /// Builds a ramp through [colors], evenly spaced from 0 to 1.
  ///
  /// An empty list gives a plain white ramp. [resolution] is the number of
  /// precomputed steps.
  ColorRamp(List<Color> colors, {int resolution = 256})
      : _lut = _build(colors, math.max(2, resolution));

  final List<Color> _lut;

  static List<Color> _build(List<Color> colors, int steps) {
    if (colors.isEmpty) {
      return List<Color>.filled(steps, const Color(0xFFFFFFFF));
    }
    if (colors.length == 1) {
      return List<Color>.filled(steps, colors.first);
    }
    final last = colors.length - 1;
    return List<Color>.generate(steps, (i) {
      final position = i / (steps - 1) * last;
      final index = position.floor();
      if (index >= last) return colors[last];
      return Color.lerp(colors[index], colors[index + 1], position - index)!;
    });
  }

  /// Number of precomputed steps.
  int get steps => _lut.length;

  /// The colour at position [t], where 0 is the first colour and 1 the last.
  ///
  /// Values outside 0 to 1 are clamped.
  Color at(double t) {
    if (t.isNaN) return _lut.first;
    final clamped = math.min(1.0, math.max(0.0, t));
    return _lut[(clamped * (_lut.length - 1)).round()];
  }
}