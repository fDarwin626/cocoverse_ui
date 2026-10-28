import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/color_ramp.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';
import 'foil_ring_advanced.dart';

export 'foil_ring_advanced.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/foil_ring.frag';

/// The seven foil colours of the original design, in palette order.
const List<Color> _defaultFoil = <Color>[
  Color(0xFF2E1626),
  Color(0xFF892867),
  Color(0xFFC030A0),
  Color(0xFFA52B0D),
  Color(0xFFE8A030),
  Color(0xFF30B0C0),
  Color(0xFF1C3A7A),
];

// The original's default speed (67) as a multiple of its base speed of 50.
const double _baseSpeed = 67 / 50;

// The original draws the ring at 73 percent by default.
const double _baseScale = 0.73;

// Distance of the original's camera, for a 30 degree field of view.
const double _focal = 1.8660254;

/// A twisting ring with a rounded polygon for a cross-section, covered in
/// wavy foil brush strokes.
///
/// Touch it and the ring spins faster, tips toward your finger and shifts a
/// little, then settles back when you let go. It fills the space its parent
/// gives it, but the ring is never drawn wider than [maxDiameter], so it stays
/// cheap on big screens. The area around the ring is transparent.
class FoilRing extends StatefulWidget {
  /// Creates a foil ring.
  const FoilRing({
    super.key,
    this.colors,
    this.baseColor = const Color(0xFF00B9A1),
    this.background,
    this.speed = 1.0,
    this.scale = 1.0,
    this.twist = 4,
    this.strokeCount = 24,
    this.touchResponse = 50.0,
    this.maxDiameter = 320.0,
    this.advanced = const FoilRingAdvanced(),
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  }) : assert(maxDiameter > 0, 'maxDiameter must be greater than zero');

  /// Colours of the foil strokes. Seven are used as they are; any other number
  /// is blended into seven. If null, the colours of the original are used.
  final List<Color>? colors;

  /// Colour of the ring under the strokes.
  final Color baseColor;

  /// Fill behind the ring. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 matches the original, 0 stops it.
  final double speed;

  /// Size of the ring inside its box, from 0.2 to 1.6. 1.0 matches the
  /// original.
  final double scale;

  /// How many times the cross-section twists around the ring, whole numbers
  /// from -16 to 16. 0 gives no twist.
  final int twist;

  /// Number of strokes around the ring, 1 to 120.
  final int strokeCount;

  /// How strongly touch speeds up, tips and shifts the ring, from 0 to 100.
  /// 50 matches the original and 0 turns the response off.
  final double touchResponse;

  /// The widest the ring is ever drawn, in logical pixels. In a bigger box it
  /// stays this size and sits in the centre. A lower value uses less battery.
  /// Raising it makes every frame more expensive.
  final double maxDiameter;

  /// Fine controls. Leave it out to get the original design.
  final FoilRingAdvanced advanced;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the ring.
  final bool interactive;

  /// Level of detail. Lower settings take fewer steps per pixel and use fewer
  /// shadow samples, which keeps the frame rate up on weaker phones.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the ring as decorative.
  final String? semanticLabel;

  @override
  State<FoilRing> createState() => _FoilRingState();
}

class _FoilRingState extends State<FoilRing> {
  ui.FragmentShader? _shader;
  Paint? _paint;

  // The settings last written to the shader. They only change when the widget
  // is rebuilt, so they are written once and not on every frame.
  _Settings? _applied;

  // Motion that is smoothed from one frame to the next, as in the original.
  double _cycles = 0;
  double _over = 0;
  double _targetX = 0;
  double _targetY = 0;
  double _pointerX = 0;
  double _pointerY = 0;
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ShaderLibrary.load(_shaderAsset);
      if (!mounted) return;
      final shader = program.fragmentShader();
      setState(() {
        _shader = shader;
        _paint = Paint()..shader = shader;
        _applied = null;
      });
    } catch (error) {
      debugPrint('FoilRing: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _resetMotion() {
    _cycles = 0;
    _over = 0;
    _targetX = 0;
    _targetY = 0;
    _pointerX = 0;
    _pointerY = 0;
    _lastTime = 0;
  }

  /// Moves the animation on. Runs once per animation tick.
  void _advance(EffectFrame frame, Size size, _Settings s) {
    // A controller reset sends the host's clock back to zero.
    if (frame.time < _lastTime) _resetMotion();
    final dt = frame.time - _lastTime;
    _lastTime = frame.time;

    final pointer = frame.pointer;
    final touching = pointer != null && frame.pointerStrength > 0.5;
    if (touching && size.width > 0 && size.height > 0) {
      _targetX = _unit(pointer.dx / size.width * 2 - 1);
      _targetY = _unit(pointer.dy / size.height * 2 - 1);
    } else {
      _targetX = 0;
      _targetY = 0;
    }
    // Extra repaints inside one tick (touch events) have no time to add.
    if (dt <= 0) return;

    final ease = math.min(1.0, dt * 6);
    _over += ((touching ? 1.0 : 0.0) - _over) * ease;
    _pointerX += (_targetX - _pointerX) * ease;
    _pointerY += (_targetY - _pointerY) * ease;

    final down = frame.pressed ? 1.0 : 0.0;
    final boost = s.hoverK * (0.6 * _over + 0.8 * down);
    final rate = _baseSpeed * s.speed * (1 + boost);
    _cycles = (_cycles + dt * rate * s.cyclesPerSecond) % s.lobes;
  }

  double _unit(double value) => math.min(1.0, math.max(-1.0, value));

  ({double steps, double ao, double aoScale}) _tierFor(EffectQuality quality) =>
      switch (quality) {
        EffectQuality.low => (steps: 36.0, ao: 2.0, aoScale: _aoScale(2)),
        EffectQuality.medium => (steps: 56.0, ao: 3.0, aoScale: _aoScale(3)),
        EffectQuality.high => (steps: 90.0, ao: 4.0, aoScale: _aoScale(4)),
      };

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame, _Settings s) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    if (!identical(_applied, s)) {
      _applyStatic(shader, s);
      _applied = s;
    }
    _advance(frame, size, s);

    // One unit of the original's picture, in pixels. The ring is never drawn
    // wider than maxDiameter.
    final unit = math.min(size.shortestSide, s.maxDiameter / (2 * s.ringUv));
    final origin = size.center(Offset.zero);
    final tier = _tierFor(frame.quality);

    // Touch tips the ring toward the finger and shifts it a little.
    final tiltDegrees = s.tilt + _pointerX * 16 * s.hoverK * _over;
    final tilt = tiltDegrees * math.pi / 180;
    final shiftX = s.centerX + _pointerX * 0.025 * s.hoverK * _over;
    final shiftY = s.centerY - _pointerY * 0.02 * s.hoverK * _over;

    shader
      ..setFloat(0, origin.dx)
      ..setFloat(1, origin.dy)
      ..setFloat(2, unit)
      ..setFloat(4, _cycles * 2 * math.pi)
      ..setFloat(5, tier.steps)
      ..setFloat(6, tier.ao)
      ..setFloat(7, tier.aoScale)
      ..setFloat(14, math.cos(tilt))
      ..setFloat(15, math.sin(tilt))
      ..setFloat(16, shiftX)
      ..setFloat(17, shiftY);

    // Only a square around the ring is drawn, so empty space costs nothing.
    final half = (s.ringUv + 0.04 * s.hoverK) * unit;
    final center = origin + Offset(s.centerX * unit, -s.centerY * unit);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: half * 2, height: half * 2),
      paint,
    );
  }

  /// Writes everything that only changes when the widget is rebuilt.
  void _applyStatic(ui.FragmentShader shader, _Settings s) {
    shader
      ..setFloat(3, s.pixel)
      ..setFloat(8, s.ringRadius)
      ..setFloat(9, s.tubeRadius)
      ..setFloat(10, s.rounding)
      ..setFloat(11, s.lobes)
      ..setFloat(12, s.twist)
      ..setFloat(13, s.objectScale)
      ..setFloat(18, _focal)
      ..setFloat(19, s.strokeCount)
      ..setFloat(20, s.rows)
      ..setFloat(21, s.strokeLength)
      ..setFloat(22, s.strokeWidth)
      ..setFloat(23, s.waveAmp)
      ..setFloat(24, s.waves)
      ..setFloat(25, s.blackShare)
      ..setFloat(26, s.sheenShift)
      ..setFloat(27, s.glint)
      ..setFloat(28, s.speckle)
      ..setFloat(29, s.ambient)
      ..setFloat(30, s.exposure)
      ..setFloat(31, s.lightX)
      ..setFloat(32, s.lightY)
      ..setFloat(33, s.lightZ)
      ..setFloat(34, s.aoStrength)
      ..setFloat(35, s.seedX)
      ..setFloat(36, s.seedY);
    _setColor(shader, 37, s.base);
    _setColor(shader, 40, s.black);
    for (var i = 0; i < 7; i++) {
      _setColor(shader, 43 + i * 3, s.foil[i]);
    }
  }

  void _setColor(ui.FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _Settings(
      widget,
      1 / MediaQuery.devicePixelRatioOf(context),
    );

    return EffectHost(
      onPaint: (canvas, size, frame) =>
          _paintFrame(canvas, size, frame, settings),
      paused: widget.paused,
      interactive: widget.interactive,
      rotatesOnDrag: false,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}

/// Keeps the shadow strength the same when fewer samples are taken.
double _aoScale(int samples) {
  var full = 0.0;
  var used = 0.0;
  var weight = 1.0;
  for (var i = 1; i <= 4; i++) {
    full += weight;
    if (i <= samples) used += weight;
    weight *= 0.65;
  }
  return full / used;
}

int _imul(int a, int b) {
  final ah = (a >> 16) & 0xffff;
  final al = a & 0xffff;
  final bh = (b >> 16) & 0xffff;
  final bl = b & 0xffff;
  return (al * bl + (((ah * bl + al * bh) & 0xffff) << 16)) & 0xffffffff;
}

/// The original's way of turning a whole-number seed into two offsets, with
/// 32-bit whole-number rules so every seed gives the same strokes.
(double, double) _seedOffsets(int seed) {
  var h = _imul((seed ^ 0x9e3779b9) & 0xffffffff, 0x85ebca6b);
  h ^= h >> 13;
  h = _imul(h, 0xc2b2ae35);
  h ^= h >> 16;
  final a = h / 4294967296;
  h = _imul((h ^ 0x27d4eb2f) & 0xffffffff, 0x165667b1);
  h ^= h >> 15;
  final b = h / 4294967296;
  return (a * 61.7, b * 47.3);
}

List<Color> _foilColors(List<Color>? colors) {
  final source = (colors == null || colors.isEmpty) ? _defaultFoil : colors;
  if (source.length == 7) return source;
  final ramp = ColorRamp(source);
  return <Color>[for (var i = 0; i < 7; i++) ramp.at(i / 6)];
}

double _clampValue(double value, double low, double high, double fallback) {
  final safe = value.isFinite ? value : fallback;
  return math.min(high, math.max(low, safe));
}

/// The widget's numbers, clamped to sensible ranges and turned into the units
/// the shader uses.
class _Settings {
  _Settings(FoilRing w, this.pixel) {
    final a = w.advanced;
    final lobesValue = _clampValue(a.lobes.toDouble(), 3, 8, 3).roundToDouble();
    final tubeValue = _clampValue(a.tubeRadius, 5, 400, 64) / 1000;
    final ringValue = _clampValue(a.ringRadius, 20, 700, 280) / 1000;
    final roundValue = _clampValue(a.rounding, 0, 95, 45) / 100;
    final scaleValue = _baseScale * _clampValue(w.scale, 0.2, 1.6, 1.0);

    lobes = lobesValue;
    twist = _clampValue(w.twist.toDouble(), -16, 16, 4).roundToDouble();
    objectScale = scaleValue;
    ringRadius = ringValue;
    tubeRadius = tubeValue;
    rounding = roundValue;
    tilt = _clampValue(a.tilt, -90, 90, 12);
    centerX = _clampValue(a.centerX, -400, 400, 0) / 1000;
    centerY = _clampValue(a.centerY, -400, 400, 0) / 1000;
    strokeCount = _clampValue(w.strokeCount.toDouble(), 1, 120, 24)
        .roundToDouble();
    rows = _clampValue(a.rows.toDouble(), 1, 12, 3).roundToDouble();
    strokeLength = _clampValue(a.strokeLength, 5, 300, 92) / 100;
    strokeWidth = _clampValue(a.strokeWidth, 1, 100, 14) / 1000;
    waveAmp = _clampValue(a.waveAmp, 0, 100, 26) / 100;
    waves = _clampValue(a.waves, 0, 60, 15) / 10;
    blackShare = _clampValue(a.blackShare, 0, 100, 30) / 100;
    sheenShift = _clampValue(a.sheenShift, 0, 200, 50) / 100;
    glint = _clampValue(a.glint, 0, 200, 45) / 100;
    speckle = _clampValue(a.speckle, 0, 200, 25) / 100;
    ambient = _clampValue(a.ambient, 0, 100, 55) / 100;
    exposure = _clampValue(a.exposure, 20, 300, 125) / 100;
    aoStrength = _clampValue(a.aoStrength, 0, 200, 70) / 100;

    final angle = _clampValue(a.lightAngle, -3600, 3600, 135) * math.pi / 180;
    final height = _clampValue(a.lightHeight, -90, 90, 50) * math.pi / 180;
    lightX = math.cos(angle) * math.cos(height);
    lightY = math.sin(angle) * math.cos(height);
    lightZ = math.sin(height);

    final offsets = _seedOffsets(a.seed);
    seedX = offsets.$1;
    seedY = offsets.$2;

    cyclesPerSecond = 1000 / math.max(100.0, _clampValue(a.cycleMs, 0, 1e6, 1000));
    speed = _clampValue(w.speed, 0, 10, 1);
    hoverK = _clampValue(w.touchResponse, 0, 100, 50) / 50;
    maxDiameter = math.max(1.0, w.maxDiameter);

    base = w.baseColor;
    black = a.strokeBlack;
    foil = _foilColors(w.colors);

    // How far the ring reaches on screen, in the original's picture units.
    final an = math.pi / lobesValue;
    final rad = tubeValue * roundValue;
    final corner = (tubeValue - rad) / math.cos(an) + rad;
    final rOut = (ringValue + corner) * scaleValue * 1.03;
    ringUv = rOut / math.sqrt(1 - (rOut / _focal) * (rOut / _focal));
  }

  /// Size of one device pixel in logical pixels.
  final double pixel;

  late final double lobes;
  late final double twist;
  late final double objectScale;
  late final double ringRadius;
  late final double tubeRadius;
  late final double rounding;
  late final double tilt;
  late final double centerX;
  late final double centerY;
  late final double strokeCount;
  late final double rows;
  late final double strokeLength;
  late final double strokeWidth;
  late final double waveAmp;
  late final double waves;
  late final double blackShare;
  late final double sheenShift;
  late final double glint;
  late final double speckle;
  late final double ambient;
  late final double exposure;
  late final double aoStrength;
  late final double lightX;
  late final double lightY;
  late final double lightZ;
  late final double seedX;
  late final double seedY;
  late final double cyclesPerSecond;
  late final double speed;
  late final double hoverK;
  late final double maxDiameter;
  late final double ringUv;
  late final Color base;
  late final Color black;
  late final List<Color> foil;
}