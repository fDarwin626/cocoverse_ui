import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../api/character_controller.dart';
import '../../api/character_types.dart';
import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/mito.frag';

// From the floor to the top of the helmet, in world units, with the robot at
// rest: the pod hovers this far up, then it is about six and a half tall.
const double _totalUnits = 8.1;
const double _headY = 5.0;
const double _hoverBase = 1.6;

// How tall Mito draws at size 1.0, in logical pixels, floor to helmet, and how
// far size may go. A big robot costs the GPU a lot, so on phones and tablets
// the biggest allowed is three times the smallest; desktop and web may go
// further.
const double _baseHeight = 224;
const double _minSize = 0.5;
const double _maxSizeMobile = 1.5;
const double _maxSizeDesktop = 4.0;

// The low sun on the right: its height above the floor, in radians.
const double _sunElevation = 48 * math.pi / 180;

// The head leans a little as it turns, and the body follows part of the turn.
const double _headRoll = -0.16;
const double _bodyShare = 0.28;

const double _blinkSeconds = 0.17;

// Hovering: how far it bobs, and how far it leans into a glide.
const double _bobHeight = 0.12;
const double _leanPerSpeed = 0.08;
const double _leanMax = 0.22;
const double _glideTurn = 0.22;

// Gliding, in world units: how big a gap is worth crossing, how fast it glides
// at glideSpeed 1.0 (units per second), and how much space to keep so the
// whole robot stays inside.
const double _glideMargin = 3.3;
const double _glideStart = 0.25;
const double _glideUnitsPerSecond = 6.0;
// Waving: raise, wave, lower (seconds), the arm's angles, and the waving.
const double _armRest = 0.12;
const double _waveUpS = 0.35;
const double _waveHold = 1.5;
const double _waveDown = 0.4;
const double _waveRaise = 2.0;
const double _waveSway = 0.3;
const double _waveHz = 2.3;

// The power-up entrance: how long it takes, and how far below its place the
// robot starts.
const double _riseSeconds = 1.2;
const double _riseFrom = 1.0;

// A hop's landing.
const double _landSeconds = 0.55;

// How fast the rings pulse at ringSpeed 1.0, in radians per second, and where
// the animation clock wraps (the shader needs it to wrap on a whole number of
// turns).
const double _ringRate = 2.6;
const double _ringWrap = math.pi * 2 * 12;

const List<Color> _defaultColors = <Color>[
  Color(0xFFF5F7FA),
  Color(0xFF0B0D10),
  Color(0xFF3D9BFF),
];

const List<Color> _defaultRings = <Color>[
  Color(0xFFFFD27A),
  Color(0xFFFF9A3D),
  Color(0xFFFF5A36),
];

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

double _linear(double c) => math.pow(c, 2.2).toDouble();

double _tanh(double x) {
  final e = math.exp(2 * _clamp(x, -10, 10));
  return (e - 1) / (e + 1);
}

double _smooth(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.fuchsia;

/// One ring colour to three: none keeps the defaults, one tints all three,
/// two gives the small ring the first and the other two the second.
List<Color> _resolveRings(List<Color>? colors) {
  if (colors == null || colors.isEmpty) return _defaultRings;
  if (colors.length == 1) return <Color>[colors[0], colors[0], colors[0]];
  if (colors.length == 2) return <Color>[colors[0], colors[1], colors[1]];
  return <Color>[colors[0], colors[1], colors[2]];
}

/// A critically damped spring that settles in about a given time.
class _Spring {
  double x = 0;
  double v = 0;

  void step(double target, double period, double dt) {
    final w = 5.8 / math.max(period, 0.02);
    var left = dt;
    while (left > 0) {
      final h = math.min(left, 0.004);
      v += (w * w * (target - x) - 2 * w * v) * h;
      x += v * h;
      left -= h;
    }
  }

  void snap(double target) {
    x = target;
    v = 0;
  }
}

// Row-major 3x3 rotations, written into a caller's buffer.
void _rotX(double a, List<double> o) {
  final c = math.cos(a);
  final s = math.sin(a);
  o[0] = 1; o[1] = 0; o[2] = 0;
  o[3] = 0; o[4] = c; o[5] = -s;
  o[6] = 0; o[7] = s; o[8] = c;
}

void _rotY(double a, List<double> o) {
  final c = math.cos(a);
  final s = math.sin(a);
  o[0] = c; o[1] = 0; o[2] = s;
  o[3] = 0; o[4] = 1; o[5] = 0;
  o[6] = -s; o[7] = 0; o[8] = c;
}

void _rotZ(double a, List<double> o) {
  final c = math.cos(a);
  final s = math.sin(a);
  o[0] = c; o[1] = -s; o[2] = 0;
  o[3] = s; o[4] = c; o[5] = 0;
  o[6] = 0; o[7] = 0; o[8] = 1;
}

void _mul(List<double> a, List<double> b, List<double> out) {
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      out[r * 3 + c] =
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
}

/// How squashed the robot is, [l] seconds after a hop lands.
double _landSquash(double l) {
  if (l > _landSeconds) return 0;
  final env = math.exp(-l * 7) * (1 - l / _landSeconds);
  return 0.16 * env * math.cos(l * 19);
}

/// How far the robot is lifted and squashed, [h] seconds into a hop.
({double lift, double squash, bool done}) _hopPose(double h, double height) {
  const crouch = 0.08;
  const air = 0.5;
  if (h < crouch) {
    return (
      lift: 0.0,
      squash: 0.13 * math.sin(math.pi / 2 * h / crouch),
      done: false,
    );
  }
  final a = h - crouch;
  if (a < air) {
    final u = a / air;
    return (
      lift: 4 * height * u * (1 - u),
      squash: -0.09 * (1 - 2 * u) * (1 - 2 * u) +
          0.13 * math.max(0.0, 1 - a / 0.06),
      done: false,
    );
  }
  final l = a - air;
  if (l > _landSeconds) return (lift: 0.0, squash: 0.0, done: true);
  return (lift: 0.0, squash: _landSquash(l), done: false);
}

/// How far the waving arm is raised, from 0 hanging to 1 up, [w] seconds in.
double _waveUp(double w) {
  double ease(double x) => x * x * (3 - 2 * x);
  if (w < _waveUpS) return ease(w / _waveUpS);
  if (w < _waveUpS + _waveHold) return 1;
  if (w < _waveUpS + _waveHold + _waveDown) {
    return 1 - ease((w - _waveUpS - _waveHold) / _waveDown);
  }
  return 0;
}

/// Which side of the space Mito flies in from or out to.
enum MitoSide {
  /// The left edge.
  left,

  /// The right edge.
  right,
}

/// How Mito first appears.
enum MitoEntrance {
  /// It is simply there.
  none,

  /// It starts low and dark, the rings light one after another from the
  /// smallest, and it rises to its place, then waves.
  powerUp,

  /// It glides in from past the left edge to its place, then waves. Needs a
  /// glideSpeed above 0.
  flyInFromLeft,

  /// It glides in from past the right edge to its place, then waves. Needs a
  /// glideSpeed above 0.
  flyInFromRight,
}

/// Controls a [Mito] from code: everything [CharacterController] does, plus
/// waving, and flying out of and back into the space.
class MitoController extends CharacterController {
  int _waves = 0;
  int _exits = 0;
  int _enters = 0;
  MitoSide _exitSide = MitoSide.right;
  MitoSide _enterSide = MitoSide.left;

  /// How many times [wave] has been called.
  int get waveCount => _waves;

  /// How many times [flyOff] has been called.
  int get exitCount => _exits;

  /// How many times [flyIn] has been called.
  int get enterCount => _enters;

  /// The side [flyOff] was last called with.
  MitoSide get exitSide => _exitSide;

  /// The side [flyIn] was last called with.
  MitoSide get enterSide => _enterSide;

  /// Makes Mito wave hello.
  void wave() {
    _waves++;
    notifyListeners();
  }

  /// Makes Mito glide out of the space past the given edge. [Mito.onExited] is
  /// called once it has gone. With a glideSpeed of 0 it disappears at once.
  void flyOff(MitoSide side) {
    _exitSide = side;
    _exits++;
    notifyListeners();
  }

  /// Makes a Mito that has flown off, or never appeared, glide in from past the
  /// given edge to its place. With a glideSpeed of 0 it appears at once.
  void flyIn(MitoSide side) {
    _enterSide = side;
    _enters++;
    notifyListeners();
  }
}

/// A small matte clay robot that hovers on three rings of light.
///
/// It follows your finger or pointer with its head and eyes, blinks, glances
/// about when nobody is pointing, hops when you tap it, and waves hello with a
/// five-fingered hand. It glides along the space to hover over your finger or
/// pointer, glides to a [position] you choose, and can make an entrance: power
/// up from the floor, or fly in from past an edge. The three rings under it
/// pulse one after another like thrusters. They flare when it hops or glides,
/// brighten with [level], and dim when [mood] is closed. Your own code can also
/// steer it: [mood] sets how it feels, [lookAt] and [lookAtKey] give it
/// something to look at, and a [MitoController] makes it blink, shake its head,
/// nod, hop, wave, or fly out of the space.
///
/// There is no ground and no background: it draws only the robot, its rings
/// and its shadow, so it sits on whatever is behind it. It fills the space its
/// parent gives it, which is also the space it glides in, so give it the full
/// width of the screen if you want it to fly in from past the edges, and a
/// little headroom above for its hops.
class Mito extends StatefulWidget {
  /// Creates a Mito.
  const Mito({
    super.key,
    this.colors,
    this.ringColors,
    this.size = 1.0,
    this.shadowColor = const Color(0xFF2E4D6A),
    this.shadowStrength = 0.0,
    this.mood = CharacterMood.neutral,
    this.lookAt,
    this.lookAtKey,
    this.follow = PointerFollow.screen,
    this.reach = 1.0,
    this.hop = 1.0,
    this.blink = true,
    this.glance = 1.0,
    this.glideSpeed = 1.0,
    this.glideToPointer = true,
    this.position,
    this.bob = 1.0,
    this.entrance = MitoEntrance.none,
    this.entranceDelay = const Duration(milliseconds: 200),
    this.onEntranceEnd,
    this.onExited,
    this.wave = true,
    this.level = 0.0,
    this.ringGlow = 0.0,
    this.ringSpeed = 1.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Three colours: the helmet and body, the face (the screen), and the eyes.
  /// Missing colours keep their defaults: a white clay, a near-black screen and
  /// blue eyes.
  final List<Color>? colors;

  /// Colours of the three rings, from the small one under the pod to the big
  /// one. Null keeps the defaults, a warm gold to orange to red. One colour
  /// tints all three rings; two colours give the small ring the first and the
  /// other two the second.
  final List<Color>? ringColors;

  /// Size of Mito, where 1.0 is about 210 logical pixels from the floor to the
  /// top of the helmet. The smallest is 0.5. On phones and tablets the biggest
  /// is 1.5, which is three times the smallest, because a big robot is costly
  /// to draw; on desktop and web the biggest is 4.0. Mito never grows past the
  /// height of the space it is given.
  final double size;

  /// Colour of the shadow on the invisible floor.
  final Color shadowColor;

  /// How dark the shadow is, from 0 to 1. 0 draws no shadow.
  final double shadowStrength;

  /// How Mito feels, shown through its eyes: open, curved into a smile, or
  /// shut. A shut Mito also powers down: it sinks a little and the rings dim.
  /// Changes ease in over a moment.
  final CharacterMood mood;

  /// A point on the screen for Mito to look at, in global coordinates (what a
  /// widget's `localToGlobal` gives). Null means no point. It wins over the
  /// pointer, and it works even when [interactive] is false.
  final Offset? lookAt;

  /// A widget for Mito to look at: it follows that widget's centre even as it
  /// moves or scrolls. Null means none. It wins over [lookAt] and the pointer,
  /// and it works even when [interactive] is false.
  final GlobalKey? lookAtKey;

  /// Whether Mito looks at the pointer, and where it may be. The default
  /// follows a touch or the mouse anywhere on the screen. Needs [interactive].
  final PointerFollow follow;

  /// How far the head turns toward what it looks at, where 1.0 is the default.
  /// 0 keeps the head still.
  final double reach;

  /// Height of the hop when you tap Mito, where 1.0 is the default. 0 turns
  /// tapping off.
  final double hop;

  /// Whether Mito blinks now and then.
  final bool blink;

  /// How often Mito glances about when nobody is pointing, where 1.0 is the
  /// default. 0 never glances.
  final double glance;

  /// How fast Mito glides, where 1.0 is the default and 2.0 is twice as fast.
  /// 0 means it never glides: it only reacts. It then also appears, leaves and
  /// moves to a new [position] at once.
  final double glideSpeed;

  /// Whether Mito glides along the space to hover over your finger or pointer,
  /// and back to its place a few seconds after you go. It needs a [glideSpeed]
  /// above 0 and [follow] and [interactive] on.
  final bool glideToPointer;

  /// Where Mito hovers across the space, from -1 at the left edge to 1 at the
  /// right edge, with 0 the middle. When it changes, Mito glides there. Null
  /// means the middle.
  final double? position;

  /// How much Mito bobs up and down while hovering, where 1.0 is the default.
  /// 0 holds it perfectly still.
  final double bob;

  /// How Mito first appears. Replays when the controller is reset.
  final MitoEntrance entrance;

  /// How long to wait before the entrance starts.
  final Duration entranceDelay;

  /// Called once when the entrance is over: after it has risen or arrived.
  final VoidCallback? onEntranceEnd;

  /// Called once when Mito has flown out of the space after
  /// [MitoController.flyOff].
  final VoidCallback? onExited;

  /// Whether Mito waves hello by itself: when its entrance ends and when a
  /// pointer arrives after being away. Calling [MitoController.wave] always
  /// works.
  final bool wave;

  /// How loud a voice is, from 0 to 1, for a robot used as an assistant. A
  /// louder voice makes it bob and open its eyes wider and glow, and the rings
  /// burn brighter. 0 does nothing.
  final double level;

  /// How bright the rings and the light they throw are, where 1.0 is the
  /// default. 0 hides them.
  final double ringGlow;

  /// How fast the rings pulse, where 1.0 is the default.
  final double ringSpeed;

  /// Fill behind Mito. Null means transparent, which is what you want when it
  /// sits inside an app.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and the pointer affect Mito.
  final bool interactive;

  /// Level of detail. Lower settings march fewer steps and probe less for
  /// shadow and occlusion, which is faster on weak phones.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the animation from the start,
  /// including the entrance. Pass a [MitoController] to also make Mito blink,
  /// shake its head, nod, hop, wave, or fly out of and into the space.
  final EffectController? controller;

  /// Screen-reader description. Null marks Mito as decorative.
  final String? semanticLabel;

  @override
  State<Mito> createState() => _MitoState();
}

class _MitoState extends State<Mito> {
  FragmentShader? _shader;
  Paint? _paint;
  final math.Random _random = math.Random(11);

  final List<double> _tA = List<double>.filled(9, 0);
  final List<double> _tB = List<double>.filled(9, 0);
  final List<double> _tC = List<double>.filled(9, 0);
  final List<double> _headM = List<double>.filled(9, 0);
  final List<double> _bodyM = List<double>.filled(9, 0);

  bool _started = false;
  double _lastTime = 0;
  final _Spring _yaw = _Spring();
  final _Spring _pitch = _Spring();
  final _Spring _bodyYaw = _Spring();
  final _Spring _eyeX = _Spring();
  final _Spring _eyeY = _Spring();
  final _Spring _lean = _Spring();
  double _tYaw = 0;
  double _tPitch = 0;
  double _tEyeX = 0;
  double _tEyeY = 0;
  double _nextGlance = 1.6;
  double _glanceYaw = 0;
  double _glancePitch = 0;
  double _blinkAt = -1;
  double _nextBlink = 2.2;
  double _hopT = -1;
  double _joyT = -1;
  double _moodOpen = 1;
  double _moodJoy = 0;
  double _levelNow = 0;

  // Gliding: where it is along the space, its speed, where it is headed, and
  // how much of a glide is showing.
  double _posX = 0;
  double _glideV = 0;
  double _glideGoal = 0;
  double _glideAmt = 0;
  double _lastActive = -1e9;

  // How high the pod was last frame, for tap tests and where it looks from.
  double _liftNow = _hoverBase;

  // The rings' animation clock.
  double _ringPhase = 0;

  // Waving: when it started, and which arm (+1 is the screen's right).
  double _waveAt = -1;
  double _waveSide = 1;

  // The entrance: 0 none, 1 waiting for its delay, 2 powering up, 3 flying in.
  int _entPhase = 0;
  double _entAt = 0;

  // Leaving the space.
  bool _exiting = false;
  double _exitSide = 1;
  bool _gone = false;

  // One-off actions from a controller.
  double _shakeT = -1;
  double _nodT = -1;
  int _seenBlinks = 0;
  int _seenShakes = 0;
  int _seenNods = 0;
  int _seenBounces = 0;
  int _seenWaves = 0;
  int _seenExits = 0;
  int _seenEnters = 0;

  // Touches and the pointer anywhere on the screen.
  Offset? _globalPosition;
  bool _globalActive = false;
  double _globalPull = 0;
  Offset? _tapGlobal;
  bool _tapPending = false;
  bool _routing = false;
  final Stopwatch _watch = Stopwatch()..start();
  double _lastPointerAt = -1e9;
  PointerDeviceKind _pointerKind = PointerDeviceKind.touch;

  @override
  void initState() {
    super.initState();
    _syncSeen();
    _syncRoute();
    _loadShader();
  }

  @override
  void didUpdateWidget(Mito oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _syncSeen();
    _syncRoute();
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
      debugPrint('Mito: could not load its shader: $error');
    }
  }

  @override
  void dispose() {
    if (_routing) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    }
    _shader?.dispose();
    super.dispose();
  }

  /// Starts counting a controller's actions from where it is now, so a
  /// controller that has been used before does not replay them.
  void _syncSeen() {
    final controller = widget.controller;
    if (controller is CharacterController) {
      _seenBlinks = controller.blinkCount;
      _seenShakes = controller.shakeCount;
      _seenNods = controller.nodCount;
      _seenBounces = controller.bounceCount;
    } else {
      _seenBlinks = 0;
      _seenShakes = 0;
      _seenNods = 0;
      _seenBounces = 0;
    }
    if (controller is MitoController) {
      _seenWaves = controller.waveCount;
      _seenExits = controller.exitCount;
      _seenEnters = controller.enterCount;
    } else {
      _seenWaves = 0;
      _seenExits = 0;
      _seenEnters = 0;
    }
  }

  /// Listens for pointer events anywhere on the screen, without taking part
  /// in any gesture, so Mito can sit over other widgets without stealing their
  /// taps.
  void _syncRoute() {
    final wanted = widget.interactive;
    if (wanted == _routing) return;
    _routing = wanted;
    final router = GestureBinding.instance.pointerRouter;
    if (wanted) {
      router.addGlobalRoute(_onGlobalPointer);
    } else {
      router.removeGlobalRoute(_onGlobalPointer);
      _globalActive = false;
    }
  }

  void _onGlobalPointer(PointerEvent event) {
    _lastPointerAt = _watch.elapsedMicroseconds / 1e6;
    _pointerKind = event.kind;
    if (event is PointerRemovedEvent || event is PointerExitEvent) {
      _globalActive = false;
    }
    if (event is PointerDownEvent) {
      _tapGlobal = event.position;
      _tapPending = true;
    }
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerHoverEvent) {
      _globalPosition = event.position;
      _globalActive = true;
    } else if ((event is PointerUpEvent || event is PointerCancelEvent) &&
        event.kind != PointerDeviceKind.mouse) {
      // A lifted finger ends the looking; a mouse keeps hovering.
      _globalActive = false;
    }
  }

  /// Puts everything back to the start, and sets up the entrance.
  void _begin(double clock, double homeX, double halfW) {
    _started = true;
    _yaw.snap(0);
    _pitch.snap(0);
    _bodyYaw.snap(0);
    _eyeX.snap(0);
    _eyeY.snap(0);
    _lean.snap(0);
    _tYaw = 0;
    _tPitch = 0;
    _tEyeX = 0;
    _tEyeY = 0;
    _nextGlance = 1.6;
    _blinkAt = -1;
    _nextBlink = 2.2;
    _hopT = -1;
    _joyT = -1;
    _shakeT = -1;
    _nodT = -1;
    _glideV = 0;
    _glideAmt = 0;
    _waveAt = -1;
    _exiting = false;
    _gone = false;
    _lastActive = -1e9;
    _posX = homeX;
    _glideGoal = homeX;
    _entPhase = 0;

    var mode = widget.entrance;
    final flies = mode == MitoEntrance.flyInFromLeft ||
        mode == MitoEntrance.flyInFromRight;
    if (flies && widget.glideSpeed <= 0) mode = MitoEntrance.none;
    if (mode != MitoEntrance.none) {
      _entPhase = 1;
      _entAt = clock + widget.entranceDelay.inMicroseconds / 1e6;
      if (mode == MitoEntrance.flyInFromLeft) _posX = -(halfW + 3.8);
      if (mode == MitoEntrance.flyInFromRight) _posX = halfW + 3.8;
    }
  }

  void _startWave(double clock, double side) {
    if (_waveAt >= 0) return;
    _waveAt = clock;
    _waveSide = side >= 0 ? 1 : -1;
  }

  void _finishEntrance(double clock) {
    _entPhase = 0;
    final callback = widget.onEntranceEnd;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });
    }
    if (widget.wave) _startWave(clock, 1);
  }

  /// The point the code asks Mito to look at, in this widget's own
  /// coordinates, or null when it has been given none.
  Offset? _codeTarget() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final keyed = widget.lookAtKey?.currentContext?.findRenderObject();
    if (keyed is RenderBox && keyed.attached && keyed.hasSize) {
      final centre = keyed.localToGlobal(keyed.size.center(Offset.zero));
      return box.globalToLocal(centre);
    }
    final at = widget.lookAt;
    if (at != null) return box.globalToLocal(at);
    return null;
  }

  /// Sets where the head and eyes turn, from how far to the side and how far
  /// up the target is, in radians.
  void _setAim(double yawRaw, double pitchRaw) {
    final maxYaw = _clamp(widget.reach, 0, 2) * 0.61;
    final maxPitch = maxYaw * 0.55;
    _tYaw = maxYaw > 0 ? maxYaw * _tanh(yawRaw / maxYaw) : 0;
    _tPitch = maxPitch > 0 ? maxPitch * _tanh(pitchRaw / maxPitch) : 0;
    const travel = 0.6;
    _tEyeX = travel * 0.62 * _tanh(yawRaw / 0.55);
    final up = _tanh(pitchRaw / 0.4);
    _tEyeY = travel * (up > 0 ? 0.46 : 0.2) * up;
  }

  void _setCols(FragmentShader shader, int index, List<double> m) {
    shader
      ..setFloat(index, m[0])
      ..setFloat(index + 1, m[3])
      ..setFloat(index + 2, m[6])
      ..setFloat(index + 3, m[1])
      ..setFloat(index + 4, m[4])
      ..setFloat(index + 5, m[7])
      ..setFloat(index + 6, m[2])
      ..setFloat(index + 7, m[5])
      ..setFloat(index + 8, m[8]);
  }

  void _setVec3(FragmentShader shader, int index, double x, double y, double z) {
    shader
      ..setFloat(index, x)
      ..setFloat(index + 1, y)
      ..setFloat(index + 2, z);
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    var elapsed = frame.time - _lastTime;
    final restarted = elapsed < 0;
    _lastTime = frame.time;
    elapsed = restarted ? 0.0 : math.min(elapsed, 0.05);
    final clock = frame.time;

    // Where Mito hovers: centred, with its size held inside the limits.
    final maxSize = _isMobile ? _maxSizeMobile : _maxSizeDesktop;
    final sizeScale = _clamp(widget.size, _minSize, maxSize);
    final heightPx = math.min(_baseHeight * sizeScale, size.height * 0.9);
    final px = math.max(heightPx / _totalUnits, 0.5);
    final originX = size.width / 2;
    final floorY = size.height / 2 + heightPx / 2;

    // The space it glides in, in world units from the middle: how far it can
    // go and still be fully inside, and where its own place is.
    final halfW = size.width / 2 / px;
    final lo = -halfW + _glideMargin;
    final hi = halfW - _glideMargin;
    final rangeLo = lo > hi ? (lo + hi) / 2 : lo;
    final rangeHi = lo > hi ? (lo + hi) / 2 : hi;
    final maxHome = math.max(0.0, halfW - _glideMargin);
    final homeX = _clamp(widget.position ?? 0.0, -1, 1) * maxHome;

    if (restarted || !_started) _begin(clock, homeX, halfW);

    // Actions asked for through a controller.
    final controller = widget.controller;
    if (controller is CharacterController) {
      if (controller.blinkCount != _seenBlinks) {
        _seenBlinks = controller.blinkCount;
        if (_blinkAt < 0) _blinkAt = clock;
      }
      if (controller.shakeCount != _seenShakes) {
        _seenShakes = controller.shakeCount;
        _shakeT = 0;
      }
      if (controller.nodCount != _seenNods) {
        _seenNods = controller.nodCount;
        _nodT = 0;
      }
      if (controller.bounceCount != _seenBounces) {
        _seenBounces = controller.bounceCount;
        if (widget.hop > 0 && (_hopT < 0 || _hopT > 0.6)) {
          _hopT = 0;
          _joyT = 0;
        }
      }
    }
    if (controller is MitoController) {
      if (controller.waveCount != _seenWaves) {
        _seenWaves = controller.waveCount;
        _startWave(clock, 1);
      }
      if (controller.exitCount != _seenExits) {
        _seenExits = controller.exitCount;
        _exiting = true;
        _gone = false;
        _exitSide = controller.exitSide == MitoSide.left ? -1 : 1;
        _entPhase = 0;
      }
      if (controller.enterCount != _seenEnters) {
        _seenEnters = controller.enterCount;
        final fromLeft = controller.enterSide == MitoSide.left;
        _exiting = false;
        _gone = false;
        _entPhase = 3;
        _glideV = 0;
        if (widget.glideSpeed > 0) {
          _posX = fromLeft ? -(halfW + 3.8) : halfW + 3.8;
        } else {
          _posX = homeX;
          _finishEntrance(clock);
        }
      }
    }

    // The entrance. Powering up starts low and dark, lights the rings one
    // after another and rises to the hover height.
    var riseOffset = 0.0;
    var powerU = 1.0;
    if (_entPhase == 1 && clock >= _entAt) {
      if (widget.entrance == MitoEntrance.powerUp) {
        _entPhase = 2;
        _entAt = clock;
      } else {
        _entPhase = 3;
      }
    }
    if (_entPhase == 2) {
      final d = clock - _entAt;
      powerU = _clamp(d / _riseSeconds, 0, 1);
      riseOffset = -_riseFrom * (1 - _smooth(0, 1, powerU));
      if (d >= _riseSeconds) _finishEntrance(clock);
    }
    final waitingToAppear = _entPhase == 1;
    final poweringUp = _entPhase == 2 && powerU < 1;

    // A tap on Mito makes it hop.
    if (_tapPending) {
      _tapPending = false;
      final box = context.findRenderObject();
      final tap = _tapGlobal;
      if (widget.interactive &&
          widget.hop > 0 &&
          tap != null &&
          box is RenderBox &&
          box.hasSize &&
          !_gone &&
          _entPhase == 0) {
        final local = box.globalToLocal(tap);
        final body = Rect.fromLTRB(
          originX + (_posX - 3.3) * px,
          floorY - (_liftNow + 6.4) * px,
          originX + (_posX + 3.3) * px,
          floorY - (_liftNow - 0.2) * px,
        );
        if (body.contains(local) && (_hopT < 0 || _hopT > 0.6)) {
          _hopT = 0;
          _joyT = 0;
        }
      }
    }

    // What the head and eyes look at: code first, then a touch or the pointer,
    // then a glance about now and then.
    _globalPull += ((_globalActive && widget.interactive ? 1.0 : 0.0) -
            _globalPull) *
        (1 - math.exp(-elapsed / 0.2));
    final nowSeconds = _watch.elapsedMicroseconds / 1e6;
    // A mouse that has stopped sending events may have left the window: stop
    // looking where it was after a few seconds. A finger counts while it is down.
    final fresh = _pointerKind != PointerDeviceKind.mouse ||
        nowSeconds - _lastPointerAt < 3.0;
    final codeAim = _codeTarget();
    Offset? pointerAim;
    if (widget.interactive) {
      final global = _globalPosition;
      final pointer = frame.pointer;
      if (widget.follow == PointerFollow.screen &&
          global != null &&
          fresh &&
          _globalPull > 0.05) {
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize) pointerAim = box.globalToLocal(global);
      } else if (widget.follow == PointerFollow.widget &&
          pointer != null &&
          frame.pointerStrength > 0.05) {
        pointerAim = pointer;
      }
    }
    final aim = codeAim ?? pointerAim;
    if (aim != null) {
      final headX = originX + _posX * px;
      final headY = floorY - (_liftNow + _headY) * px;
      final dx = (aim.dx - headX) / px;
      final dy = (headY - aim.dy) / px;
      _setAim(math.atan2(dx, 7), math.atan2(dy, math.sqrt(dx * dx + 49)));
      _nextGlance = clock + 2.5;
    } else if (widget.glance > 0) {
      if (clock >= _nextGlance) {
        final home = _random.nextDouble() < 0.3;
        _glanceYaw = home ? 0 : (_random.nextDouble() * 2 - 1) * 0.5;
        _glancePitch = home ? 0 : (_random.nextDouble() * 1.1 - 0.4) * 0.3;
        _nextGlance = clock +
            (1.4 + _random.nextDouble() * 2.6) * (10 / (4 + widget.glance * 6));
      }
      _setAim(_glanceYaw, _glancePitch);
    } else {
      _setAim(0, 0);
    }

    // A pointer that arrives after being away gets a wave, once Mito is
    // settled. While it is about, Mito may glide toward it.
    final pointerActive = pointerAim != null;
    // Gliding chases a pointer only when it is over the widget.
    final chase = pointerAim != null &&
        (Offset.zero & size).inflate(8).contains(pointerAim);
    final ptrFloorX = pointerAim == null ? 0.0 : (pointerAim.dx - originX) / px;
    if (pointerActive) {
      final away = clock - _lastActive > 3;
      if (away && widget.wave && _entPhase == 0 && !_gone && !_exiting) {
        _startWave(clock, ptrFloorX - _posX);
      }
      _lastActive = clock;
    }

    // Gliding.
    if (!waitingToAppear) {
      if (widget.glideSpeed > 0) {
        var want = _glideGoal;
        if (_exiting) {
          want = _exitSide * (halfW + 4.2);
          _glideGoal = want;
        } else if (_entPhase == 3) {
          want = homeX;
          _glideGoal = want;
        } else if (!_gone) {
          if (chase && widget.glideToPointer) {
            want = _clamp(ptrFloorX, rangeLo, rangeHi);
          } else if (clock - _lastActive > 4) {
            want = homeX;
          }
          final gliding = _glideV.abs() > 0.05;
          if (gliding || (want - _posX).abs() > _glideStart) {
            _glideGoal = want;
          }
        }

        final boost = (_entPhase == 3 || _exiting) ? 1.3 : 1.0;
        final vmax = _glideUnitsPerSecond * widget.glideSpeed * boost;
        var left = elapsed;
        while (left > 0) {
          final h = math.min(left, 0.004);
          final err = _glideGoal - _posX;
          final vd = _clamp(err * 5.0, -vmax, vmax);
          _glideV += (vd - _glideV) * math.min(1.0, h * 10.0);
          _posX += _glideV * h;
          final amt = math.min(1.0, _glideV.abs() / 0.5);
          _glideAmt += (amt - _glideAmt) * math.min(1.0, h * 6);
          left -= h;
        }
        if ((_glideGoal - _posX).abs() < 0.01 &&
            _glideV.abs() < 0.01 &&
            _glideAmt < 0.01) {
          _posX = _glideGoal;
          _glideV = 0;
          _glideAmt = 0;
        }
      } else {
        // It never glides: it is simply where it belongs.
        _glideV = 0;
        _glideAmt = 0;
        if (_exiting) {
          _posX = _exitSide * (halfW + 4.2);
        } else if (!_gone) {
          _posX = homeX;
        }
        _glideGoal = _posX;
      }

      if (_entPhase == 3 &&
          (_posX - homeX).abs() < 0.05 &&
          _glideV.abs() < 0.05) {
        _finishEntrance(clock);
      }
      if (_exiting && _posX.abs() >= halfW + 3.8) {
        _exiting = false;
        _gone = true;
        final callback = widget.onExited;
        if (callback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) callback();
          });
        }
      }
    }

    // Blinking.
    if (widget.blink && _blinkAt < 0 && clock >= _nextBlink) {
      _blinkAt = clock;
      _nextBlink = clock +
          (_random.nextDouble() < 0.2 ? 0.28 : 2.2 + _random.nextDouble() * 3.6);
    }
    var blinkOpen = 1.0;
    if (_blinkAt >= 0) {
      final b = (clock - _blinkAt) / _blinkSeconds;
      if (b >= 1) {
        _blinkAt = -1;
      } else {
        blinkOpen = 1 - 0.94 * math.sin(math.pi * b);
      }
    }

    // The mood sets how open the eyes are and how much they curve into a
    // smile; it eases over a moment.
    final moodEase = 1 - math.exp(-elapsed / 0.1);
    _moodOpen += ((widget.mood == CharacterMood.closed ? 0.0 : 1.0) - _moodOpen) *
        moodEase;
    _moodJoy += ((widget.mood == CharacterMood.happy ? 1.0 : 0.0) - _moodJoy) *
        moodEase;

    // A voice: quick to rise and slower to fall.
    final levelTarget = _clamp(widget.level, 0, 1);
    final levelEase = levelTarget > _levelNow
        ? 1 - math.exp(-elapsed / 0.05)
        : 1 - math.exp(-elapsed / 0.2);
    _levelNow += (levelTarget - _levelNow) * levelEase;

    // The arms float a little, lift outward as Mito glides, and wave: the arm
    // rises, waves, and lowers.
    var raiseL = _armRest + 0.05 * math.sin(clock * 1.9) + 0.14 * _glideAmt;
    var raiseR = _armRest + 0.05 * math.sin(clock * 1.9 + 1.3) + 0.14 * _glideAmt;
    var swingL = 0.04 * math.sin(clock * 1.3);
    var swingR = 0.04 * math.sin(clock * 1.3 + 2.0);
    var extL = 0.0;
    var extR = 0.0;
    var waveJoy = 0.0;
    if (_waveAt >= 0) {
      final w = clock - _waveAt;
      final up = _waveUp(w);
      final sway =
          _waveSway * up * up * math.sin((w - _waveUpS) * math.pi * 2 * _waveHz);
      final raise = _armRest + (_waveRaise - _armRest) * up + sway;
      if (_waveSide > 0) {
        raiseR = raise;
        swingR *= 1 - up;
        extR = up;
      } else {
        raiseL = raise;
        swingL *= 1 - up;
        extL = up;
      }
      waveJoy = up;
      if (w > _waveUpS + _waveHold + _waveDown) _waveAt = -1;
    }

    // The head and eyes ease toward where they look; the body lags behind and
    // turns a little toward where it is going, and leans into the glide.
    const period = 0.16;
    final faceTarget = _tYaw * _bodyShare + _glideV.sign * _glideTurn * _glideAmt;
    _yaw.step(_tYaw, period, elapsed);
    _pitch.step(_tPitch, period, elapsed);
    _bodyYaw.step(faceTarget, period * 1.7, elapsed);
    _eyeX.step(_tEyeX, period * 0.45, elapsed);
    _eyeY.step(_tEyeY, period * 0.45, elapsed);
    _lean.step(_clamp(_glideV * _leanPerSpeed, -_leanMax, _leanMax), 0.35, elapsed);

    // The head shake and the nod ride on top of where it is looking.
    var shakeYaw = 0.0;
    var nodPitch = 0.0;
    if (_shakeT >= 0) {
      _shakeT += elapsed;
      shakeYaw = math.sin(_shakeT * 20) * math.exp(-_shakeT * 4.5) * 0.5;
      if (_shakeT > 1.2) _shakeT = -1;
    }
    if (_nodT >= 0) {
      _nodT += elapsed;
      nodPitch = -math.sin(_nodT * 13) * math.exp(-_nodT * 3.5) * 0.35;
      if (_nodT > 1.2) _nodT = -1;
    }
    nodPitch -= 0.1 * _levelNow;

    // The hop, and the joy that goes with it.
    var hopLift = 0.0;
    var squash = 0.0;
    if (_hopT >= 0) {
      _hopT += elapsed;
      final pose = _hopPose(_hopT, _clamp(widget.hop, 0, 3) * 1.1);
      hopLift = pose.lift;
      squash = pose.squash;
      if (pose.done) _hopT = -1;
    }
    var hopJoy = 0.0;
    if (_joyT >= 0) {
      _joyT += elapsed;
      final j = _joyT;
      hopJoy = j < 0.08
          ? j / 0.08
          : (j < 0.95 ? 1.0 : math.max(0.0, 1 - (j - 0.95) / 0.15));
      if (j > 1.1) _joyT = -1;
    }

    // Hovering: a slow bob, a sink when it powers down, a lift with the voice.
    final bobAmt = _clamp(widget.bob, 0, 3);
    final hoverBob = bobAmt *
        (_bobHeight * math.sin(clock * math.pi * 2 * 0.32) +
            0.03 * math.sin(clock * math.pi * 2 * 0.83 + 1.0));
    final powerDip = 0.22 * (1 - _moodOpen);
    final lift = _hoverBase +
        hoverBob +
        riseOffset +
        hopLift -
        powerDip +
        0.05 * _levelNow;
    _liftNow = lift;

    // The rings: how strongly each burns, and their clock. They flare with a
    // hop, a glide and a voice, dim as Mito powers down, and light one after
    // another when it powers up.
    final speedFrac = widget.glideSpeed > 0
        ? math.min(1.0, _glideV.abs() / (_glideUnitsPerSecond * widget.glideSpeed))
        : 0.0;
    var thrust = 0.85 +
        0.45 * _levelNow +
        0.18 * speedFrac +
        0.25 * _clamp(hopLift / 1.1, 0, 1.5);
    thrust *= 1 - 0.55 * (1 - _moodOpen);
    thrust *= 1 + 0.12 * _moodJoy;
    final gate0 = thrust * _smooth(0.0, 0.4, powerU);
    final gate1 = thrust * _smooth(0.18, 0.58, powerU);
    final gate2 = thrust * _smooth(0.36, 0.76, powerU);
    _ringPhase = (_ringPhase +
            elapsed * _ringRate * _clamp(widget.ringSpeed, 0, 4) * (0.7 + 0.5 * thrust)) %
        _ringWrap;

    if (waitingToAppear || _gone) return;

    // The head and body rotations; the shader needs their axes. The body
    // leans into a glide.
    final hy = _yaw.x + shakeYaw - _bodyYaw.x;
    _rotY(hy, _tA);
    _rotX(-(_pitch.x + nodPitch), _tB);
    _mul(_tA, _tB, _tC);
    _rotZ(_headRoll * hy, _tA);
    _mul(_tC, _tA, _headM);
    _rotY(_bodyYaw.x, _tA);
    _rotZ(-_lean.x, _tB);
    _mul(_tA, _tB, _bodyM);

    // Quality: how hard the shader works.
    final steps = switch (frame.quality) {
      EffectQuality.low => 40.0,
      EffectQuality.medium => 56.0,
      EffectQuality.high => 80.0,
    };
    final aoTaps = switch (frame.quality) {
      EffectQuality.low => 2.0,
      EffectQuality.medium => 3.0,
      EffectQuality.high => 5.0,
    };
    final shadowSteps = switch (frame.quality) {
      EffectQuality.low => 8.0,
      EffectQuality.medium => 12.0,
      EffectQuality.high => 20.0,
    };

    // The region that can hold Mito, its rings or its shadow, which is long.
    final shadowLength = (6.6 + lift) / math.tan(_sunElevation);
    final rect = Rect.fromLTRB(
      originX + (_posX - 3.7 - shadowLength) * px,
      floorY - (7.6 + lift) * px,
      originX + (_posX + 5.4) * px,
      floorY + 1.3 * px,
    ).intersect(Offset.zero & size);
    if (rect.isEmpty) return;

    final colors = widget.colors;
    final clay = colors != null && colors.isNotEmpty ? colors[0] : _defaultColors[0];
    final screen = colors != null && colors.length > 1 ? colors[1] : _defaultColors[1];
    final eyes = colors != null && colors.length > 2 ? colors[2] : _defaultColors[2];
    final rings = _resolveRings(widget.ringColors);
    final shadow = widget.shadowColor;
    final squashed = _clamp(squash, -0.3, 0.4);
    final waving = extL + extR > 0;

    var eyeOpen = math.min(blinkOpen, _moodOpen);
    if (poweringUp) eyeOpen = math.min(eyeOpen, 0.12 + 0.88 * _smooth(0.55, 0.85, powerU));
    eyeOpen *= 1 + 0.35 * _levelNow;

    shader
      ..setFloat(0, originX)
      ..setFloat(1, floorY)
      ..setFloat(2, px)
      ..setFloat(3, rect.left)
      ..setFloat(4, rect.top)
      ..setFloat(5, rect.right)
      ..setFloat(6, rect.bottom)
      ..setFloat(7, steps)
      ..setFloat(8, aoTaps)
      ..setFloat(9, shadowSteps)
      ..setFloat(13, 6.0)
      ..setFloat(20, _posX)
      ..setFloat(21, lift)
      ..setFloat(22, 1 + squashed * 0.5)
      ..setFloat(23, 1 - squashed)
      ..setFloat(42, _eyeX.x)
      ..setFloat(43, _eyeY.x)
      ..setFloat(44, eyeOpen)
      ..setFloat(45, math.max(_moodJoy, math.max(hopJoy, waveJoy)))
      ..setFloat(46, math.cos(raiseL))
      ..setFloat(47, math.sin(raiseL))
      ..setFloat(48, math.cos(swingL))
      ..setFloat(49, math.sin(swingL))
      ..setFloat(50, math.cos(raiseR))
      ..setFloat(51, math.sin(raiseR))
      ..setFloat(52, math.cos(swingR))
      ..setFloat(53, math.sin(swingR))
      ..setFloat(54, extL)
      ..setFloat(55, extR)
      ..setFloat(56, waving ? 1.9 : 1.1)
      ..setFloat(57, waving ? 3.7 : 2.0)
      ..setFloat(58, waving ? 1.8 : 1.2)
      ..setFloat(59, 1.0)
      ..setFloat(69, 0.6 + 0.8 * _levelNow)
      ..setFloat(73, _clamp(widget.shadowStrength, 0, 1))
      ..setFloat(86, _clamp(widget.ringGlow, 0, 3))
      ..setFloat(87, _ringPhase);
    _setVec3(shader, 10, math.cos(_sunElevation), math.sin(_sunElevation), 0);
    _setVec3(shader, 14, _posX - 5.0, lift - 0.15, -2.7);
    _setVec3(
      shader,
      17,
      _posX + 5.0,
      lift + 7.1 + math.max(0.0, -squashed) * 6,
      2.7,
    );
    _setCols(shader, 24, _bodyM);
    _setCols(shader, 33, _headM);
    _setVec3(shader, 60, _linear(clay.r), _linear(clay.g), _linear(clay.b));
    _setVec3(shader, 63, _linear(screen.r), _linear(screen.g), _linear(screen.b));
    _setVec3(shader, 66, eyes.r, eyes.g, eyes.b);
    _setVec3(shader, 70, shadow.r, shadow.g, shadow.b);
    _setVec3(shader, 74, rings[0].r, rings[0].g, rings[0].b);
    _setVec3(shader, 77, rings[1].r, rings[1].g, rings[1].b);
    _setVec3(shader, 80, rings[2].r, rings[2].g, rings[2].b);
    _setVec3(shader, 83, gate0, gate1, gate2);

    canvas.drawRect(rect, paint);
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
