import 'dart:ui';

import '../api/effect_quality.dart';

/// Everything an effect needs to draw a single frame.
class EffectFrame {
  /// Creates a frame description.
  const EffectFrame({
    required this.time,
    required this.delta,
    required this.yaw,
    required this.pitch,
    required this.pointer,
    required this.pointerStrength,
    required this.quality,
  });

  /// Animation time in seconds, with speed applied and paused time excluded.
  final double time;

  /// Seconds since the previous frame, with speed applied. Zero when paused.
  final double delta;

  /// Orbit rotation around the vertical axis, in radians.
  final double yaw;

  /// Orbit rotation around the horizontal axis, in radians.
  final double pitch;

  /// Last pointer position in local logical pixels, or null if none yet.
  final Offset? pointer;

  /// How strongly the pointer is acting on the effect, eased from 0 to 1.
  final double pointerStrength;

  /// The requested level of detail.
  final EffectQuality quality;
}

/// Draws one frame of an effect.
typedef EffectPaintCallback = void Function(
  Canvas canvas,
  Size size,
  EffectFrame frame,
);