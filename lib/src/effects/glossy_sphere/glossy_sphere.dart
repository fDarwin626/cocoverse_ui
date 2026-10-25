import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/color_ramp.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/palette.dart';
import '../../core/shader_library.dart';

const String _shaderAsset =
    'packages/cocoverse_ui/shaders/glossy_sphere.frag';

/// A glass-like sphere with a slowly turning night sky inside it.
///
/// Drag to spin it. It fills the space its parent gives it and draws a circle
/// centred in that space.
class GlossySphere extends StatefulWidget {
  /// Creates a starfield sphere.
  const GlossySphere({
    super.key,
    this.colors,
    this.background,
    this.speed = 1.0,
    this.spin = 1.0,
    this.paused = false,
    this.interactive = true,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// Palette for the sky. Any number of colours works. If null, colours come
  /// from the app's theme.
  final List<Color>? colors;

  /// Fill behind the sphere. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// How fast the sphere turns on its own. 0 stops the turning.
  final double spin;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether dragging spins the sphere.
  final bool interactive;

  /// How strongly a drag turns the sphere.
  final double dragSensitivity;

  /// Level of detail. Lower settings are faster on weak phones.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the sphere as decorative.
  final String? semanticLabel;

  @override
  State<GlossySphere> createState() => _GlossySphereState();
}

class _GlossySphereState extends State<GlossySphere> {
  FragmentShader? _shader;
  Paint? _paint;

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
      debugPrint('GlossySphere: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    EffectFrame frame,
    List<Color> palette,
  ) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, frame.time)
      ..setFloat(3, frame.yaw)
      ..setFloat(4, frame.pitch);
    _setColor(shader, 5, palette[0]);
    _setColor(shader, 8, palette[1]);
    _setColor(shader, 11, palette[2]);
    _setColor(shader, 14, palette[3]);

    canvas.drawRect(Offset.zero & size, paint);
  }

  void _setColor(FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b);
  }

  @override
  Widget build(BuildContext context) {
    final ramp = ColorRamp(resolvePalette(context, widget.colors));
    final palette = <Color>[
      ramp.at(0),
      ramp.at(1 / 3),
      ramp.at(2 / 3),
      ramp.at(1),
    ];

    return EffectHost(
      onPaint: (canvas, size, frame) =>
          _paintFrame(canvas, size, frame, palette),
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      dragSensitivity: widget.dragSensitivity,
      autoRotate: 0.35 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}