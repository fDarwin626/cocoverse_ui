import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/orbit_camera.dart';
import '../../core/shader_library.dart';
import '../../core/vec3.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/glass_ring.frag';

const double _camera = 5.0;
const double _tanHalfFov = 0.41421356;
const double _ringRadius = 0.8;

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

/// A turning ring of clear glass that bends whatever is behind it.
///
/// Give it [backdropText] and the text shows through the ring, stretched and
/// split into colour fringes at the edges. Touch and hold to tilt the ring
/// toward your finger, and drag to spin it. It fills the space its parent
/// gives it.
class GlassRing extends StatefulWidget {
  /// Creates a glass ring.
  const GlassRing({
    super.key,
    this.tint = const Color(0xFFFFFFFF),
    this.chromatic = 0.25,
    this.frost = 0.5,
    this.ringSize = 0.7,
    this.thickness = 0.32,
    this.backdropText,
    this.backdropStyle,
    this.backdropColor = const Color(0xFF000000),
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

  /// Colour of the glass. White is clear glass.
  final Color tint;

  /// How far the colours split at the edges, from 0 (none) to 1 (strong).
  final double chromatic;

  /// How frosted the glass looks, from 0 (clear) to 1 (very frosted).
  final double frost;

  /// Diameter of the ring as a fraction of the shorter side, from 0 to 1.
  final double ringSize;

  /// Thickness of the glass tube, from 0 (thin) to 1 (thick).
  final double thickness;

  /// Text drawn behind the ring so you can see it bend. Null draws nothing.
  final String? backdropText;

  /// Style of the backdrop text. If null, large bold white text is used.
  final TextStyle? backdropStyle;

  /// Fill behind the backdrop text.
  final Color backdropColor;

  /// Fill behind the whole effect. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// How fast the ring turns on its own. 0 stops the turning.
  final double spin;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and drag affect the ring.
  final bool interactive;

  /// How strongly a drag turns the ring.
  final double dragSensitivity;

  /// Level of detail. Low skips the frost blur, medium blurs with 4 samples,
  /// high with 8.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the ring as decorative.
  final String? semanticLabel;

  @override
  State<GlassRing> createState() => _GlassRingState();
}

class _GlassRingState extends State<GlassRing> {
  final Paint _platePaint = Paint()..filterQuality = FilterQuality.low;

  ui.FragmentShader? _shader;
  Paint? _paint;
  ui.Image? _plate;
  bool _hasPlate = false;
  int? _plateKey;
  int _plateToken = 0;

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
      });
    } catch (error) {
      debugPrint('GlassRing: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _plateToken++;
    _shader?.dispose();
    _plate?.dispose();
    super.dispose();
  }

  /// Redraws the backdrop image when the size, text or colours change.
  void _requestPlate(Size size, double dpr) {
    final key = Object.hash(
      size.width,
      size.height,
      dpr,
      widget.backdropText,
      widget.backdropColor,
      widget.backdropStyle,
    );
    if (key == _plateKey) return;
    _plateKey = key;
    final token = ++_plateToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildPlate(size, dpr, token);
    });
  }

  Future<void> _buildPlate(Size size, double dpr, int token) async {
    final text = widget.backdropText;
    final hasText = text != null && text.isNotEmpty;
    final width = hasText ? math.max(2, (size.width * dpr).round()) : 1;
    final height = hasText ? math.max(2, (size.height * dpr).round()) : 1;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (hasText) {
      canvas.scale(width / size.width, height / size.height);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = widget.backdropColor,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: widget.backdropStyle ??
              TextStyle(
                color: const Color(0xFFFFFFFF),
                fontSize: size.shortestSide * 0.2,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          (size.width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
      painter.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();

    if (!mounted || token != _plateToken) {
      image.dispose();
      return;
    }
    setState(() {
      _plate?.dispose();
      _plate = image;
      _hasPlate = hasText;
    });
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    final shader = _shader;
    final plate = _plate;
    if (shader == null || plate == null || size.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;

    // The backdrop is drawn first, then the glass refracts the same image.
    if (_hasPlate) {
      canvas.drawImageRect(
        plate,
        Rect.fromLTWH(0, 0, plate.width.toDouble(), plate.height.toDouble()),
        rect,
        _platePaint,
      );
    }

    // Touch acts like hover: the ring leans toward the pointer.
    var tiltYaw = 0.0;
    var tiltPitch = 0.0;
    final pointer = frame.pointer;
    if (pointer != null) {
      final strength = frame.pointerStrength;
      tiltYaw =
          _clamp(pointer.dx / size.width * 2 - 1, -1, 1) * 0.5 * strength;
      tiltPitch =
          _clamp(pointer.dy / size.height * 2 - 1, -1, 1) * 0.5 * strength;
    }
    final sway = 0.2 * math.sin(frame.time * 0.6);
    final rotation = OrbitCamera(
      yaw: frame.yaw + tiltYaw,
      pitch: frame.pitch + tiltPitch + sway,
    );
    final a = rotation.rotate(const Vec3(1, 0, 0));
    final b = rotation.rotate(const Vec3(0, 1, 0));
    final c = rotation.rotate(const Vec3(0, 0, 1));

    final aspect = size.width / size.height;
    final halfShort = _camera * _tanHalfFov * math.min(1.0, aspect);
    final tube = _clamp(widget.thickness, 0.05, 1.0) * 0.5;
    final scale =
        _clamp(widget.ringSize, 0.1, 1.0) * halfShort / (_ringRadius + tube);

    final samples = widget.frost <= 0.001
        ? 0.0
        : switch (frame.quality) {
            EffectQuality.low => 0.0,
            EffectQuality.medium => 4.0,
            EffectQuality.high => 8.0,
          };

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _hasPlate ? 1.0 : 0.0)
      ..setFloat(3, a.x)
      ..setFloat(4, a.y)
      ..setFloat(5, a.z)
      ..setFloat(6, b.x)
      ..setFloat(7, b.y)
      ..setFloat(8, b.z)
      ..setFloat(9, c.x)
      ..setFloat(10, c.y)
      ..setFloat(11, c.z)
      ..setFloat(12, 0)
      ..setFloat(13, math.sin(frame.time * 2) * 0.05)
      ..setFloat(14, scale)
      ..setFloat(15, tube)
      ..setFloat(16, _clamp(widget.chromatic, 0, 1))
      ..setFloat(17, _clamp(widget.frost, 0, 1))
      ..setFloat(18, samples)
      ..setFloat(19, widget.tint.r)
      ..setFloat(20, widget.tint.g)
      ..setFloat(21, widget.tint.b)
      ..setImageSampler(0, plate);

    // The shader is only valid once its image sampler is set, so the Paint is
    // created here, after setImageSampler above.
    final paint = _paint ??= (Paint()..shader = shader);
    canvas.drawRect(rect, paint);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty) {
          _requestPlate(size, dpr);
        }
        return EffectHost(
          onPaint: _paintFrame,
          speed: widget.speed,
          paused: widget.paused,
          interactive: widget.interactive,
          dragSensitivity: widget.dragSensitivity,
          autoRotate: 0.3 * widget.spin,
          quality: widget.quality,
          controller: widget.controller,
          background: widget.background,
          semanticLabel: widget.semanticLabel,
        );
      },
    );
  }
}