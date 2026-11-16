import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

/// Where the shader is loaded from. Written the same way as the Meteor path.
const String _asset = 'packages/cocoverse_ui/shaders/crossfold.frag';

const double _tau = math.pi * 2;
const double _deg = math.pi / 180;

// Seconds per rest / unfold / hold / fold cycle at Speed 100.
const double _cycleSec = 3.45;
const double _fRest = 0.40;
const double _fExpand = 0.31;
const double _fCollapse = 0.29;

// The camera: a fixed turn and a lens, like the website's.
const double _yaw = 45 * _deg;
const double _fov = 28 * _deg;

// The bars: half sizes, the bevel on every edge, and how far apart they park.
const double _barX = 1.6;
const double _barY = 0.28;
const double _barZ = 0.28;
const double _chamfer = 0.045;
const double _park = 0.72;

// What the shader holds, and the ball that holds the whole figure.
const int _bars = 3;
const int _planesPerBar = 26;
const double _reach = 1.95;
const double _figureRadius = 1.7;

/// How the bars look.
enum CrossfoldFinish {
  /// Polished metal, reflecting a studio. The original.
  metallic,

  /// Matt plastic: soft light on the colour, with a small glint on the edges.
  matte,
}

/// Three bars that fold out of a stack into a cross, hold, and fold back,
/// turning slowly all the while. A loading asset.
///
/// It has no child and no text. Put your own `Text` next to it wherever you
/// want. It has no background unless you give one. It fills the space it is
/// given, drawn from the shorter side. The bars are drawn by a fragment
/// shader, `crossfold.frag`, which has to be listed under `shaders:` in the
/// package's pubspec.
///
/// ```dart
/// Column(
///   mainAxisSize: MainAxisSize.min,
///   children: const [
///     SizedBox(
///       height: 160,
///       width: 160,
///       child: Crossfold(color: Color(0xFFD4AF37)),
///     ),
///     Text('Loading...'),
///   ],
/// )
/// ```
class Crossfold extends StatefulWidget {
  /// Creates a folding cross.
  const Crossfold({
    super.key,
    this.color = const Color(0xFFB2B2B2),
    this.finish = CrossfoldFinish.metallic,
    this.roughness = 64.0,
    this.reflect = 67.0,
    this.size = 5.0,
    this.spin = 18.0,
    this.reverseSpin = false,
    this.fold = 90.0,
    this.hold = 30.0,
    this.speed = 100.0,
    this.tilt = 35.0,
    this.sideTilt = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.progress,
    this.background,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// The one colour of the bars.
  final Color color;

  /// Metal or matt plastic.
  final CrossfoldFinish finish;

  /// How blurred the reflection is, as a percentage from 0 to 100. On the
  /// matte finish it is how dull the plastic is.
  final double roughness;

  /// How much of the colour the metal gives back, from 0 to 100. The matte
  /// finish ignores it.
  final double reflect;

  /// How much of the box the figure fills, from 0 to 10.
  final double size;

  /// How fast it turns, in degrees a second. 0 stops the turning.
  final double spin;

  /// Turns it the other way.
  final bool reverseSpin;

  /// How far the side bars swing, in degrees, from 0 to 180. 90 is a cross.
  final double fold;

  /// How long it stays assembled, as a percentage of a cycle, from 0 to 100.
  final double hold;

  /// How fast time runs, as a percentage. 100 is normal. 0 stops the folding
  /// and leaves it assembled.
  final double speed;

  /// The view from above, in degrees, from -85 to 85.
  final double tilt;

  /// Rolls the view sideways, in degrees.
  final double sideTilt;

  /// Moves it across the box, as a percentage of the width, -50 to 50.
  final double offsetX;

  /// Moves it down the box, as a percentage of the height, -50 to 50.
  final double offsetY;

  /// 0 to 1 turns it into a loader: folded up at 0, a full cross at 1, and
  /// it eases between values. Null is the endless loop.
  final double? progress;

  /// A colour painted behind it. Null leaves it transparent.
  final Color? background;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. High smooths the edges with four rays a pixel.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] restarts the cycle from the
  /// folded stack.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative.
  final String? semanticLabel;

  @override
  State<Crossfold> createState() => _CrossfoldState();
}

// ─── Small maths ─────────────────────────────────────────────────────────────

class _V {
  const _V(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

_V _rotY(_V p, double a) {
  final c = math.cos(a);
  final s = math.sin(a);
  return _V(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

_V _rotX(_V p, double a) {
  final c = math.cos(a);
  final s = math.sin(a);
  return _V(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

_V _rotZ(_V p, double a) {
  final c = math.cos(a);
  final s = math.sin(a);
  return _V(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

_V _qrot(double qx, double qy, double qz, double qw, _V v) {
  final cx = qy * v.z - qz * v.y + qw * v.x;
  final cy = qz * v.x - qx * v.z + qw * v.y;
  final cz = qx * v.y - qy * v.x + qw * v.z;
  return _V(
    v.x + 2 * (qy * cz - qz * cy),
    v.y + 2 * (qz * cx - qx * cz),
    v.z + 2 * (qx * cy - qy * cx),
  );
}

double _clamp(double v, double lo, double hi) {
  final safe = v.isFinite ? v : lo;
  return math.min(hi, math.max(lo, safe));
}

double _lin(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

int _tier(EffectQuality q) => switch (q) {
      EffectQuality.low => 0,
      EffectQuality.medium => 1,
      EffectQuality.high => 2,
    };

double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeIn(double t) => t * t * t;

/// Where in the rest / unfold / hold / fold loop it is, as 0 (a stack) to 1
/// (a cross). [u] is the loop's phase, [hold] the held share, both 0 to 1.
double _extension(double u, double hold) {
  final h = _clamp(hold, 0, 1);
  final rem = 1 - h;
  if (rem <= 1e-6) return 1;
  final tRest = rem * _fRest;
  final tExp = rem * _fExpand;
  final tCol = rem * _fCollapse;
  final p = u - u.floorToDouble();
  if (p < tRest) return 0;
  if (p < tRest + tExp) return _easeOut((p - tRest) / tExp);
  if (p < tRest + tExp + h) return 1;
  return 1 - _easeIn(math.min((p - tRest - tExp - h) / tCol, 1.0));
}

// ─── One chamfered bar, as planes ────────────────────────────────────────────

Float64List? _barCache;

/// The 26 planes of one bar (6 faces, 12 edge bevels, 8 corner bevels), each
/// as a normal and an offset, with the bar's middle at the origin. A point is
/// inside when it is behind every plane.
Float64List _barPlanes() {
  final cached = _barCache;
  if (cached != null) return cached;
  const h = <double>[_barX, _barY, _barZ];
  const c = _chamfer;
  const r2 = 0.7071067811865476;
  const r3 = 0.5773502691896258;
  final out = Float64List(_planesPerBar * 4);
  var o = 0;
  void put(double x, double y, double z, double d) {
    out[o++] = x;
    out[o++] = y;
    out[o++] = z;
    out[o++] = d;
  }

  for (var a = 0; a < 3; a++) {
    for (final s in const <double>[-1, 1]) {
      final n = <double>[0, 0, 0];
      n[a] = s;
      put(n[0], n[1], n[2], h[a]);
    }
  }
  for (var a = 0; a < 3; a++) {
    for (var b = a + 1; b < 3; b++) {
      for (final sa in const <double>[-1, 1]) {
        for (final sb in const <double>[-1, 1]) {
          final n = <double>[0, 0, 0];
          n[a] = sa * r2;
          n[b] = sb * r2;
          put(n[0], n[1], n[2], (h[a] + h[b] - c) * r2);
        }
      }
    }
  }
  for (final sx in const <double>[-1, 1]) {
    for (final sy in const <double>[-1, 1]) {
      for (final sz in const <double>[-1, 1]) {
        put(sx * r3, sy * r3, sz * r3, (h[0] + h[1] + h[2] - 2 * c) * r3);
      }
    }
  }
  _barCache = out;
  return out;
}

// ─── The state ───────────────────────────────────────────────────────────────

Future<ui.FragmentProgram?>? _programFuture;

Future<ui.FragmentProgram?> _loadProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(_asset);
  } catch (e) {
    debugPrint(
      'Crossfold: could not load the shader at $_asset ($e). Check the '
      'shaders: list in pubspec.yaml and the path in crossfold.dart.',
    );
    return null;
  }
}

class _CrossfoldState extends State<Crossfold> {
  final Paint _paint = Paint();
  final Paint _bg = Paint();
  ui.FragmentShader? _shader;

  bool _reduced = false;
  double _lastTime = 0;
  double _cycle = 0;
  double _spin = 0;
  double _ext = 1;
  int _seenResets = 0;

  final Float64List _planes = Float64List(_bars * _planesPerBar * 4);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
    _programFuture ??= _loadProgram();
    unawaited(
      _programFuture!.then((program) {
        if (!mounted || program == null) return;
        _shader = program.fragmentShader();
      }),
    );
  }

  @override
  void didUpdateWidget(Crossfold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _seenResets = widget.controller?.resetCount ?? 0;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _cycle = 0;
      _ext = 0;
    }
  }

  /// Puts one bar's planes into the world: posed, then turned with the rest.
  void _pose(int part, double qx, double qy, double qz, double qw, _V t,
      double spin) {
    final lp = _barPlanes();
    final tw = _rotY(t, spin);
    for (var k = 0; k < _planesPerBar; k++) {
      final n = _qrot(qx, qy, qz, qw, _V(lp[k * 4], lp[k * 4 + 1], lp[k * 4 + 2]));
      final nw = _rotY(n, spin);
      final i = (part * _planesPerBar + k) * 4;
      _planes[i] = nw.x;
      _planes[i + 1] = nw.y;
      _planes[i + 2] = nw.z;
      _planes[i + 3] = lp[k * 4 + 3] + nw.x * tw.x + nw.y * tw.y + nw.z * tw.z;
    }
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 8 || size.height < 8) return;
    final w = widget;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.1) dt = 0.1;
    if (w.paused || _reduced) dt = 0;

    // The clocks. Turning does not depend on Speed; folding does.
    _spin = (_spin + dt * w.spin * _deg * (w.reverseSpin ? -1.0 : 1.0)) % _tau;
    final rate = _clamp(w.speed, 0, 300) / 100;
    final progress = w.progress;
    if (_reduced) {
      _ext = 1;
    } else if (progress != null) {
      final p = _clamp(progress, 0, 1);
      final target = p * p * (3 - 2 * p);
      _ext += (target - _ext) * (1 - math.exp(-dt * 7));
    } else if (rate <= 0) {
      _ext = 1;
    } else {
      _cycle = (_cycle + dt * rate / _cycleSec) % 1.0;
      _ext = _extension(_cycle, _clamp(w.hold, 0, 100) / 100);
    }

    // The three bars.
    final a = _clamp(w.fold, 0, 180) * _deg * _ext;
    final back = _park * (1 - _ext);
    final sa = math.sin(a / 2);
    final ca = math.cos(a / 2);
    _pose(0, 0, 0, 0, 1, _V(0, 0, -back), _spin);
    _pose(1, 0, 0, sa, ca, const _V(0, 0, 0), _spin);
    _pose(2, 0, -sa, 0, ca, _V(0, 0, back), _spin);

    // The camera.
    final width = size.width;
    final height = size.height;
    final aspect = width / height;
    final tanHalf = math.tan(_fov / 2) * math.max(1.0, 1 / aspect);
    final fill = 0.25 + _clamp(w.size, 0, 10) / 10 * 0.7;
    final k = _figureRadius / (fill * tanHalf);
    final dist = math.sqrt(k * k + _figureRadius * _figureRadius);
    final pitch = _clamp(w.tilt, -85, 85) * _deg;
    final roll = _clamp(w.sideTilt, -180, 180) * _deg;
    _V toScene(_V v) => _rotY(_rotX(_rotZ(v, -roll), -pitch), _yaw);
    final right = toScene(const _V(1, 0, 0));
    final up = toScene(const _V(0, 1, 0));
    final fwd = toScene(const _V(0, 0, -1));
    final cp = math.cos(pitch);
    final cam = _V(
      math.sin(_yaw) * cp * dist,
      math.sin(pitch) * dist,
      math.cos(_yaw) * cp * dist,
    );
    final cx = width / 2 + _clamp(w.offsetX, -50, 50) / 100 * width;
    final cy = height / 2 + _clamp(w.offsetY, -50, 50) / 100 * height;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (w.background != null) {
      _bg.color = w.background!;
      canvas.drawRect(Offset.zero & size, _bg);
    }

    final shader = _shader;
    if (shader != null) {
      // Only the part of the screen the figure can reach.
      final rpx = _reach * 1.08 * (height / 2) /
              (tanHalf * math.max(dist - _reach, 0.6)) +
          3;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: rpx)
          .intersect(Offset.zero & size);
      if (!rect.isEmpty) {
        var i = 0;
        void f(double v) {
          shader.setFloat(i, v);
          i++;
        }

        f(cx);
        f(cy);
        f(tanHalf / (height / 2));
        f(right.x);
        f(right.y);
        f(right.z);
        f(up.x);
        f(up.y);
        f(up.z);
        f(fwd.x);
        f(fwd.y);
        f(fwd.z);
        f(cam.x);
        f(cam.y);
        f(cam.z);
        f(_lin(w.color.r));
        f(_lin(w.color.g));
        f(_lin(w.color.b));
        f(_clamp(w.roughness, 0, 100) / 100);
        f(_clamp(w.reflect, 0, 100) / 100);
        f(w.finish == CrossfoldFinish.metallic ? 1 : 0);
        f(_tier(w.quality) == 2 ? 2 : 1);
        for (var q = 0; q < _planes.length; q++) {
          f(_planes[q]);
        }
        _paint.shader = shader;
        canvas.drawRect(rect, _paint);
      }
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget;
    return IgnorePointer(
      child: RepaintBoundary(
        child: EffectHost(
          onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
          paused: w.paused,
          interactive: false,
          rotatesOnDrag: false,
          quality: w.quality,
          controller: w.controller,
          background: null,
          semanticLabel: w.semanticLabel,
        ),
      ),
    );
  }
}