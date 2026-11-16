import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const double _tau = math.pi * 2;
final double _halfFov = math.tan(40 * math.pi / 360);

/// Where the rock shader is loaded from. The part before `meteor_rock.frag`
/// must be written the same way as the path in clay_bot.dart's
/// `FragmentProgram.fromAsset(` line.
const String _rockAsset = 'packages/cocoverse_ui/shaders/meteor_rock.frag';

// The rock shader holds this many slabs, and this many planes for each.
const int _slotsPerSlab = 14;
const int _maxGpuSlabs = 12;

const int _hullPlanes = 26;
const double _physStep = 1 / 120;
const int _maxSubsteps = 5;
const double _damping = 0.88;
const int _maxShards = 12;
const int _maxShapes = 200;
const int _maxDebris = 160;

// The chips' texture: its size in pixels.
const int _tile = 128;

// Lights, all in the camera's space.
const double _keyX = 0.2182;
const double _keyY = 0.8729;
const double _keyZ = 0.4364;
const double _fillX = 0.7518;
const double _fillY = -0.1253;
const double _fillZ = -0.6474;
const double _bounceX = 0.0;
const double _bounceY = -0.9701;
const double _bounceZ = 0.2425;

// Colours in linear light: the fire under the rock, the melt.
const double _gR = 1.0;
const double _gG = 0.0194;
const double _gB = 0.0018;
const double _lavaR = 1.0;
const double _lavaG = 0.0437;
const double _lavaB = 0.0;

// How bright a chip is before its texture darkens it, and the exposure.
const double _rockLight = 0.11;
const double _exposure = 0.9;

// How much red fire-bounce the rock takes.
const double _rockGround = 0.06;

/// The shape that swarms round the meteor.
enum MeteorShape {
  /// A flat plus, the original.
  plus,

  /// A ring.
  torus,

  /// A short disc.
  cylinder,

  /// A cube.
  box,

  /// A pointed diamond with eight faces, the Ethereum shape.
  octahedron,
}

/// A cracked meteor with glowing seams, hanging in a swarm of shapes and
/// rock chips. It breaks apart when it appears and closes up, and a finger
/// or cursor can push the pieces away or turn the whole thing.
///
/// It has no background, so it works over anything. Only the swarm of shapes
/// takes a colour: the rock and the lava are fixed. It fills the space it is
/// given. The rock is drawn by a fragment shader, `meteor_rock.frag`, which
/// has to be listed under `shaders:` in the package's pubspec.
///
/// ```dart
/// const SizedBox(
///   height: 360,
///   child: Meteor(shape: MeteorShape.torus, shapeColor: Color(0xFF7BD8FF)),
/// )
/// ```
class Meteor extends StatefulWidget {
  /// Creates a meteor.
  const Meteor({
    super.key,
    this.shape = MeteorShape.plus,
    this.shapeColor = const Color(0xFFEDEFF5),
    this.shapeCount = 52,
    this.shapeSize = 5.0,
    this.shapeThickness = 5.0,
    this.shapeSpread = 5.0,
    this.debrisCount = 54,
    this.debrisSize = 5.0,
    this.debrisSpread = 5.0,
    this.shards = 11,
    this.irregularity = 6.0,
    this.thickness = 5.0,
    this.glow = 6.0,
    this.size = 3.7,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.spin = 3.0,
    this.bob = 4.0,
    this.sway = 4.0,
    this.entrance = true,
    this.scatter = 6.0,
    this.tumble = 6.0,
    this.stagger = 4.0,
    this.reach = 5.0,
    this.strength = 5.0,
    this.repel = 6.0,
    this.settle = 5.0,
    this.touchPush = true,
    this.dragToRotate = true,
    this.speed = 100.0,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Which shape swarms round the meteor.
  final MeteorShape shape;

  /// The colour of the swarm. This is the only thing that changes colour.
  final Color shapeColor;

  /// How many shapes, up to 200. Lower qualities draw fewer.
  final int shapeCount;

  /// How big each shape is, from 0 to 10.
  final double shapeSize;

  /// How deep each shape is, from 0 to 10. It changes the plus, the torus
  /// and the cylinder. The cube and the octahedron ignore it.
  final double shapeThickness;

  /// How far the swarm reaches from the rock, from 0 to 10.
  final double shapeSpread;

  /// How many rock chips float round it, up to 160.
  final int debrisCount;

  /// How big each chip is, from 0 to 10.
  final double debrisSize;

  /// How far the chips reach, from 0 to 10.
  final double debrisSpread;

  /// How many slabs the rock breaks into, from 3 to 12.
  final int shards;

  /// How uneven the ball and its break are, from 0 to 10.
  final double irregularity;

  /// How thick the slabs are, from 0 to 10. Thin slabs leave a wider hollow.
  final double thickness;

  /// How bright the cracks and the hollow burn, from 0 to 10.
  final double glow;

  /// How much of the box the meteor fills, from 0 to 10.
  final double size;

  /// Moves the meteor across the box, as a percentage of its width, from
  /// -50 to 50. Positive is right.
  final double offsetX;

  /// Moves the meteor down the box, as a percentage of its height, from -50
  /// to 50. Positive is down.
  final double offsetY;

  /// How fast it turns by itself, from 0 to 10. 0 stops the turning.
  final double spin;

  /// How far it rises and falls, from 0 to 10.
  final double bob;

  /// How much it rocks off vertical, from 0 to 10.
  final double sway;

  /// Whether the rock breaks apart and comes together when it appears.
  final bool entrance;

  /// How far the pieces start out, from 0 to 10.
  final double scatter;

  /// How hard they tumble when they arrive, from 0 to 10.
  final double tumble;

  /// How much later the last piece lands than the first, from 0 to 10.
  final double stagger;

  /// How much of the box a finger or cursor pushes, from 0 to 10.
  final double reach;

  /// How far the nearest pieces are shoved, from 0 to 10. 0 turns it off.
  final double strength;

  /// Which way pieces go, from 0 to 10. 0 bulges straight out from the
  /// middle, 10 shoves them directly away from the finger.
  final double repel;

  /// How sharply everything springs back, from 0 to 10.
  final double settle;

  /// Whether a finger or cursor pushes the pieces away.
  final bool touchPush;

  /// Whether dragging a finger or cursor turns the meteor.
  final bool dragToRotate;

  /// How fast time runs, as a percentage. 100 is normal, 0 freezes it.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings draw fewer pieces and fewer noise
  /// layers on the rock.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] breaks it apart and plays
  /// the entrance again.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative.
  final String? semanticLabel;

  @override
  State<Meteor> createState() => _MeteorState();
}

// ─── The state ───────────────────────────────────────────────────────────────

/// One moving thing: a slab (0), a swarm shape (1) or a rock chip (2).
class _Piece {
  _Piece(this.kind) {
    base[0] = 1;
    base[4] = 1;
    base[8] = 1;
  }

  final int kind;
  double hx = 0;
  double hy = 0;
  double hz = 0;
  double dx = 0;
  double dy = 1;
  double dz = 0;
  double ax = 0;
  double ay = 1;
  double az = 0;
  double tilt = 0;
  double delay = 0;
  double push = 0;
  double pushVel = 0;
  double ang = 0;
  double angVel = 0;
  double sx = 0;
  double sy = 0;
  double sz = 0;
  bool free = false;
  double scale = 1;
  double radius = 1;
  double lx = 0;
  double ly = 0;
  double lz = 0;
  double near = 0;
  double tint = 1;
  double value = 1;
  double uOff = 0;
  double vOff = 0;
  int slab = -1;
  final Float64List base = Float64List(9);
}

Future<ui.FragmentProgram?>? _programFuture;

Future<ui.FragmentProgram?> _loadProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(_rockAsset);
  } catch (e) {
    debugPrint(
      'Meteor: could not load the rock shader at $_rockAsset ($e). Check '
      'the shaders: list in pubspec.yaml and the path in meteor.dart.',
    );
    return null;
  }
}

class _MeteorState extends State<Meteor> {
  final Paint _plain = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _textured = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _rockPaint = Paint();
  ui.ImageShader? _shader;
  ui.FragmentShader? _rockShader;

  bool _reduced = false;
  double _lastTime = 0;
  double _t = 0;
  int _seenResets = 0;
  bool _settled = false;

  // What was built, and the pieces.
  String _builtKey = '';
  List<_Slab> _slabs = <_Slab>[];
  List<_Piece> _pieces = <_Piece>[];
  int _nSlabs = 0;
  int _nShapes = 0;
  int _nDebris = 0;
  _Mesh? _shapeMesh;
  _Mesh? _debrisMesh;
  final List<int> _before = <int>[];
  final List<int> _after = <int>[];
  Float64List _mw = Float64List(0);
  Float64List _wp = Float64List(0);
  Float64List _scrX = Float64List(0);
  Float64List _scrY = Float64List(0);
  double _entranceClock = 0;
  double _innerR = 0.45;

  // The picture buffers for the shapes and chips.
  Float32List _pos = Float32List(0);
  Float32List _tex = Float32List(0);
  Int32List _col = Int32List(0);
  int _nv = 0;
  int _maxV = 0;

  // Scratch space.
  final Float64List _rig = Float64List(9);
  final Float64List _ma = Float64List(9);
  final Float64List _mb = Float64List(9);
  final Float64List _mc = Float64List(9);
  final Float64List _md = Float64List(9);
  final Float64List _tw = Float64List(9);
  final Float64List _ts = Float64List(6);
  final Float64List _quat = Float64List(4);

  // The camera.
  double _camD = 5;
  double _focal = 1;
  double _cx = 0;
  double _cy = 0;
  double _bobY = 0;

  // Lighting results for the vertex just lit, and the glow in use.
  double _lr = 0;
  double _lg = 0;
  double _lb = 0;
  double _lavaPower = 1;
  double _heatK = 3.5;

  // The finger or cursor.
  double _px = 0;
  double _py = 0;
  bool _pIn = false;
  bool _dragging = false;
  double _hover = 0;
  double _userYaw = 0;
  double _userPitch = 0;
  double _yawVel = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;

    _programFuture ??= _loadProgram();
    unawaited(
      _programFuture!.then((program) {
        if (!mounted || program == null) return;
        _rockShader = program.fragmentShader();
        debugPrint('Meteor: rock shader loaded');
      }),
    );

    _rockFuture ??= _makeRock();
    unawaited(
      _rockFuture!.then((image) {
        if (!mounted) return;
        try {
          _shader = ui.ImageShader(
            image,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Float64List.fromList(<double>[
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              0, 0, 0, 1,
            ]),
            // No mipmaps: the swarm samples one exact white texel, and
            // blending it with its neighbours would grey it.
            filterQuality: FilterQuality.low,
          );
          _textured.shader = _shader;
        } catch (e) {
          // The engine could not use the picture (CanvasKit returned no
          // image). Chips fall back to plain colour, and the next mount
          // rebuilds the picture instead of reusing the bad one.
          debugPrint('Meteor: chip texture unavailable ($e)');
          _shader = null;
          _rockFuture = null;
        }
      }, onError: (Object e) {
        debugPrint('Meteor: chip texture failed to build ($e)');
        _rockFuture = null;
      }),
    );

  }

  @override
  void didUpdateWidget(Meteor oldWidget) {
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
    _rockShader?.dispose();
    _rockShader = null;
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _resetEntrance();
    }
  }

  void _onPointer(PointerEvent e) {
    _px = e.localPosition.dx;
    _py = e.localPosition.dy;
    _pIn = true;
  }

  void _onUp(PointerEvent e) {
    if (e.kind == ui.PointerDeviceKind.touch) _pIn = false;
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
    _yawVel = 0;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _userYaw += d.delta.dx * 0.012;
    _userPitch = _clamp(_userPitch + d.delta.dy * 0.008, -0.9, 0.9);
  }

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
    _yawVel = _clamp(d.velocity.pixelsPerSecond.dx * 0.012, -14, 14);
  }

  void _onPanCancel() {
    _dragging = false;
  }

  // ─── Building ──────────────────────────────────────────────────────────────

  void _ensureBuilt() {
    final w = widget;
    final tier = _tier(w.quality);
    final key = <Object>[
      w.shards,
      (w.irregularity * 10).round(),
      (w.thickness * 10).round(),
      w.shape.index,
      w.shapeCount,
      (w.shapeThickness * 10).round(),
      w.debrisCount,
      tier,
    ].join('|');
    if (key == _builtKey) return;
    _builtKey = key;
    _build(tier);
  }

  void _build(int tier) {
    final w = widget;
    final husk = _buildHusk(w.shards, w.irregularity, w.thickness);
    _innerR = husk.inner;
    _slabs = husk.slabs;

    final share = const <double>[0.4, 0.7, 1.0][tier];
    _nShapes = math.min(_maxShapes, math.max(0, (w.shapeCount * share).round()));
    _nDebris = math.min(_maxDebris, math.max(0, (w.debrisCount * share).round()));
    _nSlabs = math.min(_slabs.length, _maxGpuSlabs);
    _shapeMesh = _nShapes > 0 ? _buildShape(w.shape, w.shapeThickness, tier) : null;
    _debrisMesh = _nDebris > 0 ? _buildDebris() : null;

    final rng = math.Random(0x1f123bb5);
    double rnd() => rng.nextDouble();
    final list = <_Piece>[];

    for (var i = 0; i < _nSlabs; i++) {
      final s = _slabs[i];
      final p = _Piece(0)
        ..slab = i
        ..hx = s.home.x
        ..hy = s.home.y
        ..hz = s.home.z
        ..dx = s.dir.x
        ..dy = s.dir.y
        ..dz = s.dir.z
        ..value = s.value;
      _randomAxis(rng, p);
      p.tilt = rnd() - 0.5;
      p.delay = rnd();
      list.add(p);
    }

    for (var i = 0; i < _nShapes; i++) {
      final dir = _randomDir(rng);
      final radius = 0.45 + math.pow(rnd(), 0.62).toDouble() * 1.15;
      final p = _Piece(1)
        ..dx = dir.x
        ..dy = dir.y
        ..dz = dir.z
        ..radius = radius
        ..tint = 0.82 + rnd() * 0.3
        ..free = true
        ..scale = 0.7 + rnd() * 0.6;
      _randomAxis(rng, p);
      p.tilt = rnd() - 0.5;
      p.delay = rnd();
      _randomRotation(rng, p.base);
      p.sx = (rnd() - 0.5) * 0.62;
      p.sy = (rnd() - 0.5) * 0.62;
      p.sz = (rnd() - 0.5) * 0.62;
      list.add(p);
    }

    for (var i = 0; i < _nDebris; i++) {
      final dir = _randomDir(rng);
      final radius = 1.12 + math.pow(rnd(), 0.8).toDouble() * 0.95;
      final p = _Piece(2)
        ..dx = dir.x
        ..dy = dir.y
        ..dz = dir.z
        ..radius = radius
        ..value = 0.4 + rnd() * 0.6
        ..free = true
        ..scale = 0.05 + rnd() * 0.1
        ..uOff = rnd() * _tile
        ..vOff = rnd() * _tile;
      final a = _randomDir(rng);
      p.ax = a.x;
      p.ay = a.y;
      p.az = a.z;
      p.tilt = rnd() - 0.5;
      p.delay = rnd();
      _randomRotation(rng, p.base);
      p.sx = (rnd() - 0.5) * 1.6;
      p.sy = (rnd() - 0.5) * 1.6;
      p.sz = (rnd() - 0.5) * 1.6;
      list.add(p);
    }

    _pieces = list;
    final n = list.length;
    _mw = Float64List(n * 9);
    _wp = Float64List(n * 3);
    _scrX = Float64List(n);
    _scrY = Float64List(n);

    final verts = _nShapes * (_shapeMesh?.count ?? 0) + _nDebris * (_debrisMesh?.count ?? 0);
    _maxV = verts + 3;
    _pos = Float32List(_maxV * 2);
    _tex = Float32List(_maxV * 2);
    _col = Int32List(_maxV);

    _resetEntrance();
  }

  void _randomAxis(math.Random rng, _Piece p) {
    final v = _V3(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5, rng.nextDouble() - 0.5).unit;
    p.ax = v.x;
    p.ay = v.y;
    p.az = v.z;
  }

  /// The break is the starting condition of the same spring the finger
  /// pushes against, so a touch during the entrance blends instead of
  /// fighting it.
  void _resetEntrance() {
    final w = widget;
    final rng = math.Random(0x85ebca6b);
    double rnd() => rng.nextDouble();
    _entranceClock = 0;
    _settled = false;
    if (!w.entrance || _reduced) {
      _settleAll();
      return;
    }
    final scatter = _clamp(w.scatter, 0, 10) / 10 * 2.9 + 0.15;
    final tumble = _clamp(w.tumble, 0, 10) / 10 * 3.4;
    for (final p in _pieces) {
      final reach = p.kind == 0 ? 1.0 : (p.kind == 1 ? 1.35 : 2.1);
      p.push = scatter * reach * (0.55 + rnd() * 0.9);
      p.pushVel = -scatter * (0.4 + rnd() * 0.5);
      p.ang = (rnd() - 0.5) * 2 * tumble;
      p.angVel = (rnd() - 0.5) * 2 * tumble * 2.2;
    }
  }

  void _settleAll() {
    for (final p in _pieces) {
      p.push = 0;
      p.pushVel = 0;
      p.ang = 0;
      p.angVel = 0;
      p.lx = 0;
      p.ly = 0;
      p.lz = 0;
    }
    _hover = 0;
    _entranceClock = 10;
    _settled = true;
  }

  // ─── Painting ──────────────────────────────────────────────────────────────

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 8 || size.height < 8) return;
    final w = widget;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.1) dt = 0.1;
    dt *= _clamp(w.speed, 0, 300) / 100;
    if (w.paused || _reduced) dt = 0;

    _ensureBuilt();
    if (_reduced && !_settled) _settleAll();
    final n = _pieces.length;
    if (n == 0) return;
    _t += dt;
    final tier = _tier(w.quality);

    // The camera: the husk fills a share of the shorter side.
    final width = size.width;
    final height = size.height;
    final aspect = width / height;
    final fill = 0.36 + _clamp(w.size, 0, 10) / 10 * 0.62;
    _camD = 1.16 / math.max(0.02, fill * _halfFov * math.min(1.0, aspect));
    _focal = (height / 2) / _halfFov;
    _cx = width / 2 + _clamp(w.offsetX, -50, 50) / 100 * width;
    _cy = height / 2 + _clamp(w.offsetY, -50, 50) / 100 * height;

    // Light settings from Glow.
    final intensity = _clamp(w.glow, 0, 10) / 10;
    _heatK = 0.4 + intensity * 5.2;
    _lavaPower = 0.12 + intensity * 1.55;

    // A drag turns it, and keeps turning a little after the finger lifts.
    if (!_dragging && w.dragToRotate) {
      _userYaw += _yawVel * dt;
      _yawVel *= math.exp(-dt * 2.2);
      _userPitch *= math.exp(-dt * 1.4);
    }
    if (!w.dragToRotate) {
      _userYaw = 0;
      _userPitch = 0;
      _yawVel = 0;
    }

    // Idle motion of the whole rig.
    final spin = _clamp(w.spin, 0, 10) / 10 * 0.52;
    final bob = _clamp(w.bob, 0, 10) / 10 * 0.11;
    final sway = _clamp(w.sway, 0, 10) / 10 * 0.17;
    _eulerInto(
      _rig,
      math.sin(_t * 0.31 + 1.1) * sway * 0.6 + _userPitch,
      _t * spin + _userYaw,
      math.sin(_t * 0.43) * sway,
    );
    _bobY = math.sin(_t * 0.6) * bob;

    // Spread moves the swarm already on screen.
    final shapeSpread = 0.5 + _clamp(w.shapeSpread, 0, 10) / 10 * 1.1;
    final debrisSpread = 0.6 + _clamp(w.debrisSpread, 0, 10) / 10 * 0.8;
    for (var i = _nSlabs; i < n; i++) {
      final p = _pieces[i];
      final r = p.radius * (p.kind == 1 ? shapeSpread : debrisSpread);
      p.hx = p.dx * r;
      p.hy = p.dy * r;
      p.hz = p.dz * r;
    }

    // The finger or cursor.
    final wanted = w.touchPush && _pIn && !_dragging && w.strength > 0 ? 1.0 : 0.0;
    _hover += (wanted - _hover) * (1 - math.exp(-dt * 9));
    if (_hover < 0.002) _hover = 0;
    final reachPx =
        (0.12 + _clamp(w.reach, 0, 10) / 10 * 0.9) * 0.5 * math.min(width, height);
    _updateNear(dt, reachPx);

    // The springs.
    final k = 14 + _clamp(w.settle, 0, 10) / 10 * 62;
    final c = 2 * math.sqrt(k) * _damping;
    final strength =
        math.pow(_clamp(w.strength, 0, 10) / 10, 1.35).toDouble() * 1.9 * _hover;
    final stagger = _clamp(w.stagger, 0, 10) / 10 * 0.95;
    var remaining = math.min(dt, _maxSubsteps * _physStep);
    var guard = 0;
    while (remaining > 0 && guard < _maxSubsteps) {
      final step = math.min(_physStep, remaining);
      _entranceClock += step;
      final released =
          stagger <= 0 ? 1.0 : _clamp(_entranceClock / stagger, 0, 1);
      _stepPieces(0, _nSlabs, step, k, c, strength, released);
      _stepPieces(_nSlabs, _nSlabs + _nShapes, step, k, c, strength * 1.3, released);
      _stepPieces(_nSlabs + _nShapes, n, step, k * 0.55, c * 0.55, strength * 2.4,
          released);
      remaining -= step;
      guard++;
    }

    _pose(w);

    // Shapes and chips behind the rock, or inside its shell, are drawn
    // first, so the slabs hide them and they show through the gaps. The
    // rest are drawn over it.
    _before.clear();
    _after.clear();
    for (var i = _nSlabs; i < n; i++) {
      final dx = _wp[i * 3];
      final dy = _wp[i * 3 + 1] - _bobY;
      final dz = _wp[i * 3 + 2];
      final inside = dx * dx + dy * dy + dz * dz < 0.81;
      if (dz < 0 || inside) {
        _before.add(i);
      } else {
        _after.add(i);
      }
    }
    int byDepth(int a, int b) => _wp[a * 3 + 2].compareTo(_wp[b * 3 + 2]);
    _before.sort(byDepth);
    _after.sort(byDepth);

    final shapeLin = _lin(w.shapeColor);
    final shapeSize = _clamp(w.shapeSize, 0, 10) / 10 * 0.4 + 0.08;
    final debrisSize = _clamp(w.debrisSize, 0, 10) / 10 * 1.4 + 0.3;

    _nv = 0;
    for (final i in _before) {
      _emitPiece(i, shapeLin, shapeSize, debrisSize);
    }
    final mid = _nv;
    _flush(canvas, 0, mid);
    _drawRock(canvas, size, tier);
    for (final i in _after) {
      _emitPiece(i, shapeLin, shapeSize, debrisSize);
    }
    _flush(canvas, mid, _nv);
  }

  void _emitPiece(int i, List<double> shapeLin, double shapeSize, double debrisSize) {
    final p = _pieces[i];
    if (p.kind == 1) {
      final mesh = _shapeMesh;
      if (mesh == null) return;
      _emit(
        mesh,
        i,
        shapeSize * p.scale,
        shapeLin[0] * p.tint,
        shapeLin[1] * p.tint,
        shapeLin[2] * p.tint,
        0.03,
        true,
        0,
        0,
      );
    } else {
      final mesh = _debrisMesh;
      if (mesh == null) return;
      final a = _rockLight * (0.42 + p.value * 1.25);
      _emit(mesh, i, debrisSize * p.scale, a, a * 0.98, a * 0.95, 0.45, false,
          p.uOff, p.vOff);
    }
  }

  /// Draws every slab with the rock shader, in one pass over the part of the
  /// screen they cover.
  void _drawRock(Canvas canvas, Size size, int tier) {
    final shader = _rockShader;
    if (shader == null || _nSlabs == 0) return;

    var x0 = double.infinity;
    var y0 = double.infinity;
    var x1 = -double.infinity;
    var y1 = -double.infinity;
    for (var s = 0; s < _nSlabs; s++) {
      final zc = math.max(_camD - _wp[s * 3 + 2], 0.3);
      final rpx = _slabs[s].radius * 1.05 * _focal / zc + 3;
      x0 = math.min(x0, _scrX[s] - rpx);
      y0 = math.min(y0, _scrY[s] - rpx);
      x1 = math.max(x1, _scrX[s] + rpx);
      y1 = math.max(y1, _scrY[s] + rpx);
    }
    final rect = Rect.fromLTRB(
      math.max(0.0, x0),
      math.max(0.0, y0),
      math.min(size.width, x1),
      math.min(size.height, y1),
    );
    if (rect.isEmpty) return;

    var i = 0;
    void f(double v) {
      shader.setFloat(i, v);
      i++;
    }

    f(_cx);
    f(_cy);
    f(_focal);
    f(_camD);
    f(_t * 0.77);
    f(_heatK);
    f(_lavaPower);
    f(const <double>[4.0, 5.0, 5.0][tier]);
    f(_nSlabs.toDouble());
    f(_innerR);
    f(0);
    f(_bobY);
    f(0);
    f(_rockGround);

    // The planes of every slab, in the world.
    for (var s = 0; s < _maxGpuSlabs; s++) {
      if (s < _nSlabs) {
        final slab = _slabs[s];
        final o = s * 9;
        final m0 = _mw[o];
        final m1 = _mw[o + 1];
        final m2 = _mw[o + 2];
        final m3 = _mw[o + 3];
        final m4 = _mw[o + 4];
        final m5 = _mw[o + 5];
        final m6 = _mw[o + 6];
        final m7 = _mw[o + 7];
        final m8 = _mw[o + 8];
        final tx = _wp[s * 3];
        final ty = _wp[s * 3 + 1];
        final tz = _wp[s * 3 + 2];
        for (var k = 0; k < _slotsPerSlab; k++) {
          if (k < slab.count) {
            final nx = slab.planes[k * 4];
            final ny = slab.planes[k * 4 + 1];
            final nz = slab.planes[k * 4 + 2];
            final d = slab.planes[k * 4 + 3];
            final wx = m0 * nx + m1 * ny + m2 * nz;
            final wy = m3 * nx + m4 * ny + m5 * nz;
            final wz = m6 * nx + m7 * ny + m8 * nz;
            f(wx);
            f(wy);
            f(wz);
            f(d + wx * tx + wy * ty + wz * tz);
          } else {
            f(0);
            f(0);
            f(0);
            f(10000);
          }
        }
      } else {
        for (var k = 0; k < _slotsPerSlab; k++) {
          f(0);
          f(0);
          f(0);
          f(10000);
        }
      }
    }

    // Where each slab is, and how big a ball holds it.
    for (var s = 0; s < _maxGpuSlabs; s++) {
      if (s < _nSlabs) {
        f(_wp[s * 3]);
        f(_wp[s * 3 + 1]);
        f(_wp[s * 3 + 2]);
        f(_slabs[s].radius * 1.02);
      } else {
        f(10000);
        f(10000);
        f(10000);
        f(0);
      }
    }

    // The turn that takes a world point back into the closed rock.
    for (var s = 0; s < _maxGpuSlabs; s++) {
      if (s < _nSlabs) {
        _quatFromMat(s * 9);
        f(-_quat[0]);
        f(-_quat[1]);
        f(-_quat[2]);
        f(_quat[3]);
      } else {
        f(0);
        f(0);
        f(0);
        f(1);
      }
    }

    // Its middle in the closed rock, and its own light or dark.
    for (var s = 0; s < _maxGpuSlabs; s++) {
      if (s < _nSlabs) {
        final slab = _slabs[s];
        f(slab.home.x);
        f(slab.home.y);
        f(slab.home.z);
        f(slab.value);
      } else {
        f(0);
        f(0);
        f(0);
        f(0);
      }
    }

    _rockPaint.shader = shader;
    canvas.drawRect(rect, _rockPaint);
  }

  void _quatFromMat(int o) {
    final m = _mw;
    final tr = m[o] + m[o + 4] + m[o + 8];
    double x;
    double y;
    double z;
    double w;
    if (tr > 0) {
      final s = math.sqrt(tr + 1) * 2;
      w = 0.25 * s;
      x = (m[o + 7] - m[o + 5]) / s;
      y = (m[o + 2] - m[o + 6]) / s;
      z = (m[o + 3] - m[o + 1]) / s;
    } else if (m[o] > m[o + 4] && m[o] > m[o + 8]) {
      final s = math.sqrt(1 + m[o] - m[o + 4] - m[o + 8]) * 2;
      w = (m[o + 7] - m[o + 5]) / s;
      x = 0.25 * s;
      y = (m[o + 1] + m[o + 3]) / s;
      z = (m[o + 2] + m[o + 6]) / s;
    } else if (m[o + 4] > m[o + 8]) {
      final s = math.sqrt(1 + m[o + 4] - m[o] - m[o + 8]) * 2;
      w = (m[o + 2] - m[o + 6]) / s;
      x = (m[o + 1] + m[o + 3]) / s;
      y = 0.25 * s;
      z = (m[o + 5] + m[o + 7]) / s;
    } else {
      final s = math.sqrt(1 + m[o + 8] - m[o] - m[o + 4]) * 2;
      w = (m[o + 3] - m[o + 1]) / s;
      x = (m[o + 2] + m[o + 6]) / s;
      y = (m[o + 5] + m[o + 7]) / s;
      z = 0.25 * s;
    }
    _quat[0] = x;
    _quat[1] = y;
    _quat[2] = z;
    _quat[3] = w;
  }

  void _updateNear(double dt, double reachPx) {
    final lerpK = 1 - math.exp(-dt * 11);
    for (var i = 0; i < _pieces.length; i++) {
      final p = _pieces[i];
      var near = 0.0;
      if (_hover > 0.001) {
        final reach = reachPx * (p.kind == 2 ? 1.2 : 1.0);
        final dx = _scrX[i] - _px;
        final dy = _scrY[i] - _py;
        final d = math.sqrt(dx * dx + dy * dy);
        final f = 1 - _clamp(d / math.max(reach, 1.0), 0, 1);
        near = f * f;
        if (near > 0.0001) {
          // From the screen back into the rig's own space.
          final l = math.sqrt(dx * dx + dy * dy);
          double wx;
          double wy;
          double wz;
          if (l < 1e-6) {
            wx = p.dx;
            wy = p.dy;
            wz = p.dz;
          } else {
            final vx = dx / l;
            final vy = -dy / l;
            wx = _rig[0] * vx + _rig[3] * vy;
            wy = _rig[1] * vx + _rig[4] * vy;
            wz = _rig[2] * vx + _rig[5] * vy;
          }
          p.lx += (wx - p.lx) * lerpK;
          p.ly += (wy - p.ly) * lerpK;
          p.lz += (wz - p.lz) * lerpK;
          final len = math.sqrt(p.lx * p.lx + p.ly * p.ly + p.lz * p.lz);
          if (len > 1e-6) {
            p.lx /= len;
            p.ly /= len;
            p.lz /= len;
          }
        }
      }
      p.near = near;
    }
  }

  void _stepPieces(
    int from,
    int to,
    double dt,
    double k,
    double c,
    double strength,
    double released,
  ) {
    for (var i = from; i < to; i++) {
      final p = _pieces[i];
      // A piece still inside its stagger stays where the break left it.
      if (released < p.delay) continue;
      final targetPush = p.near * strength;
      final targetAng = targetPush * p.tilt * 3.4;
      p.pushVel += ((targetPush - p.push) * k - p.pushVel * c) * dt;
      p.push += p.pushVel * dt;
      p.angVel += ((targetAng - p.ang) * k - p.angVel * c) * dt;
      p.ang += p.angVel * dt;
    }
  }

  /// Works out every piece's turn and place in the camera's space.
  void _pose(Meteor w) {
    final repel = _clamp(w.repel, 0, 10) / 10;
    // Even closed, the slabs are held a hair apart: that gap is where the
    // hollow's light gets out.
    const restGap = 0.02;
    for (var i = 0; i < _pieces.length; i++) {
      final p = _pieces[i];
      final off = p.push * (1 - repel) + (p.kind == 0 ? restGap : 0.0);
      final lat = p.push * repel;
      final qx = p.hx + p.dx * off + p.lx * lat;
      final qy = p.hy + p.dy * off + p.ly * lat;
      final qz = p.hz + p.dz * off + p.lz * lat;

      _axisAngleInto(_ma, p.ax, p.ay, p.az, p.ang);
      if (p.free) {
        _eulerInto(_mb, p.sx * _t, p.sy * _t, p.sz * _t);
        _mulInto(_mc, _ma, _mb);
        _mulInto(_md, _mc, p.base);
      } else {
        for (var j = 0; j < 9; j++) {
          _md[j] = _ma[j];
        }
      }
      // world = rig * piece
      final o = i * 9;
      final r = _rig;
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          _mw[o + row * 3 + col] = r[row * 3] * _md[col] +
              r[row * 3 + 1] * _md[3 + col] +
              r[row * 3 + 2] * _md[6 + col];
        }
      }
      final wx = r[0] * qx + r[1] * qy + r[2] * qz;
      final wy = r[3] * qx + r[4] * qy + r[5] * qz + _bobY;
      final wz = r[6] * qx + r[7] * qy + r[8] * qz;
      _wp[i * 3] = wx;
      _wp[i * 3 + 1] = wy;
      _wp[i * 3 + 2] = wz;
      final zc = math.max(_camD - wz, 0.3);
      _scrX[i] = _cx + wx * _focal / zc;
      _scrY[i] = _cy - wy * _focal / zc;
    }
  }

  // ─── Lighting for the shapes and chips ─────────────────────────────────────

  /// A key, a cool fill, the fire's bounce from below, a dim sky, and the
  /// melt in the hollow as a point light. [plate] adds the matte sheen, cool
  /// floor and bevel rim.
  void _light(
    double px,
    double py,
    double pz,
    double nx,
    double ny,
    double nz,
    double ar,
    double ag,
    double ab,
    double ground,
    bool plate,
  ) {
    final key = math.max(nx * _keyX + ny * _keyY + nz * _keyZ, 0.0);
    final fil = math.max(nx * _fillX + ny * _fillY + nz * _fillZ, 0.0);
    final bnc = math.max(nx * _bounceX + ny * _bounceY + nz * _bounceZ, 0.0);
    final up = ny * 0.5 + 0.5;
    final tx = -px;
    final ty = _bobY - py;
    final tz = -pz;
    final d2 = tx * tx + ty * ty + tz * tz;
    final dist = math.sqrt(math.max(d2, 1e-8));
    final ndl = math.max((nx * tx + ny * ty + nz * tz) / dist, 0.0);
    final lp = ndl / (1 + d2 * 3.2) * _lavaPower * 5.5 * ground;
    final gk = ground;
    var r = ar *
        (key * 2.05 +
            fil * 0.2 +
            bnc * _gR * 1.55 * gk +
            (_gR * 0.42 * gk * (1 - up) + 0.078 * up) +
            lp * _lavaR);
    var g = ag *
        (key * 2.05 +
            fil * 0.235 +
            bnc * _gG * 1.55 * gk +
            (_gG * 0.42 * gk * (1 - up) + 0.085 * up) +
            lp * _lavaG);
    var b = ab *
        (key * 2.05 +
            fil * 0.35 +
            bnc * _gB * 1.55 * gk +
            (_gB * 0.42 * gk * (1 - up) + 0.108 * up) +
            lp * _lavaB);
    if (plate) {
      final vx = -px;
      final vy = -py;
      final vz = _camD - pz;
      final vl = math.max(math.sqrt(vx * vx + vy * vy + vz * vz), 1e-6);
      final ivx = vx / vl;
      final ivy = vy / vl;
      final ivz = vz / vl;
      var hx = _keyX + ivx;
      var hy = _keyY + ivy;
      var hz = _keyZ + ivz;
      final hl = math.max(math.sqrt(hx * hx + hy * hy + hz * hz), 1e-6);
      hx /= hl;
      hy /= hl;
      hz /= hl;
      var s = math.max(nx * hx + ny * hy + nz * hz, 0.0);
      for (var q = 0; q < 7; q++) {
        s *= s;
      }
      final sp = s * 0.13;
      final ndv = 1 - math.max(nx * ivx + ny * ivy + nz * ivz, 0.0);
      final n2 = ndv * ndv;
      final rim = n2 * n2 * ndv;
      r += ar * 0.088 + sp + 0.42 * rim * 0.35;
      g += ag * 0.099 + sp + 0.44 * rim * 0.35;
      b += ab * 0.128 + sp + 0.5 * rim * 0.35;
    }
    _lr = r;
    _lg = g;
    _lb = b;
  }

  // ─── Drawing the shapes and chips ──────────────────────────────────────────

  /// Adds one piece's faces that turn toward the viewer, lit.
  void _emit(
    _Mesh m,
    int i,
    double scale,
    double ar,
    double ag,
    double ab,
    double ground,
    bool plate,
    double uOff,
    double vOff,
  ) {
    final o = i * 9;
    final m0 = _mw[o];
    final m1 = _mw[o + 1];
    final m2 = _mw[o + 2];
    final m3 = _mw[o + 3];
    final m4 = _mw[o + 4];
    final m5 = _mw[o + 5];
    final m6 = _mw[o + 6];
    final m7 = _mw[o + 7];
    final m8 = _mw[o + 8];
    final tx = _wp[i * 3];
    final ty = _wp[i * 3 + 1];
    final tz = _wp[i * 3 + 2];

    for (var v = 0; v + 2 < m.count; v += 3) {
      if (_nv + 3 > _maxV) return;
      var ok = true;
      for (var k = 0; k < 3; k++) {
        final j = (v + k) * 3;
        final lx = m.pos[j] * scale;
        final ly = m.pos[j + 1] * scale;
        final lz = m.pos[j + 2] * scale;
        final wx = m0 * lx + m1 * ly + m2 * lz + tx;
        final wy = m3 * lx + m4 * ly + m5 * lz + ty;
        final wz = m6 * lx + m7 * ly + m8 * lz + tz;
        final zc = _camD - wz;
        if (zc < 0.3) {
          ok = false;
          break;
        }
        final s = _focal / zc;
        _tw[k * 3] = wx;
        _tw[k * 3 + 1] = wy;
        _tw[k * 3 + 2] = wz;
        _ts[k * 2] = _cx + wx * s;
        _ts[k * 2 + 1] = _cy - wy * s;
      }
      if (!ok) continue;
      final cross = (_ts[2] - _ts[0]) * (_ts[5] - _ts[1]) -
          (_ts[3] - _ts[1]) * (_ts[4] - _ts[0]);
      if (cross >= 0) continue;

      for (var k = 0; k < 3; k++) {
        final j = (v + k) * 3;
        final lx = m.nor[j];
        final ly = m.nor[j + 1];
        final lz = m.nor[j + 2];
        _light(
          _tw[k * 3],
          _tw[k * 3 + 1],
          _tw[k * 3 + 2],
          m0 * lx + m1 * ly + m2 * lz,
          m3 * lx + m4 * ly + m5 * lz,
          m6 * lx + m7 * ly + m8 * lz,
          ar,
          ag,
          ab,
          ground,
          plate,
        );
        _col[_nv] = _pack(_lr, _lg, _lb);
        _pos[_nv * 2] = _ts[k * 2];
        _pos[_nv * 2 + 1] = _ts[k * 2 + 1];
        _tex[_nv * 2] = m.uv[(v + k) * 2] + uOff;
        _tex[_nv * 2 + 1] = m.uv[(v + k) * 2 + 1] + vOff;
        _nv++;
      }
    }
  }

  void _flush(Canvas canvas, int from, int to) {
    if (to <= from) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, from * 2, to * 2),
      textureCoordinates: Float32List.sublistView(_tex, from * 2, to * 2),
      colors: Int32List.sublistView(_col, from, to),
    );
    canvas.drawVertices(
      vertices,
      ui.BlendMode.modulate,
      _shader != null ? _textured : _plain,
    );
    vertices.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget;

    Widget host = RepaintBoundary(
      child: EffectHost(
        onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
        // A paused meteor still has to redraw while it is being dragged.
        paused: w.paused && !w.dragToRotate,
        interactive: false,
        rotatesOnDrag: false,
        quality: w.quality,
        controller: w.controller,
        background: null,
        semanticLabel: w.semanticLabel,
      ),
    );

    if (!w.dragToRotate && !w.touchPush) return IgnorePointer(child: host);

    if (w.dragToRotate) {
      host = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: host,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onPointer,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: MouseRegion(
        onExit: (_) {
          _pIn = false;
        },
        child: host,
      ),
    );
  }
}

// ─── Small maths ─────────────────────────────────────────────────────────────

class _V3 {
  const _V3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double k) => _V3(x * k, y * k, z * k);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get len2 => x * x + y * y + z * z;
  double get len => math.sqrt(len2);
  _V3 get unit {
    final l = len;
    return l < 1e-12 ? this : this * (1 / l);
  }

  _V3 lerp(_V3 o, double t) =>
      _V3(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);
}

double _clamp(double v, double lo, double hi) {
  final safe = v.isFinite ? v : lo;
  return math.min(hi, math.max(lo, safe));
}

double _smooth(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a == 0 ? 1.0 : b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

int _tier(EffectQuality q) => switch (q) {
      EffectQuality.low => 0,
      EffectQuality.medium => 1,
      EffectQuality.high => 2,
    };

List<double> _lin(Color c) {
  double f(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return <double>[f(c.r), f(c.g), f(c.b)];
}

int _tone(double x) {
  if (x.isNaN || x <= 0) return 0;
  if (x.isInfinite) return 255;
  final v = x * _exposure;
  final y = (v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14);
  return (math.sqrt(y > 1 ? 1.0 : y) * 255).round();
}

int _pack(double r, double g, double b) =>
    (255 << 24) | (_tone(r) << 16) | (_tone(g) << 8) | _tone(b);

_V3 _randomDir(math.Random rng) {
  final z = rng.nextDouble() * 2 - 1;
  final a = rng.nextDouble() * _tau;
  final r = math.sqrt(math.max(0.0, 1 - z * z));
  return _V3(math.cos(a) * r, math.sin(a) * r, z);
}

void _randomRotation(math.Random rng, Float64List m) {
  final u = rng.nextDouble();
  final v = rng.nextDouble() * _tau;
  final w = rng.nextDouble() * _tau;
  final a = math.sqrt(1 - u);
  final b = math.sqrt(u);
  final x = a * math.sin(v);
  final y = a * math.cos(v);
  final z = b * math.sin(w);
  final q = b * math.cos(w);
  m[0] = 1 - 2 * (y * y + z * z);
  m[1] = 2 * (x * y - z * q);
  m[2] = 2 * (x * z + y * q);
  m[3] = 2 * (x * y + z * q);
  m[4] = 1 - 2 * (x * x + z * z);
  m[5] = 2 * (y * z - x * q);
  m[6] = 2 * (x * z - y * q);
  m[7] = 2 * (y * z + x * q);
  m[8] = 1 - 2 * (x * x + y * y);
}

void _axisAngleInto(Float64List m, double ax, double ay, double az, double a) {
  final c = math.cos(a);
  final s = math.sin(a);
  final t = 1 - c;
  m[0] = t * ax * ax + c;
  m[1] = t * ax * ay - s * az;
  m[2] = t * ax * az + s * ay;
  m[3] = t * ax * ay + s * az;
  m[4] = t * ay * ay + c;
  m[5] = t * ay * az - s * ax;
  m[6] = t * ax * az - s * ay;
  m[7] = t * ay * az + s * ax;
  m[8] = t * az * az + c;
}

/// Rotation about x, then y, then z, the same order as three.js uses.
void _eulerInto(Float64List m, double x, double y, double z) {
  final a = math.cos(x);
  final b = math.sin(x);
  final c = math.cos(y);
  final d = math.sin(y);
  final e = math.cos(z);
  final f = math.sin(z);
  final ae = a * e;
  final af = a * f;
  final be = b * e;
  final bf = b * f;
  m[0] = c * e;
  m[1] = -c * f;
  m[2] = d;
  m[3] = af + be * d;
  m[4] = ae - bf * d;
  m[5] = -b * c;
  m[6] = bf - ae * d;
  m[7] = be + af * d;
  m[8] = a * c;
}

void _mulInto(Float64List out, Float64List a, Float64List b) {
  final r0 = a[0] * b[0] + a[1] * b[3] + a[2] * b[6];
  final r1 = a[0] * b[1] + a[1] * b[4] + a[2] * b[7];
  final r2 = a[0] * b[2] + a[1] * b[5] + a[2] * b[8];
  final r3 = a[3] * b[0] + a[4] * b[3] + a[5] * b[6];
  final r4 = a[3] * b[1] + a[4] * b[4] + a[5] * b[7];
  final r5 = a[3] * b[2] + a[4] * b[5] + a[5] * b[8];
  final r6 = a[6] * b[0] + a[7] * b[3] + a[8] * b[6];
  final r7 = a[6] * b[1] + a[7] * b[4] + a[8] * b[7];
  final r8 = a[6] * b[2] + a[7] * b[5] + a[8] * b[8];
  out[0] = r0;
  out[1] = r1;
  out[2] = r2;
  out[3] = r3;
  out[4] = r4;
  out[5] = r5;
  out[6] = r6;
  out[7] = r7;
  out[8] = r8;
}

// ─── Meshes for the shapes and chips ─────────────────────────────────────────

/// Triangles in a flat list: positions, normals and picture coordinates,
/// three vertices a face.
class _Mesh {
  _Mesh(this.pos, this.nor, this.uv, this.count);

  final Float32List pos;
  final Float32List nor;
  final Float32List uv;
  final int count;
}

/// Collects triangles, turning each so it faces the way its normals say.
class _MeshBuilder {
  final List<double> pos = <double>[];
  final List<double> nor = <double>[];

  void tri(_V3 a, _V3 b, _V3 c, _V3 na, _V3 nb, _V3 nc) {
    final g = (b - a).cross(c - a);
    if (g.len2 < 1e-14) return;
    final flip = g.dot(na + nb + nc) < 0;
    final v = flip ? <_V3>[a, c, b] : <_V3>[a, b, c];
    final n = flip ? <_V3>[nc, nb, na] : <_V3>[na, nb, nc];
    for (var i = 0; i < 3; i++) {
      pos.addAll(<double>[v[i].x, v[i].y, v[i].z]);
      nor.addAll(<double>[n[i].x, n[i].y, n[i].z]);
    }
  }

  /// A flat face, facing away from the origin.
  void flat(_V3 a, _V3 b, _V3 c) {
    var n = (b - a).cross(c - a);
    if (n.len2 < 1e-14) return;
    n = n.unit;
    final mid = (a + b + c) * (1 / 3);
    if (n.dot(mid) < 0) n = n * -1;
    tri(a, b, c, n, n, n);
  }

  void quad(_V3 a, _V3 b, _V3 c, _V3 d) {
    flat(a, b, c);
    flat(a, c, d);
  }

  /// Plain white coordinates: one exact white texel in the rock picture.
  _Mesh plain() {
    final count = pos.length ~/ 3;
    final uv = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      uv[i * 2] = 0.5;
      uv[i * 2 + 1] = 0.5;
    }
    return _Mesh(Float32List.fromList(pos), Float32List.fromList(nor), uv, count);
  }

  /// Rock coordinates for a chip, mapped from its own shape.
  _Mesh rocky() {
    final count = pos.length ~/ 3;
    final uv = Float32List(count * 2);
    for (var i = 0; i < count; i += 3) {
      final nx = nor[i * 3].abs();
      final ny = nor[i * 3 + 1].abs();
      final nz = nor[i * 3 + 2].abs();
      for (var k = 0; k < 3; k++) {
        final j = (i + k) * 3;
        double u;
        double v;
        if (nx >= ny && nx >= nz) {
          u = pos[j + 1];
          v = pos[j + 2];
        } else if (ny >= nz) {
          u = pos[j];
          v = pos[j + 2];
        } else {
          u = pos[j];
          v = pos[j + 1];
        }
        uv[(i + k) * 2] = u * 60;
        uv[(i + k) * 2 + 1] = v * 60;
      }
    }
    return _Mesh(Float32List.fromList(pos), Float32List.fromList(nor), uv, count);
  }
}

_Mesh _buildShape(MeteorShape shape, double thickness, int tier) {
  final depth = 0.015 + _clamp(thickness, 0, 10) / 10 * 0.1034;
  final b = _MeshBuilder();
  switch (shape) {
    case MeteorShape.plus:
      _plusMesh(b, depth, tier > 0);
    case MeteorShape.torus:
      _torusMesh(b, depth, const <int>[8, 12, 16][tier], const <int>[5, 6, 8][tier]);
    case MeteorShape.cylinder:
      _cylinderMesh(b, depth, const <int>[8, 12, 16][tier]);
    case MeteorShape.box:
      const h = 0.28;
      final v = <_V3>[
        for (final x in <double>[-h, h])
          for (final y in <double>[-h, h])
            for (final z in <double>[-h, h]) _V3(x, y, z),
      ];
      // Corners are numbered x, y, z in binary.
      for (final f in const <List<int>>[
        <int>[0, 1, 3, 2],
        <int>[4, 6, 7, 5],
        <int>[0, 4, 5, 1],
        <int>[2, 3, 7, 6],
        <int>[0, 2, 6, 4],
        <int>[1, 5, 7, 3],
      ]) {
        b.quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]]);
      }
    case MeteorShape.octahedron:
      const r = 0.3;
      const hgt = 0.5;
      const top = _V3(0, hgt, 0);
      const bot = _V3(0, -hgt, 0);
      const ring = <_V3>[_V3(r, 0, 0), _V3(0, 0, r), _V3(-r, 0, 0), _V3(0, 0, -r)];
      for (var i = 0; i < 4; i++) {
        final c = ring[i];
        final d = ring[(i + 1) % 4];
        b.flat(top, c, d);
        b.flat(bot, d, c);
      }
  }
  return b.plain();
}

/// An extruded plus with a sliver of chamfer on every edge.
void _plusMesh(_MeshBuilder m, double depth, bool bevel) {
  const arm = 0.5;
  const waist = 1 / 6;
  final t = math.max(0.004, depth);
  final bv = bevel ? math.min(0.016, t * 0.35) : 0.0;

  List<List<double>> outline(double a, double w) => <List<double>>[
        <double>[w, a],
        <double>[w, w],
        <double>[a, w],
        <double>[a, -w],
        <double>[w, -w],
        <double>[w, -a],
        <double>[-w, -a],
        <double>[-w, -w],
        <double>[-a, -w],
        <double>[-a, w],
        <double>[-w, w],
        <double>[-w, a],
      ];

  final ai = arm - bv;
  final wi = waist - bv;
  final rects = <List<double>>[
    <double>[-wi, wi, -ai, ai],
    <double>[-ai, -wi, -wi, wi],
    <double>[wi, ai, -wi, wi],
  ];
  for (final z in <double>[t, -t]) {
    for (final r in rects) {
      m.quad(_V3(r[0], r[2], z), _V3(r[1], r[2], z), _V3(r[1], r[3], z), _V3(r[0], r[3], z));
    }
  }
  final outer = outline(arm, waist);
  final inner = outline(ai, wi);
  final zs = t - bv;
  for (var i = 0; i < outer.length; i++) {
    final a = outer[i];
    final b = outer[(i + 1) % outer.length];
    m.quad(_V3(a[0], a[1], -zs), _V3(b[0], b[1], -zs), _V3(b[0], b[1], zs), _V3(a[0], a[1], zs));
    if (bv > 0) {
      final u0 = inner[i];
      final u1 = inner[(i + 1) % inner.length];
      m.quad(_V3(a[0], a[1], zs), _V3(b[0], b[1], zs), _V3(u1[0], u1[1], t), _V3(u0[0], u0[1], t));
      m.quad(_V3(b[0], b[1], -zs), _V3(a[0], a[1], -zs), _V3(u0[0], u0[1], -t), _V3(u1[0], u1[1], -t));
    }
  }
}

void _torusMesh(_MeshBuilder m, double depth, int nu, int nv) {
  final tube = 0.05 + depth;
  final ring = 0.5 - tube;
  _V3 point(int i, int j) {
    final u = _tau * i / nu;
    final v = _tau * j / nv;
    final r = ring + tube * math.cos(v);
    return _V3(r * math.cos(u), r * math.sin(u), tube * math.sin(v));
  }

  _V3 normal(int i, int j) {
    final u = _tau * i / nu;
    final v = _tau * j / nv;
    return _V3(math.cos(v) * math.cos(u), math.cos(v) * math.sin(u), math.sin(v));
  }

  for (var i = 0; i < nu; i++) {
    for (var j = 0; j < nv; j++) {
      final i1 = (i + 1) % nu;
      final j1 = (j + 1) % nv;
      m.tri(point(i, j), point(i1, j), point(i, j1), normal(i, j), normal(i1, j), normal(i, j1));
      m.tri(point(i1, j), point(i1, j1), point(i, j1), normal(i1, j), normal(i1, j1), normal(i, j1));
    }
  }
}

void _cylinderMesh(_MeshBuilder m, double depth, int n) {
  const r = 0.3;
  final h = 0.06 + depth * 1.8;
  const up = _V3(0, 0, 1);
  const down = _V3(0, 0, -1);
  for (var i = 0; i < n; i++) {
    final a0 = _tau * i / n;
    final a1 = _tau * (i + 1) / n;
    final c0 = _V3(math.cos(a0), math.sin(a0), 0);
    final c1 = _V3(math.cos(a1), math.sin(a1), 0);
    final p00 = _V3(c0.x * r, c0.y * r, -h);
    final p01 = _V3(c0.x * r, c0.y * r, h);
    final p10 = _V3(c1.x * r, c1.y * r, -h);
    final p11 = _V3(c1.x * r, c1.y * r, h);
    m.tri(p00, p10, p01, c0, c1, c0);
    m.tri(p10, p11, p01, c1, c1, c0);
    m.tri(_V3(0, 0, h), p01, p11, up, up, up);
    m.tri(_V3(0, 0, -h), p10, p00, down, down, down);
  }
}

/// A rock chip: an icosahedron with every corner moved, once.
_Mesh _buildDebris() {
  final t = (1 + math.sqrt(5)) / 2;
  final raw = <_V3>[
    _V3(-1, t, 0),
    _V3(1, t, 0),
    _V3(-1, -t, 0),
    _V3(1, -t, 0),
    _V3(0, -1, t),
    _V3(0, 1, t),
    _V3(0, -1, -t),
    _V3(0, 1, -t),
    _V3(t, 0, -1),
    _V3(t, 0, 1),
    _V3(-t, 0, -1),
    _V3(-t, 0, 1),
  ];
  final rng = math.Random(0x27d4eb2f);
  final v = <_V3>[
    for (final p in raw)
      p.unit * (0.58 + rng.nextDouble() * 0.62) +
          _V3(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5, rng.nextDouble() - 0.5) * 0.26,
  ];
  const faces = <List<int>>[
    <int>[0, 11, 5], <int>[0, 5, 1], <int>[0, 1, 7], <int>[0, 7, 10], <int>[0, 10, 11],
    <int>[1, 5, 9], <int>[5, 11, 4], <int>[11, 10, 2], <int>[10, 7, 6], <int>[7, 1, 8],
    <int>[3, 9, 4], <int>[3, 4, 2], <int>[3, 2, 6], <int>[3, 6, 8], <int>[3, 8, 9],
    <int>[4, 9, 5], <int>[2, 4, 11], <int>[6, 2, 10], <int>[8, 6, 7], <int>[9, 8, 1],
  ];
  final b = _MeshBuilder();
  for (final f in faces) {
    b.flat(v[f[0]], v[f[1]], v[f[2]]);
  }
  return b.rocky();
}

// ─── The rock: slabs cut from a ball ─────────────────────────────────────────
// Each slab is the faceted ball clipped by the bisector against every other
// seed, and hollowed out. Neighbours are clipped by the same plane, so they
// share a face exactly and the closed rock has no gaps. The slab is kept as
// its planes, which is all the rock shader needs.

class _Face {
  _Face(this.n, this.pts);

  final _V3 n;
  final List<_V3> pts;
}

class _Plane {
  _Plane(this.n, this.d);

  final _V3 n;
  final double d;
}

class _Slab {
  _Slab(this.planes, this.count, this.home, this.dir, this.value, this.radius);

  /// Normal and offset of each plane, in the slab's own space.
  final Float32List planes;
  final int count;

  /// Where the slab sits in the closed rock.
  final _V3 home;
  final _V3 dir;

  /// How pale or dark this slab is, from 0 to 1.
  final double value;

  /// The radius of a ball round its middle that holds all of it.
  final double radius;
}

class _Husk {
  _Husk(this.slabs, this.inner);

  final List<_Slab> slabs;
  final double inner;
}

const double _clipEps = 1e-7;

List<_Face> _boxFaces(double h) {
  _V3 v(double x, double y, double z) => _V3(x, y, z);
  return <_Face>[
    _Face(v(1, 0, 0), <_V3>[v(h, -h, -h), v(h, h, -h), v(h, h, h), v(h, -h, h)]),
    _Face(v(-1, 0, 0), <_V3>[v(-h, -h, h), v(-h, h, h), v(-h, h, -h), v(-h, -h, -h)]),
    _Face(v(0, 1, 0), <_V3>[v(-h, h, -h), v(-h, h, h), v(h, h, h), v(h, h, -h)]),
    _Face(v(0, -1, 0), <_V3>[v(-h, -h, h), v(-h, -h, -h), v(h, -h, -h), v(h, -h, h)]),
    _Face(v(0, 0, 1), <_V3>[v(-h, -h, h), v(h, -h, h), v(h, h, h), v(-h, h, h)]),
    _Face(v(0, 0, -1), <_V3>[v(h, -h, -h), v(-h, -h, -h), v(-h, h, -h), v(h, h, -h)]),
  ];
}

/// Keeps the half-space dot(p, n) <= d.
List<_Face> _clip(List<_Face> faces, _V3 n, double d) {
  final out = <_Face>[];
  final cut = <_V3>[];
  for (final f in faces) {
    final pts = f.pts;
    final m = pts.length;
    final kept = <_V3>[];
    for (var i = 0; i < m; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % m];
      final da = a.dot(n) - d;
      final db = b.dot(n) - d;
      if (da <= _clipEps) kept.add(a);
      if ((da < -_clipEps && db > _clipEps) || (da > _clipEps && db < -_clipEps)) {
        final p = a.lerp(b, da / (da - db));
        kept.add(p);
        cut.add(p);
      }
    }
    if (kept.length >= 3) out.add(_Face(f.n, kept));
  }
  if (cut.length >= 3) {
    // The cut edges come in no order, so the cap is rebuilt by angle round
    // its own middle.
    var c = const _V3(0, 0, 0);
    for (final p in cut) {
      c = c + p;
    }
    c = c * (1 / cut.length);
    final helper = n.x.abs() < 0.9 ? const _V3(1, 0, 0) : const _V3(0, 1, 0);
    final u = n.cross(helper).unit;
    final w = n.cross(u);
    final ranked = <(_V3, double)>[
      for (final p in cut) (p, math.atan2((p - c).dot(w), (p - c).dot(u))),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final ring = <_V3>[];
    for (final r in ranked) {
      if (ring.isEmpty || (ring.last - r.$1).len2 > 1e-12) ring.add(r.$1);
    }
    if (ring.length >= 3 && (ring.first - ring.last).len2 < 1e-12) ring.removeLast();
    if (ring.length >= 3) out.add(_Face(n, ring));
  }
  return out;
}

List<_V3> _fibonacci(int n) {
  final out = <_V3>[];
  final golden = math.pi * (3 - math.sqrt(5));
  for (var i = 0; i < n; i++) {
    final y = 1 - (i / math.max(1, n - 1)) * 2;
    final r = math.sqrt(math.max(0.0, 1 - y * y));
    final th = golden * i;
    out.add(_V3(math.cos(th) * r, y, math.sin(th) * r));
  }
  return out;
}

double _faceArea(_Face f) {
  var sum = const _V3(0, 0, 0);
  for (var k = 1; k + 1 < f.pts.length; k++) {
    sum = sum + (f.pts[k] - f.pts[0]).cross(f.pts[k + 1] - f.pts[0]);
  }
  return sum.len * 0.5;
}

_Husk _buildHusk(int shards, double irregularity, double thickness) {
  final rng = math.Random(7);
  double rnd() => rng.nextDouble();
  final count = math.max(3, math.min(_maxShards, shards));
  final irr = _clamp(irregularity, 0, 10) / 10;
  final inner = 0.62 + (0.28 - 0.62) * (_clamp(thickness, 0, 10) / 10);
  final amp = 0.06 + irr * 0.42;

  // The faceted ball every slab is cut from.
  final hull = <_Plane>[];
  for (final dir in _fibonacci(_hullPlanes)) {
    hull.add(_Plane(dir, 1 - amp * 0.5 + rnd() * amp));
  }

  // Seeds jittered in direction and radius, so the slabs come out unequal.
  final spread = 0.15 + irr * 0.45;
  final seeds = <_V3>[];
  for (final dir in _fibonacci(count)) {
    final jitter = _V3(rnd() - 0.5, rnd() - 0.5, rnd() - 0.5) * spread;
    seeds.add((dir + jitter).unit * (0.7 + rnd() * 0.5));
  }

  final slabs = <_Slab>[];
  for (var i = 0; i < seeds.length; i++) {
    final si = seeds[i];
    final axis = si.unit;
    var faces = _boxFaces(2.4);
    for (final h in hull) {
      faces = _clip(faces, h.n, h.d);
    }
    for (var j = 0; j < seeds.length; j++) {
      if (j == i) continue;
      final dv = seeds[j] - si;
      final len = dv.len;
      if (len < 1e-6) continue;
      final n = dv * (1 / len);
      final mid = (seeds[j] + si) * 0.5;
      faces = _clip(faces, n, mid.dot(n));
    }
    // Hollow: keep dot(p, axis) >= inner.
    faces = _clip(faces, axis * -1, -inner);
    if (faces.length < 4) continue;

    var centroid = const _V3(0, 0, 0);
    var cnt = 0;
    for (final f in faces) {
      for (final p in f.pts) {
        centroid = centroid + p;
        cnt++;
      }
    }
    if (cnt == 0) continue;
    centroid = centroid * (1 / cnt);

    // The biggest faces, as planes in the slab's own space.
    final ranked = <(double, _Face)>[
      for (final f in faces) (_faceArea(f), f),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final keep = math.min(ranked.length, _slotsPerSlab);
    final planes = Float32List(keep * 4);
    for (var q = 0; q < keep; q++) {
      final f = ranked[q].$2;
      planes[q * 4] = f.n.x;
      planes[q * 4 + 1] = f.n.y;
      planes[q * 4 + 2] = f.n.z;
      planes[q * 4 + 3] = f.n.dot(f.pts.first) - f.n.dot(centroid);
    }

    var radius = 0.0;
    for (final f in faces) {
      for (final p in f.pts) {
        radius = math.max(radius, (p - centroid).len);
      }
    }

    slabs.add(_Slab(planes, keep, centroid, centroid.unit, rnd(), radius));
  }
  return _Husk(slabs, inner);
}

// ─── The chips' picture ──────────────────────────────────────────────────────

Future<ui.Image>? _rockFuture;

double _hash2(int i, int j, int s) {
  final v = math.sin(i * 127.1 + j * 311.7 + s * 74.7) * 43758.5453;
  return v - v.floorToDouble();
}

/// Value noise that repeats every [per] cells, so the picture tiles.
double _tnoise(double x, double y, int per, int s) {
  final px = x * per;
  final py = y * per;
  final ix = px.floor();
  final iy = py.floor();
  final fx = px - ix;
  final fy = py - iy;
  final u = fx * fx * (3 - 2 * fx);
  final v = fy * fy * (3 - 2 * fy);
  double lat(int a, int b) => _hash2(a % per, b % per, s);
  final a = lat(ix, iy);
  final b = lat(ix + 1, iy);
  final c = lat(ix, iy + 1);
  final d = lat(ix + 1, iy + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/// Basalt as a brightness map for the chips: dark char with pale plates on
/// about a quarter of it, and a fine grain. Its first pixel is pure white,
/// which is what the swarm's colours are read from.
Future<ui.Image> _makeRock() {
  const n = _tile;
  final pixels = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final fx = x / n;
      final fy = y / n;
      final coarse = 0.5 * _tnoise(fx, fy, 2, 11) +
          0.3 * _tnoise(fx, fy, 4, 12) +
          0.2 * _tnoise(fx, fy, 8, 13);
      final grain = 0.45 * _tnoise(fx, fy, 16, 21) +
          0.3 * _tnoise(fx, fy, 32, 22) +
          0.25 * _tnoise(fx, fy, 64, 23);
      final plate = _smooth(0.50, 0.70, coarse + (grain - 0.5) * 0.28);
      final t = (0.15 + 0.85 * plate) * (0.72 + 0.28 * grain);
      var g = (_clamp(t * 1.1, 0, 1) * 255).round();
      if (x == 0 && y == 0) g = 255;
      final o = (y * n + x) * 4;
      pixels[o] = g;
      pixels[o + 1] = g;
      pixels[o + 2] = g;
      pixels[o + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    n,
    n,
    ui.PixelFormat.rgba8888,
    (image) => completer.complete(image),
  );
  return completer.future;
}