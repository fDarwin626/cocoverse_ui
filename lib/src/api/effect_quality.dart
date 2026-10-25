/// How much detail an effect draws.
///
/// Lower settings draw fewer elements per frame, which keeps animations smooth
/// on weaker phones.
enum EffectQuality {
  /// Fewest elements. Use on low-end devices.
  low,

  /// A balance of detail and speed.
  medium,

  /// Full detail.
  high,
}