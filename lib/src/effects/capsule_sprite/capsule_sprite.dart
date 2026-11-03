import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../api/character_controller.dart';
import '../../api/character_types.dart';
import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/capsule_sprite.frag';

const double _deg = math.pi / 180;

// The capsule's diameter as a share of the frame's shorter side at size 1.0.
const double _fit = 0.709 * 0.9;

// Where the sprite looks with nobody to look at: straight at you, a little up.
// Its face is not rolled.
const double _restX = 0;
const double _restY = 10 * _deg;
const double _roll = 0;

// The seam between the clear and the frosted half: the clear half faces up.
const double _seamAngle = 90 * _deg;
const double _seamTilt = 64 * _deg;
const double _seamOffset = -0.05;

// Glass wall, seam lip and sprite, as shares of the capsule's radius.
const double _wall = 0.045;
const double _lipReach = 0.06;
const double _spriteRadius = 0.593;

// The pill eyes, in degrees as seen from the sprite's centre.
const double _eyeGap = 45;
const double _eyeLength = 34;
const double _eyeWidth = 10;

// The furthest the sprite turns toward something it looks at.
const double _maxTurn = 40 * _deg;

const double _blinkSeconds = 0.15;

const Color _defaultSprite = Color(0xFF1400F6);
const Color _defaultEyes = Color(0xFFF3F2F8);

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

double _linear(double c) => math.pow(c, 2.2).toDouble();

/// 0 outside [from] to [to], and a smooth hump from 0 up to 1 and back to 0
/// inside it.
double _bump(double u, double from, double to) {
  if (u <= from || u >= to) return 0;
  return math.sin(math.pi * (u - from) / (to - from));
}

/// How open the eyes are during the intro, over its progress [u] from 0 to 1:
/// asleep, opening, then one blink.
double _introLid(double u) {
  if (u < 0.18) return 0;
  if (u < 0.32) {
    final t = (u - 0.18) / 0.14;
    return t * t * (3 - 2 * t);
  }
  if (u >= 0.54 && u < 0.59) {
    final b = (u - 0.54) / 0.05;
    return b < 0.4 ? 1 - b / 0.4 : (b - 0.4) / 0.6;
  }
  return 1;
}

/// A sprite with two pill eyes, sealed in a thick glass capsule: the upper
/// half clear, the lower half frosted.
///
/// The sprite turns to look at your finger or pointer, the capsule leans
/// toward it, and the sprite blinks on its own. Pressing makes it squint.
/// Your own code can also steer it: [mood] sets how it feels, [lookAt] and
/// [lookAtKey] give it something to look at, [intro] plays a short wake-up
/// for a splash screen, and a [CharacterController] makes it blink, shake its
/// head, nod or hop. It fills the space its parent gives it and draws the
/// capsule centred in that space.
class CapsuleSprite extends StatefulWidget {
  /// Creates a capsule sprite.
  const CapsuleSprite({
    super.key,
    this.colors,
    this.frost = 0.5,
    this.size = 1.0,
    this.mood = CharacterMood.neutral,
    this.lookAt,
    this.lookAtKey,
    this.follow = PointerFollow.screen,
    this.intro = false,
    this.introDuration = const Duration(milliseconds: 2800),
    this.onIntroEnd,
    this.reach = 1.0,
    this.lean = 1.0,
    this.blink = 1.0,
    this.float = 1.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// The first colour is the sprite, the second is its eyes. Missing colours
  /// keep their defaults: a deep blue sprite with pale eyes. The glass takes
  /// no colour.
  final List<Color>? colors;

  /// How milky the lower half of the capsule is, from 0 to 1. 0 is clear glass
  /// all round, 0.5 is the default and 1 is nearly opaque milk.
  final double frost;

  /// Size of the capsule, where 1.0 is the default.
  final double size;

  /// How the sprite feels: its eyes open, squinted or shut. Changes ease in
  /// over a moment.
  final CharacterMood mood;

  /// A point on the screen for the sprite to look at, in global coordinates
  /// (what a widget's `localToGlobal` gives). Null means no point. It wins
  /// over the pointer, and it works even when [interactive] is false.
  final Offset? lookAt;

  /// A widget for the sprite to look at: it follows that widget's centre even
  /// as it moves or scrolls. Null means none. It wins over [lookAt] and the
  /// pointer, and it works even when [interactive] is false.
  final GlobalKey? lookAtKey;

  /// Whether the sprite looks at the pointer, and where it may be. The default
  /// follows a touch or the mouse anywhere on the screen. Needs [interactive].
  final PointerFollow follow;

  /// Plays a short wake-up when the sprite first appears, like a splash
  /// screen: it is asleep, opens its eyes, blinks, then looks left and right.
  final bool intro;

  /// How long the intro takes.
  final Duration introDuration;

  /// Called once when the intro has finished.
  final VoidCallback? onIntroEnd;

  /// How hard the sprite turns to look at its target, where 1.0 is the
  /// default. 0 stops it from turning to look.
  final double reach;

  /// How far the capsule leans toward its target, where 1.0 is the default.
  /// 0 keeps it upright.
  final double lean;

  /// How often the sprite blinks, where 1.0 is the default. 0 never blinks.
  final double blink;

  /// How much the capsule bobs and sways, and how much the sprite looks
  /// around when nothing is touching it. 1.0 is the default, 0 keeps it still.
  final double float;

  /// Fill behind the capsule. Null means transparent, so the clear glass shows
  /// whatever is behind it.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and the pointer affect the sprite.
  final bool interactive;

  /// Reserved. This effect draws with a single shader, so every level looks
  /// the same and costs the same for now.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the animation from the start,
  /// including the intro. Pass a [CharacterController] to also make the sprite
  /// blink, shake its head, nod or hop on demand.
  final EffectController? controller;

  /// Screen-reader description. Null marks the capsule as decorative.
  final String? semanticLabel;

  @override
  State<CapsuleSprite> createState() => _CapsuleSpriteState();
}

class _CapsuleSpriteState extends State<CapsuleSprite> {
  FragmentShader? _shader;
  Paint? _paint;
  final math.Random _random = math.Random();

  double _lastTime = 0;
  double _yaw = _restX;
  double _pitch = _restY;
  double _leanX = 0;
  double _leanY = 0;
  double _squint = 0;
  double _moodLid = 1;
  double _blinkT = -1;
  double _nextBlink = 1.6;
  bool _doubleBlink = false;
  double _introT = 0;
  bool _introDone = false;

  // One-off actions: how long each has been playing, or -1 when it is not.
  double _shakeT = -1;
  double _nodT = -1;
  double _bounceT = -1;
  int _seenBlinks = 0;
  int _seenShakes = 0;
  int _seenNods = 0;
  int _seenBounces = 0;

  // The last touch or mouse position anywhere on the screen.
  Offset? _globalPosition;
  bool _globalActive = false;
  double _globalPull = 0;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    _syncSeen();
    _syncFollow();
    _loadShader();
  }

  @override
  void didUpdateWidget(CapsuleSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.intro && !oldWidget.intro) {
      _introT = 0;
      _introDone = false;
    }
    if (oldWidget.controller != widget.controller) _syncSeen();
    if (oldWidget.follow != widget.follow) _syncFollow();
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
      debugPrint('CapsuleSprite: could not load its shader: $error');
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
  }

  void _syncFollow() {
    final wanted = widget.follow == PointerFollow.screen;
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

  void _resetMotion() {
    _yaw = _restX;
    _pitch = _restY;
    _leanX = 0;
    _leanY = 0;
    _squint = 0;
    _moodLid = 1;
    _blinkT = -1;
    _nextBlink = 1.6;
    _doubleBlink = false;
    _introT = 0;
    _introDone = false;
    _shakeT = -1;
    _nodT = -1;
    _bounceT = -1;
  }

  void _setVec3(FragmentShader shader, int index, double x, double y, double z) {
    shader
      ..setFloat(index, x)
      ..setFloat(index + 1, y)
      ..setFloat(index + 2, z);
  }

  /// The point the code asks the sprite to look at, in this widget's own
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

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;

    var elapsed = frame.time - _lastTime;
    if (elapsed < 0) {
      _resetMotion();
      elapsed = 0;
    }
    _lastTime = frame.time;
    elapsed = math.min(elapsed, 0.05);
    final clock = frame.time;

    // Actions asked for through a CharacterController.
    final controller = widget.controller;
    if (controller is CharacterController) {
      if (controller.blinkCount != _seenBlinks) {
        _seenBlinks = controller.blinkCount;
        if (_blinkT < 0) _blinkT = 0;
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
        _bounceT = 0;
      }
    }
    var shakeYaw = 0.0;
    var nodPitch = 0.0;
    var hop = 0.0;
    if (_shakeT >= 0) {
      _shakeT += elapsed;
      shakeYaw = math.sin(_shakeT * 20) * math.exp(-_shakeT * 4.5) * 26 * _deg;
      if (_shakeT > 1.2) _shakeT = -1;
    }
    if (_nodT >= 0) {
      _nodT += elapsed;
      nodPitch = -math.sin(_nodT * 13) * math.exp(-_nodT * 3.5) * 20 * _deg;
      if (_nodT > 1.2) _nodT = -1;
    }
    if (_bounceT >= 0) {
      _bounceT += elapsed;
      hop = math.sin(_bounceT * 10).abs() * math.exp(-_bounceT * 3.0) * 0.25;
      if (_bounceT > 1.4) _bounceT = -1;
    }

    // The capsule, in logical pixels, with its slow bob.
    final shortSide = math.min(size.width, size.height);
    final radius =
        math.max(1.0, _fit * _clamp(widget.size, 0.2, 1.6) * shortSide * 0.5);
    final fl = 1.5 * widget.float;
    final cx = size.width * 0.5 + math.sin(clock * 0.53) * fl * 0.035 * radius;
    final cy = size.height * 0.5 +
        math.sin(clock * 0.8) * fl * 0.07 * radius -
        hop * radius;

    // The intro: asleep, eyes open, one blink, then a look left and right.
    final introActive = widget.intro && !_introDone;
    var introLid = 1.0;
    var introYaw = 0.0;
    if (introActive) {
      final total = math.max(0.3, widget.introDuration.inMicroseconds / 1e6);
      _introT += elapsed;
      final u = _introT / total;
      introLid = _introLid(u);
      introYaw =
          (_bump(u, 0.36, 0.60) * -22 + _bump(u, 0.62, 0.86) * 22) * _deg;
      if (u >= 1) {
        _introDone = true;
        _nextBlink = 1.2;
        final callback = widget.onIntroEnd;
        if (callback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) callback();
          });
        }
      }
    }

    // Where the sprite looks and how the capsule leans: with nothing to look
    // at it glances slowly about; code can give it a target; a pointer pulls
    // it round.
    var targetYaw = _restX +
        (math.sin(clock * 0.37) * 6 * _deg + math.sin(clock * 0.91) * 2 * _deg) *
            fl +
        introYaw;
    var targetPitch = _restY + math.sin(clock * 0.29 + 1.3) * 4 * _deg * fl;
    var targetLeanX = math.sin(clock * 0.53) * 3 * _deg * fl;
    var targetLeanY = math.sin(clock * 0.41 + 0.7) * 2 * _deg * fl;

    _globalPull += ((_globalActive && widget.interactive ? 1.0 : 0.0) -
            _globalPull) *
        (1 - math.exp(-elapsed / 0.2));

    Offset? aim;
    var pull = 0.0;
    if (!introActive) {
      final fromCode = _codeTarget();
      final pointer = frame.pointer;
      final global = _globalPosition;
      if (fromCode != null) {
        aim = fromCode;
        pull = 1.0;
      } else if (widget.interactive &&
          widget.follow == PointerFollow.screen &&
          global != null &&
          _globalPull > 0.001) {
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          aim = box.globalToLocal(global);
          pull = _clamp(_globalPull, 0, 1);
        }
      } else if (widget.interactive &&
          widget.follow == PointerFollow.widget &&
          pointer != null &&
          frame.pointerStrength > 0.001) {
        aim = pointer;
        pull = _clamp(frame.pointerStrength, 0, 1);
      }
    }
    if (aim != null) {
      // The target in capsule radii, on a plane a few radii in front of it:
      // a nearer plane is a harder turn.
      final dx = (aim.dx - cx) / radius;
      final dy = -(aim.dy - cy) / radius;
      if (widget.reach > 0) {
        final distance = 1.6 / widget.reach;
        final lookYaw = _clamp(math.atan2(dx, distance), -_maxTurn, _maxTurn);
        final lookPitch = _clamp(
          math.atan2(dy, math.sqrt(dx * dx + distance * distance)),
          -_maxTurn,
          _maxTurn,
        );
        targetYaw += (lookYaw - targetYaw) * pull;
        targetPitch += (lookPitch - targetPitch) * pull;
      }
      final tilt = widget.lean * 22 * _deg;
      targetLeanX += _clamp(dx / 2.5, -1, 1) * tilt * pull;
      targetLeanY += _clamp(dy / 2.5, -1, 1) * tilt * pull;
    }

    final lookEase = 1 - math.exp(-elapsed / 0.09);
    _yaw += (targetYaw - _yaw) * lookEase;
    _pitch += (targetPitch - _pitch) * lookEase;
    // The glass is heavier than the sprite: it leans on a longer ease.
    final leanEase = 1 - math.exp(-elapsed / 0.35);
    _leanX += (targetLeanX - _leanX) * leanEase;
    _leanY += (targetLeanY - _leanY) * leanEase;

    // Blinking: shut fast, open a little slower, and now and then twice.
    if (widget.blink > 0 && !introActive) {
      _nextBlink -= elapsed;
      if (_nextBlink <= 0 && _blinkT < 0) {
        _blinkT = 0;
        if (_doubleBlink) {
          _doubleBlink = false;
          _nextBlink = 2.6 / widget.blink * (0.5 + _random.nextDouble());
        } else {
          _doubleBlink = _random.nextDouble() < 0.25;
          _nextBlink = _doubleBlink
              ? _blinkSeconds + 0.12
              : 2.6 / widget.blink * (0.5 + _random.nextDouble());
        }
      }
    }
    var lid = 1.0;
    if (_blinkT >= 0) {
      _blinkT += elapsed;
      final u = _blinkT / _blinkSeconds;
      lid = u < 0.4 ? 1 - u / 0.4 : math.min(1.0, (u - 0.4) / 0.6);
      if (u >= 1) _blinkT = -1;
    }
    if (introActive) lid = introLid;

    // A press is a happy squint, held while the finger is down.
    final press = widget.interactive && frame.pressed ? 1.0 : 0.0;
    _squint += (press - _squint) * (1 - math.exp(-elapsed / 0.06));

    // The mood sets how far the eyes open; it eases over a moment.
    final moodTarget = switch (widget.mood) {
      CharacterMood.neutral => 1.0,
      CharacterMood.happy => 0.3,
      CharacterMood.closed => 0.0,
    };
    _moodLid += (moodTarget - _moodLid) * (1 - math.exp(-elapsed / 0.1));
    final open = math.min(lid, math.min(1 - _squint * 0.8, _moodLid));

    // The head shake and the nod ride on top of where it is looking.
    final yaw = _yaw + shakeYaw;
    final pitch = _pitch + nodPitch;
    final leanX = _leanX + shakeYaw * 0.35;
    final leanY = _leanY;

    // The sprite's own axes in view space: right, up and forward, with its
    // face rolled a little about the way it looks.
    final cp = math.cos(pitch);
    final fx = math.sin(yaw) * cp;
    final fy = math.sin(pitch);
    final fz = math.cos(yaw) * cp;
    final rl = math.sqrt(fz * fz + fx * fx);
    final rx = fz / rl;
    final rz = -fx / rl;
    final ux = fy * rz;
    final uy = fz * rx - fx * rz;
    final uz = -fy * rx;
    final cr = math.cos(_roll);
    final sr = math.sin(_roll);

    // The seam plane's normal, leaned with the capsule.
    var nx = math.cos(_seamAngle) * math.sin(_seamTilt);
    var ny = math.sin(_seamAngle) * math.sin(_seamTilt);
    var nz = math.cos(_seamTilt);
    final cyaw = math.cos(leanX);
    final syaw = math.sin(leanX);
    final turnedX = cyaw * nx + syaw * nz;
    final turnedZ = -syaw * nx + cyaw * nz;
    nx = turnedX;
    nz = turnedZ;
    final cpit = math.cos(-leanY);
    final spit = math.sin(-leanY);
    final tiltedY = cpit * ny - spit * nz;
    final tiltedZ = spit * ny + cpit * nz;
    ny = tiltedY;
    nz = tiltedZ;

    final inner = 1 - _wall;
    final lip = math.max(0.3, inner - _lipReach);
    final bobY = math.sin(clock * 0.8 - 0.9) * fl * 0.045;

    final colors = widget.colors;
    final sprite = colors != null && colors.isNotEmpty ? colors[0] : _defaultSprite;
    final eyes = colors != null && colors.length > 1 ? colors[1] : _defaultEyes;

    shader
      ..setFloat(0, cx)
      ..setFloat(1, cy)
      ..setFloat(2, radius)
      ..setFloat(6, _seamOffset)
      ..setFloat(7, inner)
      ..setFloat(8, lip)
      ..setFloat(9, _spriteRadius)
      ..setFloat(10, bobY)
      ..setFloat(20, _eyeGap / 2 * _deg)
      ..setFloat(21, math.max(0, (_eyeLength - _eyeWidth) / 2) * _deg)
      ..setFloat(22, _eyeWidth / 2 * _deg)
      ..setFloat(23, open)
      ..setFloat(30, _clamp(widget.frost, 0, 1) * 2)
      ..setFloat(31, 1.0)
      ..setFloat(32, 1.0);
    _setVec3(shader, 3, nx, ny, nz);
    _setVec3(shader, 11, rx * cr + ux * sr, uy * sr, rz * cr + uz * sr);
    _setVec3(shader, 14, ux * cr - rx * sr, uy * cr, uz * cr - rz * sr);
    _setVec3(shader, 17, fx, fy, fz);
    _setVec3(
      shader,
      24,
      _linear(sprite.r),
      _linear(sprite.g),
      _linear(sprite.b),
    );
    _setVec3(
      shader,
      27,
      _linear(eyes.r),
      _linear(eyes.g),
      _linear(eyes.b),
    );

    canvas.drawRect(Offset.zero & size, paint);
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