import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../api/effect_quality.dart';
import '../../api/pisces_controller.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';
import 'pisces_fins.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/pisces.frag';

/// Which fish swims.
enum PiscesVariant {
  /// An orange oranda with a deeper orange hood.
  oranda,

  /// A pale pearl oranda with a red cap.
  redCap,
}

/// How the fish comes and goes.
enum PiscesMode {
  /// An aquarium: the fish swims around, rests and wanders off by itself.
  idle,

  /// There is no fish until something sends one (see [Pisces.active],
  /// [Pisces.every] and [PiscesController.swim]): it crosses and leaves.
  visit,
}

/// What a tap on the fish does.
enum PiscesTap {
  /// The fish croaks, turns belly up, floats up and fades out.
  croak,

  /// Taps do nothing.
  none,
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

PiscesSide _opposite(PiscesSide s) => switch (s) {
      PiscesSide.top => PiscesSide.bottom,
      PiscesSide.bottom => PiscesSide.top,
      PiscesSide.left => PiscesSide.right,
      PiscesSide.right => PiscesSide.left,
    };

/// A goldfish that swims around on its own and follows a finger or cursor.
///
/// It comes as two fish, picked with [variant]. It fills the space its parent
/// gives it, and it swims within that space. Tapping the fish catches it.
class Pisces extends StatefulWidget {
  /// Creates a fish.
  const Pisces({
    super.key,
    this.variant = PiscesVariant.oranda,
    this.mode = PiscesMode.idle,
    this.active = false,
    this.every,
    this.enterFrom,
    this.exitTo,
    this.tapAction = PiscesTap.croak,
    this.respawnDelay = const Duration(seconds: 8),
    this.revisitDelay = const Duration(seconds: 3),
    this.restAfter = const Duration(seconds: 40),
    this.wanderOff = true,
    this.onCaught,
    this.onVisitEnd,
    this.size = 1.0,
    this.bodyDepth = 1.1,
    this.bubbles = true,
    this.tailLength = 1.0,
    this.finSway = 1.7,
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

  /// How the fish comes and goes.
  final PiscesMode mode;

  /// In [PiscesMode.visit]: while true, the fish keeps crossing, a new visit
  /// [revisitDelay] after each exit. Set it to false when the task is done.
  final bool active;

  /// In [PiscesMode.visit]: send a visit this often. Null for none.
  final Duration? every;

  /// The side a visit comes in from. Null picks one at random.
  final PiscesSide? enterFrom;

  /// The side a visit leaves by. Null is the side opposite the entry.
  final PiscesSide? exitTo;

  /// What a tap on the fish does.
  final PiscesTap tapAction;

  /// How long after being caught an idle fish swims back in.
  final Duration respawnDelay;

  /// In [PiscesMode.visit]: the wait between visits, and after a catch.
  final Duration revisitDelay;

  /// In [PiscesMode.idle]: how long left alone before it goes to rest at the
  /// bottom. Zero means it never rests.
  final Duration restAfter;

  /// In [PiscesMode.idle]: whether it now and then swims off the screen and
  /// comes back.
  final bool wanderOff;

  /// Called when the fish is caught by a tap or by [PiscesController.kill].
  final VoidCallback? onCaught;

  /// Called when a visit ends: the fish has left the screen.
  final VoidCallback? onVisitEnd;

  /// Size of the fish. 1.0 is the default.
  final double size;

  /// How deep and round the body is. 1.0 is slim, 1.1 plump.
  final double bodyDepth;

  /// How long the tail is. 1.0 is the default.
  final double tailLength;

  /// How much the fins ripple and sway. 0 holds them still.
  final double finSway;

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

  /// Optional control: pausing, resetting, sending the fish across, catching
  /// it and sending it to rest.
  final PiscesController? controller;

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

/// What the fish is doing.
enum _Phase { swimming, resting, crossing, dying, absent }

/// What kind of crossing it is on.
enum _Path { pass, enter, leave }

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

  // What it is doing, and when things happen next.
  _Phase _phase = _Phase.swimming;
  _Path _path = _Path.pass;
  final List<Offset> _way = <Offset>[];
  int _wayIdx = 0;
  double _alpha = 1;
  double _dieT = 0;
  double _appearAt = 0;
  double _nextVisit = 1e9;
  double _everyAt = 1e9;
  double _lastActive = 0;
  double _restUntil = 0;
  double _nextLeave = 60;
  bool _visitPending = false;
  PiscesSide? _reqFrom;
  PiscesSide? _reqTo;
  int _seenSwim = 0, _seenKill = 0, _seenRest = 0, _seenReset = 0;

  // The frame the fish swims in, and where it was drawn (for taps).
  double _k = 100, _hw = 100, _hh = 100, _rx = 0, _ry = 0;
  double _hitCx = 0, _hitCy = 0;

  // Breathing: now and then the mouth opens and a few bubbles come out.
  final List<_Bubble> _bubbles = <_Bubble>[];
  final List<double> _emitAt = <double>[];
  final List<double> _emitR = <double>[];
  double _nextGulp = 4;
  double _gulpStart = -10;

  // The fins, and the water they feel (body lengths per second, in the
  // fish's own frame: quick at the root, slow at the tips).
  final PiscesFins _fins = PiscesFins();
  final PiscesPose _pose = PiscesPose();
  double _dbx = 0, _dby = 0, _dbz = 0, _dtx = 0, _dty = 0, _dtz = 0;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _fins.load().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object error) {
      debugPrint('Pisces: could not bake its fins: $error');
    });
    widget.controller?.addListener(_onController);
    _syncSeen();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void didUpdateWidget(Pisces oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
      _syncSeen();
    }
    if (oldWidget.mode != widget.mode) _inited = false;
    if (widget.active && !oldWidget.active) {
      _appearAt = math.min(_appearAt, _clock + 0.2);
      _nextVisit = math.min(_nextVisit, _clock + 0.2);
    }
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
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    widget.controller?.removeListener(_onController);
    _shader?.dispose();
    _fins.dispose();
    super.dispose();
  }

  List<Color> _palette() => widget.variant == PiscesVariant.redCap
      ? _redCapColors
      : _orandaColors;

  // ------------------------------------------------------------ controls

  void _syncSeen() {
    final c = widget.controller;
    if (c == null) return;
    _seenSwim = c.swimCount;
    _seenKill = c.killCount;
    _seenRest = c.restCount;
    _seenReset = c.resetCount;
  }

  void _onController() {
    final c = widget.controller;
    if (c == null) return;
    if (c.swimCount != _seenSwim) {
      _seenSwim = c.swimCount;
      _requestSwim(c.swimFrom, c.swimTo);
    }
    if (c.killCount != _seenKill) {
      _seenKill = c.killCount;
      _kill();
    }
    if (c.restCount != _seenRest) {
      _seenRest = c.restCount;
      if (widget.mode == PiscesMode.idle && _phase == _Phase.swimming) {
        _startRest();
      }
    }
    if (c.resetCount != _seenReset) {
      _seenReset = c.resetCount;
      _inited = false;
    }
  }

  void _requestSwim(PiscesSide? from, PiscesSide? to) {
    if (widget.mode == PiscesMode.idle) {
      if (_phase == _Phase.swimming || _phase == _Phase.resting) {
        _startLeave(to);
      }
      return;
    }
    _visitPending = true;
    _reqFrom = from;
    _reqTo = to;
    if (_phase == _Phase.absent) _appearAt = math.min(_appearAt, _clock);
  }

  /// A tap anywhere on the fish catches it. The route is global, so taps
  /// still reach widgets beneath.
  void _onPointer(PointerEvent e) {
    if (e is! PointerDownEvent || !mounted) return;
    if (widget.tapAction == PiscesTap.none || !widget.interactive) return;
    if (_phase == _Phase.dying || _phase == _Phase.absent) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(e.position);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > box.size.width ||
        local.dy > box.size.height) {
      return;
    }
    if (_hitsFish(local)) _kill();
  }

  /// Whether a point (in the widget's own space) is on the body or the tail,
  /// with a fingertip of slack.
  bool _hitsFish(Offset local) {
    final k = _hitK;
    final px = (local.dx - _hitCx) / k;
    final py = (_hitCy - local.dy) / k;
    var ax = _f[0];
    var ay = _f[1];
    final al = math.sqrt(ax * ax + ay * ay);
    if (al < 0.05) {
      ax = 1;
      ay = 0;
    } else {
      ax /= al;
      ay /= al;
    }
    final a = px * ax + py * ay;
    final b = -px * ay + py * ax;
    final slack = 22 / k;
    bool inside(double c, double ra, double rb) {
      final da = (a - c) / (ra + slack);
      final db = b / (rb + slack);
      return da * da + db * db <= 1;
    }

    final depth = widget.bodyDepth.clamp(0.6, 1.6).toDouble();
    return inside(0.0, 0.55, 0.36 * depth) || inside(-0.85, 0.5, 0.35);
  }

  double get _hitK => _k;

  void _kill() {
    if (_phase == _Phase.dying || _phase == _Phase.absent) return;
    _phase = _Phase.dying;
    _dieT = 0;
    widget.onCaught?.call();
  }

  // ------------------------------------------------------------ the brain

  /// Once a frame: decides what the fish does next.
  void _director(Offset? chase) {
    final idle = widget.mode == PiscesMode.idle;
    final every = widget.every;
    if (!idle && every != null && every > Duration.zero && _clock >= _everyAt) {
      _everyAt = _clock + every.inMilliseconds / 1000.0;
      _visitPending = true;
    }
    switch (_phase) {
      case _Phase.absent:
        if (_clock < _appearAt) break;
        if (idle) {
          _spawn(_Path.enter, null, null);
        } else if (_visitPending ||
            (widget.active && _clock >= _nextVisit)) {
          final from = _reqFrom ?? widget.enterFrom;
          final to = _reqTo ?? widget.exitTo;
          _visitPending = false;
          _reqFrom = null;
          _reqTo = null;
          _spawn(_Path.pass, from, to);
        }
      case _Phase.swimming:
        if (!idle) break;
        if (chase != null) _lastActive = _clock;
        final restSec = widget.restAfter.inMilliseconds / 1000.0;
        if (restSec > 0 && chase == null && _clock - _lastActive > restSec) {
          _startRest();
        } else if (widget.wanderOff && chase == null && _clock >= _nextLeave) {
          _startLeave(null);
        }
      case _Phase.resting:
        if (chase != null || _clock >= _restUntil) {
          _phase = _Phase.swimming;
          _wanderUntil = _clock;
          _lastActive = _clock;
        }
      case _Phase.crossing:
        _advanceCrossing();
      case _Phase.dying:
        break;
    }
  }

  void _startRest() {
    _phase = _Phase.resting;
    _wx = (_rnd.nextDouble() * 2 - 1) * _rx * 0.8;
    _wy = -math.max(0.0, _hh - 0.55 * _k);
    _restUntil = _clock + 15 + _rnd.nextDouble() * 15;
  }

  Offset _edgePoint(PiscesSide side, double frac, double margin) {
    final t = frac * 2 - 1;
    return switch (side) {
      PiscesSide.top => Offset(t * _hw, _hh + margin),
      PiscesSide.bottom => Offset(t * _hw, -_hh - margin),
      PiscesSide.left => Offset(-_hw - margin, t * _hh),
      PiscesSide.right => Offset(_hw + margin, t * _hh),
    };
  }

  Offset _clampIn(Offset o) {
    final mx = math.max(0.0, _hw - 0.6 * _k);
    final my = math.max(0.0, _hh - 0.4 * _k);
    return Offset(_clamp(o.dx, -mx, mx), _clamp(o.dy, -my, my));
  }

  double get _exitMargin =>
      (1.0 + widget.tailLength.clamp(0.4, 1.8).toDouble()) * _k;

  /// Swims off a side of the space; it comes back later.
  void _startLeave(PiscesSide? to) {
    final side = to ?? (_facing > 0 ? PiscesSide.right : PiscesSide.left);
    _way
      ..clear()
      ..add(_edgePoint(side, 0.25 + _rnd.nextDouble() * 0.5, _exitMargin));
    _wayIdx = 0;
    _path = _Path.leave;
    _phase = _Phase.crossing;
  }

  /// Puts the fish just outside the space and sends it in.
  void _spawn(_Path path, PiscesSide? from, PiscesSide? to) {
    final k = _k;
    final fromSide = from ?? PiscesSide.values[_rnd.nextInt(4)];
    final toSide = to ?? _opposite(fromSide);
    final e = _edgePoint(fromSide, 0.25 + _rnd.nextDouble() * 0.5, 0.6 * k);
    _way
      ..clear()
      ..add(e);
    if (path == _Path.pass) {
      final x =
          _edgePoint(toSide, 0.25 + _rnd.nextDouble() * 0.5, _exitMargin);
      final d = x - e;
      final len = d.distance;
      final perp =
          len > 1e-6 ? Offset(-d.dy / len, d.dx / len) : const Offset(0, 1);
      final span = math.min(_hw, _hh) * 2;
      final sign = _rnd.nextBool() ? 1.0 : -1.0;
      final o1 = sign * (0.08 + _rnd.nextDouble() * 0.12) * span;
      final o2 = -sign * (0.08 + _rnd.nextDouble() * 0.12) * span;
      _way
        ..add(_clampIn(e + d * 0.36 + perp * o1))
        ..add(_clampIn(e + d * 0.68 + perp * o2))
        ..add(x);
    } else {
      _way.add(Offset(
        (_rnd.nextDouble() * 2 - 1) * _rx,
        (_rnd.nextDouble() * 2 - 1) * _ry,
      ));
    }
    _path = path;
    _wayIdx = 1;

    // Facing the way it is about to swim, already moving.
    _x = e.dx;
    _y = e.dy;
    final toward = _way[1] - e;
    final dist = math.max(toward.distance, 1e-6);
    if (toward.dx.abs() > 0.2 * dist) _facing = toward.dx > 0 ? 1 : -1;
    _yaw = _facing > 0 ? _yawBias : math.pi - _yawBias;
    _pitch =
        _clamp(math.atan2(toward.dy, toward.dx.abs() + 0.6 * k), -1.45, 1.45);
    _yawV = 0;
    _pitchV = 0;
    _roll = 0;
    _bend = 0;
    _beatAmp = 0.5;
    final v0 = 0.4 * k;
    _vx = toward.dx / dist * v0;
    _vy = toward.dy / dist * v0;
    _alpha = 1;
    _phase = _Phase.crossing;
    _basis();
  }

  /// Moves on to the next waypoint, and ends the crossing at the last one.
  void _advanceCrossing() {
    final wp = _way[_wayIdx];
    final last = _wayIdx == _way.length - 1;
    if (!last) {
      final hx = _x + _f[0] * 0.5 * _k;
      final hy = _y + _f[1] * 0.5 * _k;
      if ((Offset(hx, hy) - wp).distance < 0.9 * _k) _wayIdx++;
      return;
    }
    switch (_path) {
      case _Path.enter:
        final hx = _x + _f[0] * 0.5 * _k;
        final hy = _y + _f[1] * 0.5 * _k;
        if ((Offset(hx, hy) - wp).distance > 0.4 * _k) return;
        _phase = _Phase.swimming;
        _wanderUntil = _clock;
        _lastActive = _clock;
        _nextLeave = _clock + 50 + _rnd.nextDouble() * 70;
      case _Path.pass:
        if ((Offset(_x, _y) - wp).distance > 0.3 * _k) return;
        _phase = _Phase.absent;
        _alpha = 0;
        final wait = _visitPending ? 0.4 : widget.revisitDelay.inMilliseconds / 1000.0;
        _appearAt = _clock + wait;
        _nextVisit = _clock + widget.revisitDelay.inMilliseconds / 1000.0;
        widget.onVisitEnd?.call();
      case _Path.leave:
        if ((Offset(_x, _y) - wp).distance > 0.3 * _k) return;
        _phase = _Phase.absent;
        _alpha = 0;
        _appearAt = _clock + 3 + _rnd.nextDouble() * 4;
    }
  }

  void _finishDeath() {
    _phase = _Phase.absent;
    _alpha = 0;
    final delay = widget.mode == PiscesMode.idle
        ? widget.respawnDelay
        : widget.revisitDelay;
    _appearAt = _clock + delay.inMilliseconds / 1000.0;
    _nextVisit = _appearAt;
  }

  // ------------------------------------------------------------ motion

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
    final eager = widget.eagerness.clamp(0.0, 4.0).toDouble();
    final pace = widget.swimSpeed.clamp(0.0, 4.0).toDouble();
    double tx, ty, vmax, wTurn, tauV;
    var pitchMax = 0.55;
    var wandering = false;
    if (_phase == _Phase.crossing) {
      // On its way across: it ignores fingers until it has gone.
      final wp = _way[_wayIdx];
      tx = wp.dx;
      ty = wp.dy;
      vmax = 0.9 * math.max(0.3, pace) * k;
      wTurn = 1.8;
      tauV = 0.45;
      pitchMax = 1.45;
    } else if (_phase == _Phase.resting) {
      tx = _wx;
      ty = _wy;
      vmax = 0.25 * k;
      wTurn = 1.0;
      tauV = 0.8;
    } else if (chase != null) {
      tx = chase.dx;
      ty = chase.dy;
      vmax = (1.0 + 1.6 * eager) * k;
      wTurn = 2.4 + 1.2 * eager;
      tauV = 0.28;
    } else {
      wandering = true;
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
    if (wandering && dist < 0.25 * k) {
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
        _clamp(math.atan2(oy, ox.abs() + 0.6 * k), -pitchMax, pitchMax) * near;

    // Critically damped turns.
    const z = 0.9;
    _yawV += (wTurn * wTurn * (yawT - _yaw) - 2 * z * wTurn * _yawV) * dt;
    _yaw += _yawV * dt;
    final wp2 = wTurn * 1.2;
    _pitchV += (wp2 * wp2 * (pitchT - _pitch) - 2 * z * wp2 * _pitchV) * dt;
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

    _updateDrag(dt, k);
  }

  /// A caught fish: it croaks, turns belly up, floats up and fades.
  void _stepDying(double dt, double k) {
    _dieT += dt;
    _roll += (math.pi - _roll) * (1 - math.exp(-dt / 0.3));
    _pitch += (0.12 - _pitch) * (1 - math.exp(-dt / 0.6));
    final yawT = _facing > 0 ? _yawBias : math.pi - _yawBias;
    _yawV = 0;
    _yaw += (yawT - _yaw) * (1 - math.exp(-dt / 0.6));
    // the tail goes limp and the body curls a little
    _beatAmp += (0.05 - _beatAmp) * (1 - math.exp(-dt / 0.4));
    _beatHz += (0.15 - _beatHz) * (1 - math.exp(-dt / 0.4));
    _beat = (_beat + 2 * math.pi * _beatHz * dt) % (math.pi * 2);
    _bend += ((_facing > 0 ? 0.2 : -0.2) - _bend) *
        (1 - math.exp(-dt / 0.5));
    // it stops, then drifts slowly upward
    final rise = k * (0.10 + 0.12 * _smooth(0.6, 3.0, _dieT));
    final kv = 1 - math.exp(-dt / 0.7);
    _vx += (0 - _vx) * kv;
    _vy += (rise - _vy) * kv;
    _x += (_vx + 0.02 * k * math.sin(_dieT * 1.7)) * dt;
    _y += _vy * dt;
    _alpha = 1 - _smooth(1.0, 4.0, _dieT);
    _basis();
    _updateDrag(dt, k);
    if (_dieT > 4.2 || _y > _hh + 2 * k) _finishDeath();
  }

  /// The water the fins feel: the opposite of the swim, plus the sideways
  /// sweep of a turn.
  void _updateDrag(double dt, double k) {
    final lx = -(_vx * _f[0] + _vy * _f[1]) / k;
    final ly = -(_vx * _u[0] + _vy * _u[1]) / k;
    final lz = -(_vx * _s[0] + _vy * _s[1]) / k + _yawV * 0.7;
    final kb = 1 - math.exp(-dt / 0.12);
    final kt = 1 - math.exp(-dt / 0.45);
    _dbx += (lx - _dbx) * kb;
    _dby += (ly - _dby) * kb;
    _dbz += (lz - _dbz) * kb;
    _dtx += (lx - _dtx) * kt;
    _dty += (ly - _dty) * kt;
    _dtz += (lz - _dtz) * kt;
  }

  // ------------------------------------------------------------ bubbles

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
    if (_phase == _Phase.absent || _phase == _Phase.dying) {
      _nextGulp = math.max(_nextGulp, _clock + 1.5);
    } else if (_clock >= _nextGulp) {
      // A gulp at a random moment: the mouth opens, then bubbles come out.
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
        if (_phase != _Phase.absent) _emitBubble(k, _emitR[i]);
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

  // ------------------------------------------------------------ painting

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;
    final k = math.max(8.0, 0.27 * widget.size * size.shortestSide);
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final roam = widget.roam.clamp(0.0, 1.0).toDouble();
    final rx = math.max(0.0, halfW - 1.1 * k) * roam;
    final ry = math.max(0.0, halfH - 0.4 * k) * roam;
    _k = k;
    _hw = halfW;
    _hh = halfH;
    _rx = rx;
    _ry = ry;

    if (!_inited) {
      _inited = true;
      _bubbles.clear();
      _emitAt.clear();
      _emitR.clear();
      _alpha = 1;
      _roll = 0;
      _bend = 0;
      _dieT = 0;
      _visitPending = false;
      _lastActive = _clock;
      _nextLeave = _clock + 50 + _rnd.nextDouble() * 70;
      final every = widget.every;
      _everyAt = every != null && every > Duration.zero
          ? _clock + every.inMilliseconds / 1000.0
          : 1e9;
      _facing = _rnd.nextBool() ? 1 : -1;
      _yaw = _facing > 0 ? _yawBias : math.pi - _yawBias;
      _pitch = 0;
      if (widget.mode == PiscesMode.idle) {
        _phase = _Phase.swimming;
        _x = (_rnd.nextDouble() * 2 - 1) * rx * 0.5;
        _y = (_rnd.nextDouble() * 2 - 1) * ry * 0.5;
        _wanderUntil = 0;
      } else {
        _phase = _Phase.absent;
        _alpha = 0;
        _appearAt = _clock + 0.3;
        _nextVisit = widget.active ? _clock + 0.3 : 1e9;
      }
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

    _director(chase);

    if (dt > 0) {
      final n = (dt / 0.016).ceil();
      final h = dt / n;
      for (var i = 0; i < n; i++) {
        _clock += h;
        if (_phase == _Phase.dying) {
          _stepDying(h, k);
        } else if (_phase != _Phase.absent) {
          _step(h, k, rx, ry, _phase == _Phase.swimming ? chase : null);
        }
      }
    }
    _basis();

    _updateBubbles(dt, k, halfH);

    final shader = _shader;
    if (shader == null) return;

    // A fish that is away shows nothing but its last bubbles.
    if (_phase == _Phase.absent || _alpha <= 0.004) {
      if (widget.bubbles) _drawBubbles(canvas, halfW, halfH);
      return;
    }

    final gp = (_clock - _gulpStart) / 0.7;
    var gulp = gp > 0 && gp < 1
        ? math.pow(math.sin(math.pi * gp), 2).toDouble()
        : 0.0;
    if (_phase == _Phase.dying) gulp = 0.85;
    final belly = widget.variant == PiscesVariant.redCap
        ? _redCapBelly
        : _orandaBelly;

    final bobPx = 0.012 * k * math.sin(frame.time * 0.8);
    final cx = halfW + _x;
    final cy = halfH - _y - bobPx;
    _hitCx = cx;
    _hitCy = cy;
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
      ..setFloat(26, _alpha)
      ..setFloat(27, steps)
      ..setFloat(28, _lin(belly.r))
      ..setFloat(29, _lin(belly.g))
      ..setFloat(30, _lin(belly.b));

    final pose = _pose;
    pose.k = k;
    pose.cx = cx;
    pose.cy = cy;
    for (var i = 0; i < 3; i++) {
      pose.fwd[i] = _f[i];
      pose.up[i] = _u[i];
      pose.side[i] = _s[i];
    }
    pose.beat = _beat;
    pose.beatAmp = _beatAmp;
    pose.bend = _bend;
    pose.time = frame.time % (200 * math.pi);
    pose.dragBase[0] = _dbx;
    pose.dragBase[1] = _dby;
    pose.dragBase[2] = _dbz;
    pose.dragTip[0] = _dtx;
    pose.dragTip[1] = _dty;
    pose.dragTip[2] = _dtz;
    pose.speedBl = math.sqrt(_vx * _vx + _vy * _vy) / k;
    pose.depth = widget.bodyDepth.clamp(0.6, 1.6).toDouble();
    pose.tailScale = widget.tailLength.clamp(0.4, 1.8).toDouble();
    pose.sway = widget.finSway.clamp(0.0, 3.0).toDouble();
    pose.alpha = _alpha;
    pose.quality = frame.quality;
    final fc = pal[2];
    pose.capLin[0] = _lin(cap.r);
    pose.capLin[1] = _lin(cap.g);
    pose.capLin[2] = _lin(cap.b);
    pose.finLin[0] = _lin(fc.r);
    pose.finLin[1] = _lin(fc.g);
    pose.finLin[2] = _lin(fc.b);

    // Fins behind the body, then the body, then the fins in front of it.
    _fins.draw(canvas, pose, near: false);
    final paint = _paint ??= (Paint()..shader = shader);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 1.5 * k, height: 1.5 * k),
      paint,
    );
    _fins.draw(canvas, pose, near: true);
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