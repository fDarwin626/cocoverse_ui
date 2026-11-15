import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerCancelEvent,
        PointerDownEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent;
import 'package:flutter/widgets.dart';

import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

/// Where the shader is loaded from. Written the same way as the Meteor path.
const String _asset = 'packages/cocoverse_ui/shaders/gaze.frag';

const double _deg = math.pi / 180;

// How fast the eye catches up with where it wants to look, in seconds.
const double _followSec = 0.045;

// About how long it holds an idle glance, in seconds.
const double _saccadeSec = 2.2;

// How much the pupil breathes by itself.
const double _hippus = 0.30;

// The soft grey ring round the iris, and how strong the fibres are.
const double _limbus = 0.75;
const double _fiber = 1.0;

/// What the eye follows by itself.
enum GazeFollow {
  /// Any finger or cursor, anywhere on the screen.
  screen,

  /// Nothing. It only looks where a [GazeController] tells it to, or rests.
  off,
}

/// Tells a [Gaze] where to look, for example at a password field.
///
/// ```dart
/// final eye = GazeController();
/// final field = GlobalKey();
/// // Gaze(controller: eye) ... TextField(key: field)
/// eye.lookAtKey(field); // stares at the field
/// eye.release(); // goes back to following the finger
/// ```
class GazeController extends ChangeNotifier {
  Offset? _point;
  GlobalKey? _key;
  int _startles = 0;

  /// How many times [startle] has been called.
  int get startleCount => _startles;

  /// Whether it is locked onto a point or a widget.
  bool get isLocked => _point != null || _key != null;

  /// Looks at a point, in screen coordinates.
  void lookAt(Offset globalPoint) {
    _point = globalPoint;
    _key = null;
    notifyListeners();
  }

  /// Looks at the middle of the widget that [key] belongs to.
  void lookAtKey(GlobalKey key) {
    _key = key;
    _point = null;
    notifyListeners();
  }

  /// Goes back to following the finger or cursor.
  void release() {
    _point = null;
    _key = null;
    notifyListeners();
  }

  /// Snaps the pupil small for a moment.
  void startle() {
    _startles++;
    notifyListeners();
  }

  /// Where it is told to look, in screen coordinates, or null.
  Offset? get target {
    final p = _point;
    if (p != null) return p;
    final k = _key;
    if (k == null) return null;
    final ro = k.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      return ro.localToGlobal(ro.size.center(Offset.zero));
    }
    return null;
  }
}

/// A wet, glossy eyeball that turns to look at your finger or cursor.
///
/// It follows any pointer anywhere on the screen, glances around by itself
/// when nothing is pointing, and its pupil snaps small when you press. It has
/// no text and no background, so it works over anything. It fills the space it
/// is given, drawn from the shorter side. The eye is drawn by a fragment
/// shader, `gaze.frag`, which has to be listed under `shaders:` in the
/// package's pubspec.
///
/// ```dart
/// const SizedBox(
///   width: 120,
///   height: 120,
///   child: Gaze(irisColor: Color(0xFF2E9E5B)),
/// )
/// ```
class Gaze extends StatefulWidget {
  /// Creates an eye.
  const Gaze({
    super.key,
    this.irisColor = const Color(0xFFFF2400),
    this.scleraColor = const Color(0xFFFFFFFF),
    this.collarColor = const Color(0xFF7A4A22),
    this.pupilSize = 0.0,
    this.size = 8.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.follow = GazeFollow.screen,
    this.reach = 10.0,
    this.dilate = 5.2,
    this.wander = 10.0,
    this.bob = 10.0,
    this.restX = 22.0,
    this.restY = 1.0,
    this.maxTurn = 42.0,
    this.irisAngle = 29.0,
    this.bulge = 12.0,
    this.gloss = 100.0,
    this.redness = 100.0,
    this.veins = 30.0,
    this.lightAngle = 0.0,
    this.speed = 100.0,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// The middle tone of the iris. The fibres and shadows come from it.
  final Color irisColor;

  /// The lit colour of the white of the eye.
  final Color scleraColor;

  /// The ragged ring round the pupil.
  final Color collarColor;

  /// The resting pupil size, from 0 to 10.
  final double pupilSize;

  /// How much of the box the eye fills, from 0 to 10.
  final double size;

  /// Moves it across the box, as a percentage of the width, -50 to 50.
  final double offsetX;

  /// Moves it down the box, as a percentage of the height, -50 to 50.
  final double offsetY;

  /// What it follows by itself.
  final GazeFollow follow;

  /// How hard it turns toward the pointer, from 0 to 10. 0 stops following.
  final double reach;

  /// How much the pupil reacts, from 0 to 10: it widens as the pointer is
  /// near and snaps small on a press.
  final double dilate;

  /// How much it glances about when nothing is pointing, from 0 to 10.
  final double wander;

  /// How far the whole ball bobs, from 0 to 10.
  final double bob;

  /// Where it looks at rest, in degrees. Positive is right.
  final double restX;

  /// Where it looks at rest, in degrees. Positive is up.
  final double restY;

  /// The most it can turn toward the pointer, in degrees.
  final double maxTurn;

  /// How wide the iris is, in degrees as seen from the middle of the eye,
  /// from 10 to 45.
  final double irisAngle;

  /// How far the cornea stands above the ball, as a percentage of its radius.
  final double bulge;

  /// How strong the shiny reflections are, from 0 to 100.
  final double gloss;

  /// How red the shadow side and the rim are, from 0 to 100.
  final double redness;

  /// How strong the veins are, from 0 to 100.
  final double veins;

  /// Turns the studio lights round, in degrees.
  final double lightAngle;

  /// How fast time runs, as a percentage. 100 is normal, 0 freezes it.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Low drops the finest fibres and veins.
  final EffectQuality quality;

  /// Optional control for looking at a point or a widget.
  final GazeController? controller;

  /// Screen-reader description. Null marks it as decorative.
  final String? semanticLabel;

  @override
  State<Gaze> createState() => _GazeState();
}

// ─── Small maths ─────────────────────────────────────────────────────────────

double _clamp(double v, double lo, double hi) {
  final safe = v.isFinite ? v : lo;
  return math.min(hi, math.max(lo, safe));
}

double _gamma(double v) => math.pow(v, 2.2).toDouble();

int _tier(EffectQuality q) => switch (q) {
      EffectQuality.low => 0,
      EffectQuality.medium => 1,
      EffectQuality.high => 2,
    };

// ─── The state ───────────────────────────────────────────────────────────────

Future<ui.FragmentProgram?>? _programFuture;

Future<ui.FragmentProgram?> _loadProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(_asset);
  } catch (e) {
    debugPrint(
      'Gaze: could not load the shader at $_asset ($e). Check the '
      'shaders: list in pubspec.yaml and the path in gaze.dart.',
    );
    return null;
  }
}

class _GazeState extends State<Gaze> {
  final Paint _paint = Paint();
  ui.FragmentShader? _shader;

  bool _reduced = false;
  double _lastTime = 0;
  double _clock = 0;

  // The eye.
  bool _aimed = false;
  double _yaw = 0;
  double _pitch = 0;
  double _pupil = 1;
  double _flash = 0;
  double _scare = 0;
  double _glanceX = 0;
  double _glanceY = 0;
  double _nextGlance = 1.2;
  int _seenStartles = 0;

  // The same seed in every eye, so a pair glances together.
  final math.Random _rng = math.Random(0x6a09e667);

  // The finger or cursor, in screen coordinates.
  double _px = 0;
  double _py = 0;
  bool _have = false;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _seenStartles = widget.controller?.startleCount ?? 0;
    _programFuture ??= _loadProgram();
    unawaited(
      _programFuture!.then((program) {
        if (!mounted || program == null) return;
        _shader = program.fragmentShader();
      }),
    );
  }

  @override
  void didUpdateWidget(Gaze oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _seenStartles = widget.controller?.startleCount ?? 0;
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerHoverEvent ||
        event is PointerMoveEvent ||
        event is PointerDownEvent) {
      _px = event.position.dx;
      _py = event.position.dy;
      _have = true;
      if (event is PointerDownEvent) _down = true;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down = false;
      // A lifted finger stops the looking. A mouse keeps its place.
      if (event.kind == ui.PointerDeviceKind.touch) _have = false;
    }
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 8 || size.height < 8 || !mounted) return;
    final w = widget;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.1) dt = 0.1;
    dt *= _clamp(w.speed, 0, 300) / 100;
    if (w.paused) dt = 0;
    final still = _reduced;
    _clock += dt;

    // Where this eye is on the screen.
    Offset? origin;
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      origin = ro.localToGlobal(Offset.zero);
    }

    final width = size.width;
    final height = size.height;
    final fill = 0.3 + _clamp(w.size, 0, 10) / 10 * 0.7;
    final radius = fill * math.min(width, height) / 2;
    final bobAmt =
        still ? 0.0 : math.sin(_clock * 0.9) * _clamp(w.bob, 0, 10) * 0.006;
    final cx = width / 2 + _clamp(w.offsetX, -50, 50) / 100 * width;
    final cy = height / 2 +
        _clamp(w.offsetY, -50, 50) / 100 * height +
        bobAmt * radius;

    // What it is looking at.
    final controller = w.controller;
    Offset? target = controller?.target;
    if (target == null && w.follow == GazeFollow.screen && _have) {
      target = Offset(_px, _py);
    }

    var tx = _clamp(w.restX, -90, 90) * _deg;
    var ty = _clamp(w.restY, -90, 90) * _deg;
    if (!_aimed) {
      _yaw = tx;
      _pitch = ty;
      _aimed = true;
    }
    var following = false;
    if (target != null && origin != null && w.reach > 0) {
      following = true;
      // The pointer in eye radii, on a plane a few radii in front of the eye:
      // a nearer plane means a harder turn.
      final dx = (target.dx - (origin.dx + cx)) / radius;
      final dy = -(target.dy - (origin.dy + cy)) / radius;
      final d = 17 / _clamp(w.reach, 0.1, 10);
      final lim = _clamp(w.maxTurn, 0, 85) * _deg;
      tx = _clamp(math.atan2(dx, d), -lim, lim);
      ty = _clamp(math.atan2(dy, math.sqrt(dx * dx + d * d)), -lim, lim);
    } else if (!still && w.wander > 0) {
      // Idle glances: hold, then jump. Eyes never glide.
      _nextGlance -= dt;
      if (_nextGlance <= 0) {
        final amp = _clamp(w.wander, 0, 10) * 2.2 * _deg;
        final home = _rng.nextDouble() < 0.4;
        _glanceX = home ? 0.0 : (_rng.nextDouble() * 2 - 1) * amp;
        _glanceY = home ? 0.0 : (_rng.nextDouble() * 2 - 1) * amp * 0.6;
        _nextGlance = _saccadeSec * (0.45 + _rng.nextDouble() * 1.1);
      }
      tx += _glanceX;
      ty += _glanceY;
    }
    if (!still) {
      tx += math.sin(_clock * 37.0) * 0.05 * _deg +
          math.sin(_clock * 23.0) * 0.04 * _deg;
      ty += math.sin(_clock * 31.0 + 1.0) * 0.05 * _deg;
    }
    final k = 1 - math.exp(-dt / math.max(0.005, _followSec));
    _yaw += (tx - _yaw) * k;
    _pitch += (ty - _pitch) * k;

    // The pupil: snaps small on a press, widens slowly as the pointer nears.
    if (controller != null && controller.startleCount != _seenStartles) {
      _seenStartles = controller.startleCount;
      _scare = 1;
    }
    final react = _clamp(w.dilate, 0, 10) / 10;
    if (_down) _flash = 1;
    final near = following ? 1.0 : 0.0;
    final want = math.max(
      0.2,
      1 + react * 0.22 * near - react * 0.45 * _flash - 0.55 * _scare,
    );
    // Closing is fast, opening again is slow, as in a real eye.
    final pk = 1 - math.exp(-dt / (want < _pupil ? 0.12 : 0.9));
    _pupil += (want - _pupil) * pk;
    _flash = _down ? 1.0 : math.max(0.0, _flash - dt * 2.2);
    _scare = math.max(0.0, _scare - dt * 1.1);
    final breathe = still
        ? 0.0
        : _hippus * 0.03 * math.sin(_clock * 1.7) * math.sin(_clock * 0.53 + 2.0);
    final pupilR = math.min(
      0.6,
      (0.13 + _clamp(w.pupilSize, 0, 10) * 0.035) * (_pupil + breathe),
    );

    // The eye's turn: yaw about y, then pitch about x.
    final cyw = math.cos(_yaw);
    final syw = math.sin(_yaw);
    final cp = math.cos(_pitch);
    final sp = math.sin(_pitch);

    // The cornea: a sphere through the rim of the iris and the apex.
    final a = _clamp(w.irisAngle, 10, 45) * _deg;
    final sinA = math.sin(a);
    final cosA = math.cos(a);
    final apex = 1 + math.max(0.01, _clamp(w.bulge, 0, 40) / 100);
    final rc =
        (sinA * sinA + (apex - cosA) * (apex - cosA)) / (2 * (apex - cosA));
    final zc = apex - rc;
    final irisZ = cosA - 0.04;
    final irisR = math.sqrt(1 - irisZ * irisZ);

    final shader = _shader;
    if (shader == null) return;
    final rect = Rect.fromCircle(
      center: Offset(cx, cy),
      radius: radius * 1.12 + 3,
    ).intersect(Offset.zero & size);
    if (rect.isEmpty) return;

    var i = 0;
    void f(double v) {
      shader.setFloat(i, v);
      i++;
    }

    f(cx);
    f(cy);
    f(radius);
    f(cyw);
    f(0);
    f(-syw);
    f(-syw * sp);
    f(cp);
    f(-cyw * sp);
    f(syw * cp);
    f(sp);
    f(cyw * cp);
    f(cosA);
    f(sinA);
    f(zc);
    f(rc);
    f(irisZ);
    f(irisR);
    f(pupilR);
    f(_gamma(w.irisColor.r));
    f(_gamma(w.irisColor.g));
    f(_gamma(w.irisColor.b));
    f(_gamma(w.scleraColor.r));
    f(_gamma(w.scleraColor.g));
    f(_gamma(w.scleraColor.b));
    f(_gamma(w.collarColor.r));
    f(_gamma(w.collarColor.g));
    f(_gamma(w.collarColor.b));
    f(math.cos(w.lightAngle * _deg));
    f(math.sin(w.lightAngle * _deg));
    f(_clamp(w.gloss, 0, 200) / 100);
    f(_clamp(w.redness, 0, 100) / 100);
    f(_clamp(w.veins, 0, 100) / 100);
    f(_limbus);
    f(_fiber);
    f(_clock % 100);
    f(_tier(w.quality) == 0 ? 0 : 1);

    _paint.shader = shader;
    canvas.drawRect(rect, _paint);
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
          controller: null,
          background: null,
          semanticLabel: w.semanticLabel,
        ),
      ),
    );
  }
}