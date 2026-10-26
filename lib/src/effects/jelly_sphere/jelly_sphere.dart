import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/color_ramp.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/palette.dart';
import '../../core/shader_library.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/jelly_sphere.frag';

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

/// A glossy sphere with a folded, flowing surface and a glowing core.
///
/// Press it and it squashes like jelly, then wobbles back. Touch or hover and
/// the core blooms under your finger. Drag to spin it, and it eases back to
/// rest when you let go. It fills the space its parent gives it.
class JellySphere extends StatefulWidget {
  /// Creates a jelly sphere.
  const JellySphere({
    super.key,
    this.colors,
    this.background,
    this.size = 0.8,
    this.turbulence = 1.0,
    this.specks = 0.2,
    this.squish = 1.0,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// Four colours: the deep shadows, the main body, the glowing core, and the
  /// bright veins. Any number works and they are spread across the four roles.
  /// If null, they come from the app's theme.
  final List<Color>? colors;

  /// Fill behind the sphere. Null means transparent.
  final Color? background;

  /// Diameter of the sphere as a fraction of the shorter side, from 0.1 to 1.5.
  final double size;

  /// How strongly the surface folds and flows, where 1.0 is the default.
  final double turbulence;

  /// How many small white specks cover the surface, from 0 to 1.
  final double specks;

  /// How strongly a press squashes the sphere. 0 turns it off.
  final double squish;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch, hover, press and drag affect the sphere.
  final bool interactive;

  /// How strongly a drag turns the sphere.
  final double dragSensitivity;

  /// Level of detail. Low is the cheapest, high adds the folds' relief shading.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the sphere as decorative.
  final String? semanticLabel;

  @override
  State<JellySphere> createState() => _JellySphereState();
}

class _JellySphereState extends State<JellySphere> {
  ui.FragmentShader? _shader;
  Paint? _paint;

  double _lastTime = 0;
  double _squash = 0;
  double _squashVelocity = 0;
  bool _wasPressed = false;

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
      debugPrint('JellySphere: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _setColor(ui.FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b);
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    EffectFrame frame,
    ColorRamp ramp,
  ) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    var elapsed = frame.time - _lastTime;
    if (elapsed < 0) {
      _squash = 0;
      _squashVelocity = 0;
      elapsed = 0;
    }
    _lastTime = frame.time;
    elapsed = math.min(elapsed, 0.05);

    // A press gives the spring a kick, then it wobbles back to round.
    if (frame.pressed && !_wasPressed) {
      _squashVelocity -= 2.2 * _clamp(widget.squish, 0, 3);
    }
    _wasPressed = frame.pressed;
    final acceleration = -140 * _squash - 9 * _squashVelocity;
    _squashVelocity += acceleration * elapsed;
    _squash = _clamp(_squash + _squashVelocity * elapsed, -0.45, 0.45);

    final half = math.min(size.width, size.height) / 2;
    final scale =
        _clamp(widget.size, 0.1, 1.5) * (1 + 0.06 * frame.pointerStrength);
    var pointerX = 0.0;
    var pointerY = 0.0;
    final pointer = frame.pointer;
    if (pointer != null) {
      pointerX = (pointer.dx - size.width / 2) / half / scale;
      pointerY = -(pointer.dy - size.height / 2) / half / scale;
    }

    final detail = switch (frame.quality) {
      EffectQuality.low => 0.0,
      EffectQuality.medium => 1.0,
      EffectQuality.high => 2.0,
    };

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, frame.time)
      ..setFloat(3, frame.yaw)
      ..setFloat(4, frame.pitch)
      ..setFloat(5, _squash)
      ..setFloat(6, frame.pointerStrength)
      ..setFloat(7, pointerX)
      ..setFloat(8, pointerY)
      ..setFloat(9, detail)
      ..setFloat(10, scale)
      ..setFloat(11, _clamp(widget.turbulence, 0, 3))
      ..setFloat(12, _clamp(widget.specks, 0, 1) * 0.92);
    _setColor(shader, 13, ramp.at(0));
    _setColor(shader, 16, ramp.at(1 / 3));
    _setColor(shader, 19, ramp.at(2 / 3));
    _setColor(shader, 22, ramp.at(1));

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  Widget build(BuildContext context) {
    final ramp = ColorRamp(resolvePalette(context, widget.colors));
    return EffectHost(
      onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame, ramp),
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      dragSensitivity: widget.dragSensitivity,
      restRate: 2.5,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}