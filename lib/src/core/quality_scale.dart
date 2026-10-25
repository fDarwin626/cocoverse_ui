import '../api/effect_quality.dart';

/// Internal helpers for scaling detail by [EffectQuality].
extension EffectQualityScale on EffectQuality {
  /// Multiplier applied to element counts such as particles or tiles.
  double get densityScale => switch (this) {
        EffectQuality.low => 0.45,
        EffectQuality.medium => 0.75,
        EffectQuality.high => 1.0,
      };

  /// Scales [count] by [densityScale], never going below [minimum].
  int scaleCount(int count, {int minimum = 1}) {
    final scaled = (count * densityScale).round();
    return scaled < minimum ? minimum : scaled;
  }
}