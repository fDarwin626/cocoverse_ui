import 'dart:ui';

import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/core/color_ramp.dart';
import 'package:cocoverse_ui/src/core/effect_frame.dart';
import 'package:cocoverse_ui/src/core/effect_host.dart';
import 'package:cocoverse_ui/src/core/palette.dart';
import 'package:cocoverse_ui/src/core/shader_library.dart';
import 'package:flutter/widgets.dart';


const String _shaderAsset =
    'packages/cocoverse_ui/shaders/starfield_sphere.frag';

/// A clear glass sphere with small stars drifting inside it.
///
/// Drag to spin it. It fills the space its parent gives it and draws a circle
/// centred in that space, with the area behind it showing through.
class StarfieldSphere extends StatefulWidget {
  /// Creates a starfield sphere.
  const StarfieldSphere({
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

  /// Palette for the glass and mist. Any number of colours works. If null,
  /// colours come from the app's theme.
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

  /// Level of detail. Low draws one shell of stars, medium two, high three.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the sphere as decorative.
  final String? semanticLabel;

  @override
  State<StarfieldSphere> createState() => _StarfieldSphereState();
}

class _StarfieldSphereState extends State<StarfieldSphere> {
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
      debugPrint('StarfieldSphere: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  double _detail(EffectQuality quality) => switch (quality) {
        EffectQuality.low => 0,
        EffectQuality.medium => 1,
        EffectQuality.high => 2,
      };

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
      ..setFloat(4, frame.pitch)
      ..setFloat(5, _detail(frame.quality));
    _setColor(shader, 6, palette[0]);
    _setColor(shader, 9, palette[1]);
    _setColor(shader, 12, palette[2]);
    _setColor(shader, 15, palette[3]);

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
      autoRotate: 0.25 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}