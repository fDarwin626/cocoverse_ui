import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../api/character_controller.dart';
import '../../api/character_types.dart';
import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/clay_bot.frag';

// The robot is about six world units tall, with its feet at 0.
const double _robotUnits = 6.0;
const double _headY = 4.08;

// How tall the robot draws at size 1.0, in logical pixels, and how far size
// may go. A big robot costs the GPU a lot, so on phones and tablets the
// biggest allowed is three times the smallest; desktop and web may go further.
const double _baseHeight = 160;
const double _minSize = 0.5;
const double _maxSizeMobile = 1.5;
const double _maxSizeDesktop = 4.0;

// The low sun on the right: its height above the floor, in radians.
const double _sunElevation = 48 * math.pi / 180;

// The head leans a little as it turns, and the body follows part of the turn.
const double _headRoll = -0.16;
const double _bodyShare = 0.28;

const double _blinkSeconds = 0.17;

// Walking, in world units: how far a step reaches, how high a foot lifts, how
// far the body rocks, how much it bobs, how far the arms swing, and how far
// the body turns toward where it is going.
const double _stride = 0.62;
const double _stepLift = 0.17;
const double _waddle = 0.075;
const double _bob = 0.05;
const double _armSwing = 0.5;
const double _walkTurn = 0.5;
// Keeps the whole robot, helmet and ears, inside the space while it walks.
const double _walkMargin = 3.05;
// It starts a walk only for a gap worth crossing.
const double _walkStart = 0.6;
// How fast it walks at walkSpeed 1.0, in world units per second.
const double _walkUnitsPerSecond = 1.3;

// Waving: raise, wave, lower (seconds), the arm's angles, and the waving.
const double _armRest = 0.28;
const double _waveUpS = 0.35;
const double _waveHold = 1.5;
const double _waveDown = 0.4;
const double _waveRaise = 2.0;
const double _waveSway = 0.3;
const double _waveHz = 2.3;

// The drop-in entrance: where it falls from, how long, and the landing.
const double _dropFrom = 9.5;
const double _dropSeconds = 0.62;
const double _landSeconds = 0.55;

const List<Color> _defaultColors = <Color>[
  Color(0xFFB5A1FF),
  Color(0xFF22225E),
  Color(0xFFFFFFFF),
];

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

double _linear(double c) => math.pow(c, 2.2).toDouble();

double _tanh(double x) {
  final e = math.exp(2 * _clamp(x, -10, 10));
  return (e - 1) / (e + 1);
}

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.fuchsia;

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

/// How squashed the robot is, [l] seconds after landing.
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

/// Which side of the space the robot walks in from or out to.
enum ClayBotSide {
  /// The left edge.
  left,

  /// The right edge.
  right,
}

/// How the robot first appears.
enum ClayBotEntrance {
  /// It is simply there.
  none,

  /// It drops in from above, lands with a squash, then waves.
  dropIn,

  /// It walks in from past the left edge to its place, then waves. Needs a
  /// walkSpeed above 0.
  walkInFromLeft,

  /// It walks in from past the right edge to its place, then waves. Needs a
  /// walkSpeed above 0.
  walkInFromRight,
}

/// Controls a [ClayBot] from code: everything [CharacterController] does, plus
/// waving, and walking out of and back into the space.
class ClayBotController extends CharacterController {
  int _waves = 0;
  int _exits = 0;
  int _enters = 0;
  ClayBotSide _exitSide = ClayBotSide.right;
  ClayBotSide _enterSide = ClayBotSide.left;

  /// How many times [wave] has been called.
  int get waveCount => _waves;

  /// How many times [walkOff] has been called.
  int get exitCount => _exits;

  /// How many times [walkIn] has been called.
  int get enterCount => _enters;

  /// The side [walkOff] was last called with.
  ClayBotSide get exitSide => _exitSide;

  /// The side [walkIn] was last called with.
  ClayBotSide get enterSide => _enterSide;

  /// Makes the robot wave hello.
  void wave() {
    _waves++;
    notifyListeners();
  }

  /// Makes the robot walk out of the space past the given edge. [ClayBot.onExited]
  /// is called once it has gone. With a walkSpeed of 0 it disappears at once.
  void walkOff(ClayBotSide side) {
    _exitSide = side;
    _exits++;
    notifyListeners();
  }

  /// Makes a robot that has walked off, or never appeared, walk in from past the
  /// given edge to its place. With a walkSpeed of 0 it appears at once.
  void walkIn(ClayBotSide side) {
    _enterSide = side;
    _enters++;
    notifyListeners();
  }
}

/// A small matte clay robot with a round helmet and a screen for a face.
///
/// It follows your finger or pointer with its head and eyes, blinks, glances
/// about when nobody is pointing, hops when you tap it, and waves hello. It can
/// walk along the space to stand under your finger or pointer, walk to a
/// [position] you choose, and make an entrance: drop in, or walk in from past an
/// edge. Your own code can also steer it: [mood] sets how it feels, [lookAt] and
/// [lookAtKey] give it something to look at, [level] makes it react to a voice,
/// and a [ClayBotController] makes it blink, shake its head, nod, hop, wave, or
/// walk out of the space.
///
/// There is no ground and no background: it draws only the robot and its
/// shadow, so it sits on whatever is behind it. It fills the space its parent
/// gives it, which is also the space it walks in, so give it the full width of
/// the screen if you want it to walk in from past the edges.
class ClayBot extends StatefulWidget {
  /// Creates a clay robot.
  const ClayBot({
    super.key,
    this.colors,
    this.size = 1.0,
    this.shadowColor = const Color(0xFF2E4D6A),
    this.shadowStrength = 0.45,
    this.mood = CharacterMood.neutral,
    this.lookAt,
    this.lookAtKey,
    this.follow = PointerFollow.screen,
    this.reach = 1.0,
    this.hop = 1.0,
    this.blink = true,
    this.glance = 1.0,
    this.walkSpeed = 1.0,
    this.walkToPointer = true,
    this.position,
    this.entrance = ClayBotEntrance.none,
    this.entranceDelay = const Duration(milliseconds: 200),
    this.onEntranceEnd,
    this.onExited,
    this.wave = true,
    this.level = 0.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Three colours: the helmet and body, the face (the screen), and the eyes.
  /// Missing colours keep their defaults: a lavender clay, a deep navy screen
  /// and white eyes.
  final List<Color>? colors;

  /// Size of the robot, where 1.0 is about 160 logical pixels tall. The
  /// smallest is 0.5. On phones and tablets the biggest is 1.5, which is three
  /// times the smallest, because a big robot is costly to draw; on desktop and
  /// web the biggest is 4.0. The robot never grows past the height of the
  /// space it is given.
  final double size;

  /// Colour of the shadow on the invisible floor.
  final Color shadowColor;

  /// How dark the shadow is, from 0 to 1. 0 draws no shadow.
  final double shadowStrength;

  /// How the robot feels, shown through its eyes: open, curved into a smile,
  /// or shut. Changes ease in over a moment.
  final CharacterMood mood;

  /// A point on the screen for the robot to look at, in global coordinates
  /// (what a widget's `localToGlobal` gives). Null means no point. It wins over
  /// the pointer, and it works even when [interactive] is false.
  final Offset? lookAt;

  /// A widget for the robot to look at: it follows that widget's centre even as
  /// it moves or scrolls. Null means none. It wins over [lookAt] and the
  /// pointer, and it works even when [interactive] is false.
  final GlobalKey? lookAtKey;

  /// Whether the robot looks at the pointer, and where it may be. The default
  /// follows a touch or the mouse anywhere on the screen. Needs [interactive].
  final PointerFollow follow;

  /// How far the head turns toward what it looks at, where 1.0 is the default.
  /// 0 keeps the head still.
  final double reach;

  /// Height of the hop when you tap the robot, where 1.0 is the default. 0
  /// turns tapping off.
  final double hop;

  /// Whether the robot blinks now and then.
  final bool blink;

  /// How often the robot glances about when nobody is pointing, where 1.0 is
  /// the default. 0 never glances.
  final double glance;

  /// How fast the robot walks, where 1.0 is the default and 2.0 is twice as
  /// fast. 0 means it never walks: it only reacts. It then also appears,
  /// leaves and moves to a new [position] at once, with no walking.
  final double walkSpeed;

  /// Whether the robot walks along the space to stand under your finger or
  /// pointer, and back to its place a few seconds after you go. It needs a
  /// [walkSpeed] above 0 and [follow] and [interactive] on.
  final bool walkToPointer;

  /// Where the robot stands across the space, from -1 at the left edge to 1 at
  /// the right edge, with 0 the middle. When it changes, the robot walks there.
  /// Null means the middle.
  final double? position;

  /// How the robot first appears. Replays when the controller is reset.
  final ClayBotEntrance entrance;

  /// How long to wait before the entrance starts.
  final Duration entranceDelay;

  /// Called once when the entrance is over: after it lands or arrives.
  final VoidCallback? onEntranceEnd;

  /// Called once when the robot has walked out of the space after
  /// [ClayBotController.walkOff].
  final VoidCallback? onExited;

  /// Whether the robot waves hello by itself: when its entrance ends and when
  /// a pointer arrives after being away. Calling [ClayBotController.wave]
  /// always works.
  final bool wave;

  /// How loud a voice is, from 0 to 1, for a robot used as an assistant. A
  /// louder voice makes it bob and open its eyes wider and glow. 0 does
  /// nothing.
  final double level;

  /// Fill behind the robot. Null means transparent, which is what you want when
  /// it sits inside an app.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and the pointer affect the robot.
  final bool interactive;

  /// Level of detail. Lower settings march fewer steps and probe less for
  /// shadow and occlusion, which is faster on weak phones.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the animation from the start,
  /// including the entrance. Pass a [ClayBotController] to also make the robot
  /// blink, shake its head, nod, hop, wave, or walk out of and into the space.
  final EffectController? controller;

  /// Screen-reader description. Null marks the robot as decorative.
  final String? semanticLabel;

  @override
  State<ClayBot> createState() => _ClayBotState();
}

class _ClayBotState extends State<ClayBot> {
  FragmentShader? _shader;
  Paint? _paint;
  final math.Random _random = math.Random(7);

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

  // Walking: where it is along the floor, its speed, where it is headed, the
  // gait phase and how much of the gait is showing.
  double _walkX = 0;
  double _walkV = 0;
  double _walkGoal = 0;
  double _gait = 0;
  double _walkAmt = 0;
  double _lastActive = -1e9;

  // Waving: when it started, and which arm (+1 is the screen's right).
  double _waveAt = -1;
  double _waveSide = 1;

  // The entrance: 0 none, 1 waiting for its delay, 2 dropping in, 3 walking in.
  int _entPhase = 0;
  double _entAt = 0;
  double _landT = -1;

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
  void didUpdateWidget(ClayBot oldWidget) {
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
      debugPrint('ClayBot: could not load its shader: $error');
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
    if (controller is ClayBotController) {
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
  /// in any gesture, so the robot can sit over other widgets without stealing
  /// their taps.
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
    _walkV = 0;
    _walkAmt = 0;
    _gait = 0;
    _waveAt = -1;
    _landT = -1;
    _exiting = false;
    _gone = false;
    _lastActive = -1e9;
    _walkX = homeX;
    _walkGoal = homeX;
    _entPhase = 0;

    var mode = widget.entrance;
    final walks = mode == ClayBotEntrance.walkInFromLeft ||
        mode == ClayBotEntrance.walkInFromRight;
    if (walks && widget.walkSpeed <= 0) mode = ClayBotEntrance.none;
    if (mode != ClayBotEntrance.none) {
      _entPhase = 1;
      _entAt = clock + widget.entranceDelay.inMicroseconds / 1e6;
      if (mode == ClayBotEntrance.walkInFromLeft) _walkX = -(halfW + 3.6);
      if (mode == ClayBotEntrance.walkInFromRight) _walkX = halfW + 3.6;
    }
  }

  void _startWave(double clock, double side) {
    if (_waveAt >= 0) return;
    _waveAt = clock;
    _waveSide = side >= 0 ? 1 : -1;
  }

  void _finishEntrance(double clock) {
    _entPhase = 0;
    _landT = -1;
    final callback = widget.onEntranceEnd;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });
    }
    if (widget.wave) _startWave(clock, 1);
  }

  /// The point the code asks the robot to look at, in this widget's own
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

    // Where the robot stands: centred, with its size held inside the limits.
    final maxSize = _isMobile ? _maxSizeMobile : _maxSizeDesktop;
    final sizeScale = _clamp(widget.size, _minSize, maxSize);
    final heightPx = math.min(_baseHeight * sizeScale, size.height * 0.9);
    final px = math.max(heightPx / _robotUnits, 0.5);
    final originX = size.width / 2;
    final floorY = size.height / 2 + heightPx / 2;

    // The space it walks in, in world units from the middle: how far it can
    // go and still be fully inside, and where its own place is.
    final halfW = size.width / 2 / px;
    final lo = -halfW + _walkMargin;
    final hi = halfW - _walkMargin;
    final rangeLo = lo > hi ? (lo + hi) / 2 : lo;
    final rangeHi = lo > hi ? (lo + hi) / 2 : hi;
    final maxHome = math.max(0.0, halfW - _walkMargin);
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
    if (controller is ClayBotController) {
      if (controller.waveCount != _seenWaves) {
        _seenWaves = controller.waveCount;
        _startWave(clock, 1);
      }
      if (controller.exitCount != _seenExits) {
        _seenExits = controller.exitCount;
        _exiting = true;
        _gone = false;
        _exitSide = controller.exitSide == ClayBotSide.left ? -1 : 1;
        _entPhase = 0;
      }
      if (controller.enterCount != _seenEnters) {
        _seenEnters = controller.enterCount;
        final fromLeft = controller.enterSide == ClayBotSide.left;
        _exiting = false;
        _gone = false;
        _entPhase = 3;
        _walkV = 0;
        if (widget.walkSpeed > 0) {
          _walkX = fromLeft ? -(halfW + 3.6) : halfW + 3.6;
        } else {
          _walkX = homeX;
          _finishEntrance(clock);
        }
      }
    }

    // The entrance.
    var dropLift = 0.0;
    var dropSquash = 0.0;
    if (_entPhase == 1 && clock >= _entAt) {
      if (widget.entrance == ClayBotEntrance.dropIn) {
        _entPhase = 2;
        _entAt = clock;
      } else {
        _entPhase = 3;
      }
    }
    if (_entPhase == 2) {
      final d = clock - _entAt;
      if (d < _dropSeconds) {
        final u = d / _dropSeconds;
        dropLift = _dropFrom * (1 - u * u);
        dropSquash = -0.08 * u;
      } else {
        _landT = d - _dropSeconds;
        dropSquash = _landSquash(_landT);
        if (_landT > _landSeconds) _finishEntrance(clock);
      }
    }
    final waitingToAppear = _entPhase == 1;
    final dropping = _entPhase == 2 && clock - _entAt < _dropSeconds + 0.1;

    // A tap on the robot makes it hop.
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
          originX + (_walkX - 3.3) * px,
          floorY - 6.4 * px,
          originX + (_walkX + 3.3) * px,
          floorY + 0.2 * px,
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
      final headX = originX + _walkX * px;
      final headY = floorY - _headY * px;
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

    // A pointer that arrives after being away gets a wave, once the robot is
    // settled. While it is about, the robot may walk toward it.
    final pointerActive = pointerAim != null;
    // Walking chases a pointer only when it is over the widget.
    final chase = pointerAim != null &&
        (Offset.zero & size).inflate(8).contains(pointerAim);
    final ptrFloorX = pointerAim == null ? 0.0 : (pointerAim.dx - originX) / px;
    if (pointerActive) {
      final away = clock - _lastActive > 3;
      if (away && widget.wave && _entPhase == 0 && !_gone && !_exiting) {
        _startWave(clock, ptrFloorX - _walkX);
      }
      _lastActive = clock;
    }

    // Walking.
    if (!waitingToAppear) {
      if (widget.walkSpeed > 0) {
        var want = _walkGoal;
        if (_exiting) {
          want = _exitSide * (halfW + 4.0);
          _walkGoal = want;
        } else if (_entPhase == 3) {
          want = homeX;
          _walkGoal = want;
        } else if (!_gone) {
          if (chase && widget.walkToPointer) {
            want = _clamp(ptrFloorX, rangeLo, rangeHi);
          } else if (clock - _lastActive > 4) {
            want = homeX;
          }
          final walking = _walkV.abs() > 0.05;
          if (_waveAt >= 0) {
            _walkGoal = _walkX;
          } else if (walking || (want - _walkX).abs() > _walkStart) {
            _walkGoal = want;
          }
        }

        final boost = (_entPhase == 3 || _exiting) ? 1.3 : 1.0;
        final vmax = _walkUnitsPerSecond * widget.walkSpeed * boost;
        var left = elapsed;
        while (left > 0) {
          final h = math.min(left, 0.004);
          final err = _walkGoal - _walkX;
          final vd = _clamp(err * 2.5, -vmax, vmax);
          _walkV += (vd - _walkV) * math.min(1.0, h * 6);
          _walkX += _walkV * h;
          _gait += _walkV.abs() * h * math.pi / _stride;
          final amt = math.min(1.0, _walkV.abs() / 0.35);
          _walkAmt += (amt - _walkAmt) * math.min(1.0, h * 8);
          left -= h;
        }
        if ((_walkGoal - _walkX).abs() < 0.01 &&
            _walkV.abs() < 0.01 &&
            _walkAmt < 0.01) {
          _walkX = _walkGoal;
          _walkV = 0;
          _walkAmt = 0;
        }
        _gait %= math.pi * 2;
      } else {
        // It never walks: it is simply where it belongs.
        _walkV = 0;
        _walkAmt = 0;
        if (_exiting) {
          _walkX = _exitSide * (halfW + 4.0);
        } else if (!_gone) {
          _walkX = homeX;
        }
        _walkGoal = _walkX;
      }

      if (_entPhase == 3 &&
          (_walkX - homeX).abs() < 0.05 &&
          _walkV.abs() < 0.05) {
        _finishEntrance(clock);
      }
      if (_exiting && _walkX.abs() >= halfW + 3.6) {
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

    // Waving: the arm rises, waves, and lowers.
    var raiseL = _armRest;
    var raiseR = _armRest;
    final gs = math.sin(_gait);
    var swingL = _walkAmt * _armSwing * gs;
    var swingR = -swingL;
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
    // turns toward where it is going.
    const period = 0.25;
    final faceTarget = _tYaw * _bodyShare + _walkV.sign * _walkTurn * _walkAmt;
    _yaw.step(_tYaw, period, elapsed);
    _pitch.step(_tPitch, period, elapsed);
    _bodyYaw.step(faceTarget, period * 1.7, elapsed);
    _eyeX.step(_tEyeX, period * 0.45, elapsed);
    _eyeY.step(_tEyeY, period * 0.45, elapsed);

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
    var lift = dropLift + 0.05 * _levelNow;
    var squash = dropSquash;
    if (_hopT >= 0) {
      _hopT += elapsed;
      final pose = _hopPose(_hopT, _clamp(widget.hop, 0, 3) * 1.6);
      lift += pose.lift;
      squash += pose.squash;
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

    // Walking lifts a foot, rocks the body and bobs it.
    lift += _walkAmt * _bob * gs.abs();
    final roll = -_walkAmt * _waddle * gs;
    final liftL = _walkAmt * _stepLift * math.max(0.0, gs);
    final liftR = _walkAmt * _stepLift * math.max(0.0, -gs);

    if (waitingToAppear) return;

    // The head and body rotations; the shader needs their axes.
    final hy = _yaw.x + shakeYaw - _bodyYaw.x;
    _rotY(hy, _tA);
    _rotX(-(_pitch.x + nodPitch), _tB);
    _mul(_tA, _tB, _tC);
    _rotZ(_headRoll * hy, _tA);
    _mul(_tC, _tA, _headM);
    _rotY(_bodyYaw.x, _tA);
    _rotZ(roll, _tB);
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

    // The region that can hold the robot or its shadow, which is long.
    final shadowLength = 6.5 / math.tan(_sunElevation);
    final rect = Rect.fromLTRB(
      originX + (_walkX - 3.4 - shadowLength) * px,
      floorY - (7.0 + lift) * px,
      originX + (_walkX + 4.0) * px,
      floorY + 1.2 * px,
    ).intersect(Offset.zero & size);
    if (rect.isEmpty) return;

    final colors = widget.colors;
    final clay = colors != null && colors.isNotEmpty ? colors[0] : _defaultColors[0];
    final screen = colors != null && colors.length > 1 ? colors[1] : _defaultColors[1];
    final eyes = colors != null && colors.length > 2 ? colors[2] : _defaultColors[2];
    final shadow = widget.shadowColor;
    final squashed = _clamp(squash, -0.3, 0.4);
    final waving = extL + extR > 0;

    var eyeOpen = math.min(blinkOpen, _moodOpen);
    if (dropping) eyeOpen = 0.12;
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
      ..setFloat(20, _walkX)
      ..setFloat(21, lift)
      ..setFloat(22, 1 + squashed * 0.5)
      ..setFloat(23, 1 - squashed)
      ..setFloat(42, _eyeX.x)
      ..setFloat(43, _eyeY.x)
      ..setFloat(44, eyeOpen)
      ..setFloat(45, math.max(_moodJoy, math.max(hopJoy, waveJoy)))
      ..setFloat(46, liftL)
      ..setFloat(47, liftR)
      ..setFloat(48, math.cos(raiseL))
      ..setFloat(49, math.sin(raiseL))
      ..setFloat(50, math.cos(swingL))
      ..setFloat(51, math.sin(swingL))
      ..setFloat(52, math.cos(raiseR))
      ..setFloat(53, math.sin(raiseR))
      ..setFloat(54, math.cos(swingR))
      ..setFloat(55, math.sin(swingR))
      ..setFloat(56, extL)
      ..setFloat(57, extR)
      ..setFloat(58, waving ? 1.48 : 1.05)
      ..setFloat(59, waving ? 3.0 : 1.45)
      ..setFloat(60, waving ? 1.55 : 1.12)
      ..setFloat(61, waving ? 0.9 : 0.85)
      ..setFloat(71, 0.6 + 0.8 * _levelNow)
      ..setFloat(75, _clamp(widget.shadowStrength, 0, 1));
    _setVec3(shader, 10, math.cos(_sunElevation), math.sin(_sunElevation), 0);
    _setVec3(shader, 14, _walkX - 3.25, -0.05, -2.7);
    _setVec3(
      shader,
      17,
      _walkX + 3.25,
      6.55 + lift + math.max(0.0, -squashed) * 6,
      2.7,
    );
    _setCols(shader, 24, _bodyM);
    _setCols(shader, 33, _headM);
    _setVec3(shader, 62, _linear(clay.r), _linear(clay.g), _linear(clay.b));
    _setVec3(shader, 65, _linear(screen.r), _linear(screen.g), _linear(screen.b));
    _setVec3(shader, 68, eyes.r, eyes.g, eyes.b);
    _setVec3(shader, 72, shadow.r, shadow.g, shadow.b);

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