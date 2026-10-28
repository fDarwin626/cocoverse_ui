import 'dart:math' as math;
import 'dart:ui';

import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/core/color_ramp.dart';
import 'package:cocoverse_ui/src/core/effect_frame.dart';
import 'package:cocoverse_ui/src/core/effect_host.dart';
import 'package:cocoverse_ui/src/core/shader_library.dart';
import 'package:flutter/widgets.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/urchin.frag';

/// Colours of the original design, from the base of the spikes to their rim.
const List<Color> _defaultColors = <Color>[
  Color(0xFF3400FF),
  Color(0xFF00CFFF),
  Color(0xFFFF00EF),
  Color(0xFFAC0093),
];

/// The web original passes its colours to the GPU as linear light and shows
/// them without converting back, which gives deeper, more saturated colours.
/// Keep this true to look the same as the original. Set it to false to use
/// the colours exactly as they are written.
const bool _matchWebColors = true;

// The original's default speed (9) and spin (9) turned into real rates.
const double _morphRate = 9 * 0.12;
const double _spinRate = 9 * 0.07;

// The original draws the shell at 130 percent of its box by default.
const double _defaultObjectScale = 1.3;

/// A glass-bright sea urchin: a sphere whose radius is a set of standing
/// waves, so it grows spikes, ridges and rings that slowly morph.
///
/// Touch it and it leans toward your finger. It fills the space its parent
/// gives it, but never draws larger than [maxDiameter], so it stays cheap on
/// big screens. The area around it is transparent.
class Urchin extends StatefulWidget {
  /// Creates an urchin.
  const Urchin({
    super.key,
    this.colors,
    this.background,
    this.speed = 1.0,
    this.spin = 1.0,
    this.scale = 1.0,
    this.maxDiameter = 300.0,
    this.lobes = 8,
    this.petals = 8,
    this.rings = 8,
    this.bands = 8,
    this.sharpness = 20.0,
    this.amplitude = 1.0,
    this.morph = 20.0,
    this.tilt = 0.0,
    this.shine = 20.0,
    this.glow = 20.0,
    this.lean = 20.0,
    this.followPointer = true,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  }) : assert(maxDiameter > 0, 'maxDiameter must be greater than zero');

  /// Palette from the base of the spikes to their tips. Four colours are used
  /// as they are: base, middle, tips and rim. Three or fewer map to base,
  /// middle and tips, and the rim is made from the tips colour. More than
  /// four are blended down to four. If null, the colours of the original
  /// design are used.
  final List<Color>? colors;

  /// Fill behind the urchin. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 matches the original.
  final double speed;

  /// How fast it turns on its own. 1.0 matches the original, 0 stops it.
  final double spin;

  /// Size of the urchin inside its box, from 0.2 to 1.1. 1.0 matches the
  /// original, where the spikes nearly touch the edge of the box.
  final double scale;

  /// The largest size, in logical pixels, the urchin is ever drawn at. In a
  /// bigger box it stays this size and sits in the centre. A lower value
  /// uses less battery. Raising it makes every frame more expensive.
  final double maxDiameter;

  /// Number of lobes around the vertical axis, 0 to 8.
  final int lobes;

  /// Number of petals around the vertical axis, 0 to 8.
  final int petals;

  /// Number of rings from pole to pole, 0 to 8.
  final int rings;

  /// Number of bands from pole to pole, 0 to 8.
  final int bands;

  /// How sharp the spikes are, 1 to 20. Higher is thinner.
  final double sharpness;

  /// How tall the spikes are, 1 to 20.
  final double amplitude;

  /// How much the shape drifts over time, 0 to 20.
  final double morph;

  /// Constant tilt toward the viewer, 0 to 20.
  final double tilt;

  /// Tightness of the highlight, 1 to 20. Higher is smaller and brighter.
  final double shine;

  /// Strength of the glow at the edges, 0 to 20.
  final double glow;

  /// How far it leans toward your finger, 0 to 20.
  final double lean;

  /// Whether it leans toward your finger while you touch it.
  final bool followPointer;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the urchin.
  final bool interactive;

  /// Level of detail. Lower settings take fewer steps per pixel, which keeps
  /// the frame rate up on weaker phones.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the urchin as decorative.
  final String? semanticLabel;

  @override
  State<Urchin> createState() => _UrchinState();
}

class _UrchinState extends State<Urchin> {
  FragmentShader? _shader;
  Paint? _paint;

  // Motion that is smoothed from one frame to the next, as in the original.
  double _targetX = 0.5;
  double _targetY = 0.5;
  double _pointerX = 0.5;
  double _pointerY = 0.5;
  double _grip = 0;
  double _leanX = 0;
  double _leanY = 0;
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
      });
    } catch (error) {
      debugPrint('Urchin: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _resetMotion() {
    _targetX = 0.5;
    _targetY = 0.5;
    _pointerX = 0.5;
    _pointerY = 0.5;
    _grip = 0;
    _leanX = 0;
    _leanY = 0;
    _lastTime = 0;
  }

  /// Eases the lean toward the finger. Runs once per animation tick.
  void _advance(EffectFrame frame, Size size, _Settings s) {
    // A controller reset sends the host's clock back to zero.
    if (frame.time < _lastTime) _resetMotion();
    final dt = frame.time - _lastTime;
    _lastTime = frame.time;

    final pointer = frame.pointer;
    if (pointer != null && size.width > 0 && size.height > 0) {
      _targetX = pointer.dx / size.width;
      _targetY = 1 - pointer.dy / size.height;
    }
    // Extra repaints inside one tick (touch events) have no time to add.
    if (dt <= 0) return;

    final pointerEase = 1 - math.exp(-dt * 8);
    _pointerX += (_targetX - _pointerX) * pointerEase;
    _pointerY += (_targetY - _pointerY) * pointerEase;

    final want = widget.followPointer
        ? math.min(1.0, math.max(0.0, frame.pointerStrength))
        : 0.0;
    _grip += (want - _grip) * (1 - math.exp(-dt * 3.5));

    final wantX = -s.tilt - (_pointerY - 0.5) * 2 * s.lean * _grip;
    final wantY = (_pointerX - 0.5) * 2 * s.lean * _grip;
    final leanEase = 1 - math.exp(-dt * 3);
    _leanX += (wantX - _leanX) * leanEase;
    _leanY += (wantY - _leanY) * leanEase;
  }

  ({double steps, double relax}) _tierFor(EffectQuality quality) =>
      switch (quality) {
        EffectQuality.low => (steps: 22.0, relax: 1.0),
        EffectQuality.medium => (steps: 32.0, relax: 0.85),
        EffectQuality.high => (steps: 44.0, relax: 0.7),
      };

  void _paintFrame(
    Canvas canvas,
    Size size,
    EffectFrame frame,
    _Settings s,
    List<double> rgb,
  ) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    _advance(frame, size, s);

    final diameter = math.min(
      math.min(size.width, size.height),
      s.maxDiameter,
    );
    final center = size.center(Offset.zero);
    final tier = _tierFor(frame.quality);
    final time = frame.time * _morphRate;

    shader
      ..setFloat(0, center.dx)
      ..setFloat(1, center.dy)
      ..setFloat(2, diameter / 2)
      ..setFloat(3, s.lobes + math.sin(time * 0.23) * s.morph)
      ..setFloat(4, s.petals + math.sin(time * 0.31 + 1.7) * s.morph)
      ..setFloat(5, s.rings + math.sin(time * 0.19 + 3.1) * s.morph)
      ..setFloat(6, s.bands + math.sin(time * 0.27 + 4.6) * s.morph)
      ..setFloat(7, s.sharpness)
      ..setFloat(8, s.amp)
      ..setFloat(9, s.shine)
      ..setFloat(10, s.glow)
      ..setFloat(11, frame.yaw + _leanY)
      ..setFloat(12, _leanX)
      ..setFloat(13, s.span)
      ..setFloat(14, s.objectScale)
      ..setFloat(15, tier.steps)
      ..setFloat(16, tier.relax)
      ..setFloat(17, s.pixel)
      ..setFloat(18, s.bandMean)
      ..setFloat(19, s.bandNeedle);
    for (var i = 0; i < 12; i++) {
      shader.setFloat(20 + i, rgb[i]);
    }

    // Only the square the urchin lives in is drawn, so a big box costs nothing.
    canvas.drawRect(
      Rect.fromCenter(center: center, width: diameter, height: diameter),
      paint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _Settings(
      widget,
      1 / MediaQuery.devicePixelRatioOf(context),
    );
    final rgb = _paletteFloats(widget.colors);

    return EffectHost(
      onPaint: (canvas, size, frame) =>
          _paintFrame(canvas, size, frame, settings, rgb),
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      rotatesOnDrag: false,
      autoRotate: _spinRate * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}

/// The four shader colours as 12 floats, in the order deep, mid, bright, rim.
List<double> _paletteFloats(List<Color>? colors) {
  final source = (colors == null || colors.isEmpty) ? _defaultColors : colors;
  final List<Color> picks;
  if (source.length >= 4) {
    final ramp = ColorRamp(source);
    picks = <Color>[
      ramp.at(0),
      ramp.at(1 / 3),
      ramp.at(2 / 3),
      ramp.at(1),
    ];
  } else {
    // The original's rim is its tips colour at about two thirds brightness,
    // so with fewer than four colours the rim is made the same way.
    final base = source.first;
    final tips = source.last;
    final middle = source.length == 3 ? source[1] : Color.lerp(base, tips, 0.5)!;
    picks = <Color>[base, middle, tips, _dim(tips)];
  }
  final out = <double>[];
  for (final color in picks) {
    out
      ..add(_channel(color.r))
      ..add(_channel(color.g))
      ..add(_channel(color.b));
  }
  return out;
}

double _channel(double value) => _matchWebColors ? _toLinear(value) : value;

double _toLinear(double value) => value <= 0.04045
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

Color _dim(Color color) => Color.from(
      alpha: color.a,
      red: color.r * 0.675,
      green: color.g * 0.675,
      blue: color.b * 0.675,
    );

/// The power the original raises each wave to.
double _sharpPower(double sharpness) =>
    0.35 + _clampValue(sharpness, 1, 20, 20) * 0.3;

/// Average height of one wave, so thin needles can fade to it.
double _waveMean(double power) {
  const samples = 512;
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    sum += math.pow(math.sin((i + 0.5) / samples * math.pi), power).toDouble();
  }
  return sum / samples;
}

/// Width of a needle as a share of its wave, measured at half its height.
double _needleWidth(double power) =>
    2 * math.acos(math.pow(0.5, 1 / power).toDouble()) / math.pi;

double _clampValue(double value, double low, double high, double fallback) {
  final safe = value.isFinite ? value : fallback;
  return math.min(high, math.max(low, safe));
}

/// The widget's numbers, clamped to the ranges of the original and turned
/// into the units the shader uses.
class _Settings {
  _Settings(Urchin w, this.pixel)
      : lobes = _clampValue(w.lobes.toDouble(), 0, 8, 8).roundToDouble(),
        petals = _clampValue(w.petals.toDouble(), 0, 8, 8).roundToDouble(),
        rings = _clampValue(w.rings.toDouble(), 0, 8, 8).roundToDouble(),
        bands = _clampValue(w.bands.toDouble(), 0, 8, 8).roundToDouble(),
        sharpness = _sharpPower(w.sharpness),
        amp = 0.06 + _clampValue(w.amplitude, 1, 20, 1) * 0.021,
        morph = _clampValue(w.morph, 0, 20, 20) * 0.055,
        tilt = _clampValue(w.tilt, 0, 20, 0) * 0.045,
        shine = 8 + _clampValue(w.shine, 1, 20, 20) * 7,
        glow = _clampValue(w.glow, 0, 20, 20) * 0.055,
        lean = _clampValue(w.lean, 0, 20, 20) * 0.05,
        objectScale =
            _defaultObjectScale * _clampValue(w.scale, 0.2, 1.1, 1.0),
        maxDiameter = math.max(1.0, w.maxDiameter),
        bandMean = _waveMean(_sharpPower(w.sharpness)),
        bandNeedle = _needleWidth(_sharpPower(w.sharpness));

  final double lobes;
  final double petals;
  final double rings;
  final double bands;
  final double sharpness;
  final double amp;
  final double morph;
  final double tilt;
  final double shine;
  final double glow;
  final double lean;
  final double objectScale;
  final double maxDiameter;

  /// Size of one device pixel in logical pixels.
  final double pixel;

  /// Average height of a wave, and how wide a needle is as a share of it.
  final double bandMean;
  final double bandNeedle;
  
  /// How many units the shorter side of the box spans. The original zooms
  /// out as the spikes get taller, so the shell always fits.
  double get span => (0.18 + amp * 4) * 2.7;
}
