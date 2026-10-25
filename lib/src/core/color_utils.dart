import 'dart:math' as math;
import 'dart:ui';

/// Returns [color] with its opacity multiplied by [factor].
///
/// [factor] is clamped to 0 through 1, so 0 is invisible and 1 leaves the
/// colour unchanged.
Color scaleAlpha(Color color, double factor) {
  final f = math.min(1.0, math.max(0.0, factor));
  return color.withValues(alpha: color.a * f);
}