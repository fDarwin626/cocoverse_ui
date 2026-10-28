import 'dart:ui';

/// Fine controls for [FoilRing]. Every field is optional and the defaults
/// match the original design, so you only set what you want to change.
///
/// ```dart
/// FoilRing(advanced: const FoilRingAdvanced(rows: 4, glint: 80))
/// ```
class FoilRingAdvanced {
  /// Creates a set of fine controls.
  const FoilRingAdvanced({
    this.cycleMs = 1000.0,
    this.lobes = 3,
    this.ringRadius = 280.0,
    this.tubeRadius = 64.0,
    this.rounding = 45.0,
    this.tilt = 12.0,
    this.centerX = 0.0,
    this.centerY = 0.0,
    this.rows = 3,
    this.strokeLength = 92.0,
    this.strokeWidth = 14.0,
    this.waveAmp = 26.0,
    this.waves = 15.0,
    this.blackShare = 30.0,
    this.sheenShift = 50.0,
    this.glint = 45.0,
    this.speckle = 25.0,
    this.ambient = 55.0,
    this.exposure = 125.0,
    this.aoStrength = 70.0,
    this.lightAngle = 135.0,
    this.lightHeight = 50.0,
    this.strokeBlack = const Color(0xFF020101),
    this.seed = 7,
  });

  /// Milliseconds one lobe step takes at normal speed. Lower is faster.
  /// At least 100.
  final double cycleMs;

  /// Number of sides of the tube's cross-section, 3 to 8.
  final int lobes;

  /// Radius of the ring itself, from 20 to 700.
  final double ringRadius;

  /// Radius of the tube, from 5 to 400.
  final double tubeRadius;

  /// How round the corners of the tube are, from 0 (sharp) to 95.
  final double rounding;

  /// Resting tilt of the ring, in degrees.
  final double tilt;

  /// Moves the ring sideways, in thousandths of the picture size.
  final double centerX;

  /// Moves the ring up, in thousandths of the picture size.
  final double centerY;

  /// Number of stroke rows around the tube, 1 to 12.
  final int rows;

  /// Length of each stroke as a percentage of its row, from 5 to 300.
  final double strokeLength;

  /// Width of each stroke, from 1 to 100.
  final double strokeWidth;

  /// How far strokes wave from side to side, from 0 to 100.
  final double waveAmp;

  /// How many waves a stroke has, from 0 to 60. 0 draws straight strokes.
  final double waves;

  /// Share of strokes that are black, from 0 to 100.
  final double blackShare;

  /// How much the foil colour shifts with the viewing angle, from 0 to 200.
  final double sheenShift;

  /// Strength of the shiny highlight on strokes, from 0 to 200.
  final double glint;

  /// Strength of the fine speckle on strokes, from 0 to 200.
  final double speckle;

  /// How much of the light is ambient rather than directional, from 0 to 100.
  final double ambient;

  /// Overall brightness, from 20 to 300.
  final double exposure;

  /// Strength of the soft shadows in crevices, from 0 to 200.
  final double aoStrength;

  /// Direction the light comes from, in degrees.
  final double lightAngle;

  /// How high the light is, in degrees from -90 to 90.
  final double lightHeight;

  /// Colour of the black strokes.
  final Color strokeBlack;

  /// Changes which strokes get which colours.
  final int seed;
}