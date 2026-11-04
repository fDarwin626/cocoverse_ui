import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/pisces.frag';

/// Which fish swims.
enum PiscesVariant {
  /// An orange oranda with a deeper orange hood.
  oranda,

  /// A pale pearl oranda with a red cap.
  redCap,
}

// Hood, body and fin colours of each fish.
const List<Color> _orandaColors = [
  Color(0xFFFF8A1A),
  Color(0xFFF0A820),
  Color(0xFFF0A050),
];
const List<Color> _redCapColors = [
  Color(0xFFD8371A),
  Color(0xFFF2DFC8),
  Color(0xFFF0D2B4),
];

// Belly colours: pale gold on the oranda, a blush of red on the pearl fish.
const Color _orandaBelly = Color(0xFFFFE9A8);
const Color _redCapBelly = Color(0xFFF0C4BC);

const double _yawBias = 0.22;

double _clamp(double v, double lo, double hi) =>
    math.min(hi, math.max(lo, v));

double _smooth(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

double _lin(double c) => math.pow(c, 2.2).toDouble();

/// A goldfish that swims around on its own and follows a finger or cursor.
///
/// It comes as two fish, picked with [variant]. It fills the space its parent
/// gives it, and it swims within that space.
class Pisces extends StatefulWidget {
  /// Creates a fish.
  const Pisces({
    super.key,
    this.variant = PiscesVariant.oranda,
    this.size = 1.0,
    this.bodyDepth = 1.1,
    this.bubbles = true,
    this.swimSpeed = 1.0,
    this.roam = 0.8,
    this.follow = true,
    this.eagerness = 1.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Which fish swims.
  final PiscesVariant variant;

  /// Size of the fish. 1.0 is the default.
  final double size;

  /// How deep and round the body is. 1.0 is slim, 1.1 plump.
  final double bodyDepth;

  /// Whether it lets out a few bubbles from its mouth now and then.
  final bool bubbles;

  /// How fast it cruises when left alone. 0 hangs it where it is.
  final double swimSpeed;

  /// How much of its space it wanders over, from 0 to 1.
  final double roam;

  /// Whether it swims toward a finger or cursor over it.
  final bool follow;

  /// How keenly it chases a finger or cursor.
  final double eagerness;

  /// Fill behind the fish. Null means transparent.
  final Color? background;

  /// Animation speed multiplier.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and hover affect the fish.
  final bool interactive;

  /// Level of detail. Low marches fewer steps per pixel.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the fish as decorative.
  final String? semanticLabel;

  @override
  State<Pisces> createState() => _PiscesState();
}

class _Bubble {
  _Bubble(this.x, this.y, this.r, this.vx, this.seed);

  double x; // px from the middle, y pointing up
  double y;
  final double r; // radius, px
  double vx;
  final double seed;
  double age = 0;
}

class _PiscesState extends State<Pisces> {
  final math.Random _rnd = math.Random(20261103);

  ui.FragmentShader? _shader;
  Paint? _paint;

  // The fish's state. x and y are pixels from the middle, y pointing up.
  bool _inited = false;
  double _lastTime = -1;
  double _clock = 0;
  double _x = 0, _y = 0, _vx = 0, _vy = 0;
  double _yaw = _yawBias, _yawV = 0, _pitch = 0, _pitchV = 0, _roll = 0;
  int _facing = 1;
  double _beat = 0, _beatHz = 0.7, _beatAmp = 0.3, _bend = 0;
  double _wx = 0, _wy = 0, _wanderUntil = 0, _pauseUntil = 0;
  bool _arrived = false;
  bool _wasChasing = false;
  final Float64List _f = Float64List(3);
  final Float64List _u = Float64List(3);
  final Float64List _s = Float64List(3);

  // Breathing: now and then the mouth opens and a few bubbles come out.
  final List<_Bubble> _bubbles = <_Bubble>[];
  final List<double> _emitAt = <double>[];
  final List<double> _emitR = <double>[];
  double _nextGulp = 4;
  double _gulpStart = -10;

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
      debugPrint('Pisces: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  List<Color> _palette() => widget.variant == PiscesVariant.redCap
      ? _redCapColors
      : _orandaColors;

  void _basis() {
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final cyw = math.cos(_yaw), syw = math.sin(_yaw);
    _f[0] = cp * cyw;
    _f[1] = sp;
    _f[2] = cp * syw;
    final ux = -sp * cyw, uy = cp, uz = -sp * syw;
    // side = forward x up
    final sx = _f[1] * uz - _f[2] * uy;
    final sy = _f[2] * ux - _f[0] * uz;
    final sz = _f[0] * uy - _f[1] * ux;
    final cr = math.cos(_roll), sr = math.sin(_roll);
    _u[0] = ux * cr + sx * sr;
    _u[1] = uy * cr + sy * sr;
    _u[2] = uz * cr + sz * sr;
    _s[0] = sx * cr - ux * sr;
    _s[1] = sy * cr - uy * sr;
    _s[2] = sz * cr - uz * sr;
  }

  void _pickWander(double rx, double ry, double k) {
    var bx = 0.0, by = 0.0, best = -1.0;
    for (var i = 0; i < 4; i++) {
      final cx = (_rnd.nextDouble() * 2 - 1) * rx;
      final cy = (_rnd.nextDouble() * 2 - 1) * ry;
      final dx = (cx - _x).abs();
      final dy = (cy - _y).abs();
      // A fish turns round only for a target clearly to one side of it.
      final d = math.sqrt(dx * dx + dy * dy) * (dx > 1.4 * dy + 0.7 * k ? 1 : 0.1);
      if (d > best) {
        best = d;
        bx = cx;
        by = cy;
      }
    }
    _wx = bx;
    _wy = by;
    final pace = widget.swimSpeed.clamp(0.05, 4.0).toDouble();
    final v = 0.4 * pace * k;
    final dist = math.sqrt((bx - _x) * (bx - _x) + (by - _y) * (by - _y));
    _wanderUntil = _clock + 4 + _rnd.nextDouble() * 4 + 1.4 * dist / v;
    _arrived = false;
  }

  void _step(double dt, double k, double rx, double ry, Offset? chase) {
    _clock += dt;
    final eager = widget.eagerness.clamp(0.0, 4.0).toDouble();
    final pace = widget.swimSpeed.clamp(0.0, 4.0).toDouble();
    final chasing = chase != null;
    double tx, ty, vmax, wTurn, tauV;
    if (chase != null) {
      tx = chase.dx;
      ty = chase.dy;
      vmax = (1.0 + 1.6 * eager) * k;
      wTurn = 2.4 + 1.2 * eager;
      tauV = 0.28;
    } else {
      if (_clock > _wanderUntil) _pickWander(rx, ry, k);
      tx = _wx;
      ty = _wy;
      vmax = 0.4 * pace * k;
      wTurn = 1.4;
      tauV = 0.55;
    }

    // Steer the snout, not the middle, onto the target.
    final hx = _x + _f[0] * 0.5 * k;
    final hy = _y + _f[1] * 0.5 * k;
    final ox = tx - hx;
    final oy = ty - hy;
    final dist = math.sqrt(ox * ox + oy * oy);
    if (!chasing && dist < 0.25 * k) {
      if (!_arrived) {
        _arrived = true;
        _pauseUntil = _clock + 1 + _rnd.nextDouble() * 2;
      } else if (_clock > _pauseUntil) {
        _wanderUntil = _clock;
      }
    }

    final cxo = tx - _x;
    final hyst = 0.6 * k;
    if (cxo > hyst && _facing < 0) {
      _facing = 1;
    } else if (cxo < -hyst && _facing > 0) {
      _facing = -1;
    }
    final yawT = _facing > 0 ? _yawBias : math.pi - _yawBias;
    final near = _smooth(0, 0.6 * k, dist);
    final pitchT =
        _clamp(math.atan2(oy, ox.abs() + 0.6 * k), -0.55, 0.55) * near;

    // Critically damped turns.
    const z = 0.9;
    _yawV += (wTurn * wTurn * (yawT - _yaw) - 2 * z * wTurn * _yawV) * dt;
    _yaw += _yawV * dt;
    final wp = wTurn * 1.2;
    _pitchV += (wp * wp * (pitchT - _pitch) - 2 * z * wp * _pitchV) * dt;
    _pitch += _pitchV * dt;
    _roll += (_clamp(_yawV * 0.12, -0.3, 0.3) - _roll) *
        (1 - math.exp(-dt / 0.35));
    _basis();

    // Thrust along the heading only once it points the right way.
    final align = math.max(0.0, math.cos(_yaw - yawT));
    final ahead =
        dist > 1e-6 ? _clamp((_f[0] * ox + _f[1] * oy) / dist, 0, 1) : 0.0;
    final vstar =
        vmax * _smooth(0.02 * k, 1.1 * k, dist) * align * align * ahead;
    var dvx = _f[0] * vstar;
    var dvy = _f[1] * vstar;
    if (dist < 1.2 * k) {
      final sc = math.min(1.0, (0.35 * k) / math.max(dist, 1e-4)) * 1.4;
      dvx += ox * sc;
      dvy += oy * sc;
    }
    final kv = 1 - math.exp(-dt / tauV);
    _vx += (dvx - _vx) * kv;
    _vy += (dvy - _vy) * kv;
    _x += _vx * dt;
    _y += _vy * dt;

    // Tail beat: lazy at rest, quicker and wider when it works.
    final swim = math.sqrt(_vx * _vx + _vy * _vy) / k;
    final work = _clamp(swim / 1.6 + _yawV.abs() * 0.25, 0, 1.4);
    final hzT = 0.7 * (1 + 1.3 * math.min(1.0, work));
    _beatHz += (hzT - _beatHz) *
        (1 - math.exp(-dt / (hzT > _beatHz ? 0.18 : 0.6)));
    _beat = (_beat + 2 * math.pi * _beatHz * dt) % (math.pi * 2);
    final ampT = 0.3 + 0.6 * math.min(1.0, work);
    _beatAmp += (ampT - _beatAmp) *
        (1 - math.exp(-dt / (ampT > _beatAmp ? 0.15 : 0.6)));
    _bend += (_clamp(_yawV * 0.16, -0.4, 0.4) - _bend) *
        (1 - math.exp(-dt / 0.12));
  }


  /// Lets a bubble out at the lips, in the fish's own frame.
  void _emitBubble(double k, double radiusBl) {
    final lat = _beatAmp * (-0.014 * math.sin(_beat + 0.9)) - 0.03 * _bend;
    const lx = 0.505;
    const ly = -0.055;
    final wx = k * (_f[0] * lx + _u[0] * ly + _s[0] * lat);
    final wy = k * (_f[1] * lx + _u[1] * ly + _s[1] * lat);
    _bubbles.add(_Bubble(
      _x + wx,
      _y + wy,
      radiusBl * k,
      _f[0] * 0.3 * k,
      _rnd.nextDouble() * 100,
    ));
  }

  void _updateBubbles(double dt, double k, double halfH) {
    // A gulp at a random moment: the mouth opens, then bubbles come out.
    if (_clock >= _nextGulp) {
      _gulpStart = _clock;
      _nextGulp = _clock + 3 + _rnd.nextDouble() * 7;
      if (widget.bubbles) {
        const radii = [0.026, 0.019, 0.014];
        final count = 2 + _rnd.nextInt(2);
        for (var i = 0; i < count; i++) {
          _emitAt.add(_clock + 0.25 + 0.12 * i);
          _emitR.add(radii[i]);
        }
      }
    }
    for (var i = _emitAt.length - 1; i >= 0; i--) {
      if (_clock >= _emitAt[i]) {
        _emitBubble(k, _emitR[i]);
        _emitAt.removeAt(i);
        _emitR.removeAt(i);
      }
    }
    // Bubbles rise at a speed set by their size, zig-zagging a little.
    for (var i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];
      b.age += dt;
      final vy = (0.6 + 14 * (b.r / k)) * k;
      b.vx *= math.exp(-dt / 0.3);
      b.x += (b.vx + 0.28 * vy * math.sin(b.age * 9 + b.seed)) * dt;
      b.y += vy * dt;
      if (b.y > halfH + b.r * 2 || b.age > 9) _bubbles.removeAt(i);
    }
  }

  void _drawBubbles(Canvas canvas, double midX, double midY) {
    final ring = Paint()..style = PaintingStyle.stroke;
    final fill = Paint();
    for (final b in _bubbles) {
      final a = _clamp(b.age / 0.15, 0, 1) * (1 - _smooth(7, 9, b.age));
      if (a <= 0) continue;
      final c = Offset(midX + b.x, midY - b.y);
      final r = b.r * (1 + 0.03 * b.age);
      fill.color = Color.fromRGBO(190, 225, 255, 0.07 * a);
      canvas.drawCircle(c, r, fill);
      ring.strokeWidth = math.max(1.0, r * 0.14);
      ring.color = Color.fromRGBO(235, 245, 255, 0.55 * a);
      canvas.drawCircle(c, r, ring);
      fill.color = Color.fromRGBO(255, 255, 255, 0.85 * a);
      canvas.drawCircle(
          c + Offset(-0.34 * r, -0.4 * r), math.max(0.8, r * 0.18), fill);
      fill.color = Color.fromRGBO(255, 255, 255, 0.35 * a);
      canvas.drawCircle(
          c + Offset(0.3 * r, 0.38 * r), math.max(0.6, r * 0.1), fill);
    }
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;
    final k = math.max(8.0, 0.27 * widget.size * size.shortestSide);
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final roam = widget.roam.clamp(0.0, 1.0).toDouble();
    final rx = math.max(0.0, halfW - 0.6 * k) * roam;
    final ry = math.max(0.0, halfH - 0.4 * k) * roam;

    if (!_inited) {
      _inited = true;
      _facing = _rnd.nextBool() ? 1 : -1;
      _yaw = _facing > 0 ? _yawBias : math.pi - _yawBias;
      _x = (_rnd.nextDouble() * 2 - 1) * rx * 0.5;
      _y = (_rnd.nextDouble() * 2 - 1) * ry * 0.5;
      _wanderUntil = 0;
      _basis();
    }

    var dt = _lastTime < 0 ? 0.0 : frame.time - _lastTime;
    _lastTime = frame.time;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;

    Offset? chase;
    final pointer = frame.pointer;
    if (widget.follow &&
        widget.interactive &&
        pointer != null &&
        frame.pointerStrength > 0.05) {
      chase = Offset(pointer.dx - halfW, halfH - pointer.dy);
    }
    if (_wasChasing && chase == null) _wanderUntil = _clock;
    _wasChasing = chase != null;

    if (dt > 0) {
      final n = (dt / 0.016).ceil();
      final h = dt / n;
      for (var i = 0; i < n; i++) {
        _step(h, k, rx, ry, chase);
      }
    }
    _basis();

    _updateBubbles(dt, k, halfH);
    final gp = (_clock - _gulpStart) / 0.7;
    final gulp = gp > 0 && gp < 1
        ? math.pow(math.sin(math.pi * gp), 2).toDouble()
        : 0.0;
    final belly = widget.variant == PiscesVariant.redCap
        ? _redCapBelly
        : _orandaBelly;

    final shader = _shader;
    if (shader == null) return;
    
    final bobPx = 0.012 * k * math.sin(frame.time * 0.8);
    final cx = halfW + _x;
    final cy = halfH - _y - bobPx;
    final steps = switch (frame.quality) {
      EffectQuality.low => 40.0,
      EffectQuality.medium => 56.0,
      EffectQuality.high => 72.0,
    };
    final pal = _palette();
    final cap = pal[0];
    final skin = pal[1];

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, cx)
      ..setFloat(3, cy)
      ..setFloat(4, k)
      ..setFloat(5, _f[0])
      ..setFloat(6, _f[1])
      ..setFloat(7, _f[2])
      ..setFloat(8, _u[0])
      ..setFloat(9, _u[1])
      ..setFloat(10, _u[2])
      ..setFloat(11, _s[0])
      ..setFloat(12, _s[1])
      ..setFloat(13, _s[2])
      ..setFloat(14, _beat)
      ..setFloat(15, _beatAmp)
      ..setFloat(16, _bend)
      ..setFloat(17, gulp)
      ..setFloat(18, _lin(cap.r))
      ..setFloat(19, _lin(cap.g))
      ..setFloat(20, _lin(cap.b))
      ..setFloat(21, _lin(skin.r))
      ..setFloat(22, _lin(skin.g))
      ..setFloat(23, _lin(skin.b))
      ..setFloat(24, widget.bodyDepth.clamp(0.6, 1.6).toDouble())
      ..setFloat(25, 1)
      ..setFloat(26, 1)
      ..setFloat(27, steps)
      ..setFloat(28, _lin(belly.r))
      ..setFloat(29, _lin(belly.g))
      ..setFloat(30, _lin(belly.b));

    final paint = _paint ??= (Paint()..shader = shader);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 1.5 * k, height: 1.5 * k),
      paint,
    );
    if (widget.bubbles) _drawBubbles(canvas, halfW, halfH);

  }

  @override
  Widget build(BuildContext context) {
    return EffectHost(
      onPaint: _paintFrame,
      speed: widget.speed,
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