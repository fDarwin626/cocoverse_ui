import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';
import 'link_chain_motion.dart';
import 'link_chain_rope.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/link_chain.frag';

// The original's camera lens, 1 / tan(half the field of view).
const double _lens = 2.35;

// Physics runs in fixed steps, whatever the frame rate.
const double _subDt = 1 / 90;
const int _maxSubSteps = 3;
const int _warmupSteps = 120;

// How fast and how far the two ends wander, as in the original.
const double _swayRate = 0.39;
const double _swayAmp = 0.04;

// A link covers few pixels on a phone, so grabbing it needs a target at least
// this many logical pixels across.
const double _touchTarget = 22;

const int _groupSize = 4;
const int _maxPalette = 16;

/// The candy colours of the original, in the order they follow each other.
const List<Color> _defaultColors = <Color>[
  Color(0xFFF0521E),
  Color(0xFFEFE2C3),
  Color(0xFF1B4BE0),
  Color(0xFF0E6B22),
  Color(0xFFB9BEF2),
  Color(0xFFE8A317),
  Color(0xFF2A0B33),
  Color(0xFFF03CB4),
  Color(0xFFFF7A70),
  Color(0xFFA9AEC0),
  Color(0xFF9E1226),
];

/// How a [LinkChain] is painted.
enum LinkChainFinish {
  /// Flat colour bands with an ink outline, like a drawing.
  cartoon,

  /// Polished metal that reflects a studio, and darkens where links meet.
  metallic,
}

/// A chain of interlocked links hanging between two points on real rope
/// physics.
///
/// It hangs from the edges of the space it is given, so you control how long it
/// is by sizing the widget, and how far it sags with [slack]. Gravity always
/// pulls down, like a real chain, and with [reactToMotion] it follows the phone
/// when it is tilted or shaken. You can grab a link and swing it. When it first
/// appears it is lowered into place, once.
///
/// ```dart
/// SizedBox(
///   height: 120,
///   child: LinkChain(finish: LinkChainFinish.metallic, slack: 0.12),
/// )
/// ```
class LinkChain extends StatefulWidget {
  /// Creates a hanging chain.
  const LinkChain({
    super.key,
    this.finish = LinkChainFinish.cartoon,
    this.colors,
    this.metalColor = const Color(0xFFC7CAD1),
    this.background,
    this.start = Alignment.topLeft,
    this.end = Alignment.topRight,
    this.span = 1.0,
    this.slack = 0.10,
    this.density = 22,
    this.linkLength = 58.0,
    this.linkThickness = 36.0,
    this.outline = 0.3,
    this.sway = 100.0,
    this.speed = 1.0,
    this.drift = 1.0,
    this.drag = 60.0,
    this.entrance = true,
    this.entranceDuration = const Duration(milliseconds: 1100),
    this.reactToMotion = true,
    this.motionQuarterTurns = 0,
    this.pinned = true,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// Cartoon or metallic.
  final LinkChainFinish finish;

  /// Colours the links take, in order, for the cartoon finish. Any number from
  /// 1 to 16 works and they form a ring. If null, the candy colours of the
  /// original are used.
  final List<Color>? colors;

  /// Colour of the metal for the metallic finish. Steel by default, gold or
  /// copper work well too.
  final Color metalColor;

  /// Fill behind the chain. Null means transparent.
  final Color? background;

  /// Where the first end is fixed, inside the widget's box.
  final Alignment start;

  /// Where the second end is fixed, inside the widget's box.
  final Alignment end;

  /// How much of the distance between [start] and [end] the chain covers, from
  /// 0.1 to 1.0. Less than 1 shortens it toward the middle.
  final double span;

  /// How saggy it hangs, from 0.02 (nearly tight) to 1.5 (a deep loop). It is
  /// the extra chain length as a share of the distance it spans.
  final double slack;

  /// Number of links, 12 to 40. The links grow or shrink to fill the span.
  final int density;

  /// How long each link is, from 0 to 100. 58 matches the original.
  final double linkLength;

  /// How thick the metal of each link is, from 0 to 100. 36 matches the
  /// original.
  final double linkThickness;

  /// Thickness of the ink line in the cartoon finish, from 0 to 1.
  final double outline;

  /// How far the two ends wander, from 0 to 200 percent. 0 hangs dead still.
  final double sway;

  /// How fast the ends wander. 1.0 matches the original, 0 stops them.
  final double speed;

  /// How fast the colours slide along the chain in the cartoon finish. 0 holds
  /// them still.
  final double drift;

  /// How hard a grabbed link is pulled toward your finger, from 0 to 100.
  /// 0 turns grabbing off.
  final double drag;

  /// Whether the chain is lowered into place when it first appears. It plays
  /// once, and again when the controller is reset.
  final bool entrance;

  /// How long the entrance takes.
  final Duration entranceDuration;

  /// Whether the chain follows the phone when it is tilted or shaken. Where
  /// there is no motion sensor the chain just hangs down.
  final bool reactToMotion;

  /// Quarter turns of the screen away from upright, for apps that rotate. One
  /// is a quarter turn anticlockwise.
  final int motionQuarterTurns;

  /// Whether the two ends are fixed. Set it to false and the chain lets go and
  /// falls.
  final bool pinned;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the chain.
  final bool interactive;

  /// Level of detail. Lower settings take fewer steps per pixel, and the
  /// metallic finish drops its occlusion and its reflection of the chain
  /// itself.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] plays the entrance again.
  final EffectController? controller;

  /// Screen-reader description. Null marks the chain as decorative.
  final String? semanticLabel;

  @override
  State<LinkChain> createState() => _LinkChainState();
}

class _LinkChainState extends State<LinkChain> {
  ui.FragmentShader? _shader;
  Paint? _paint;

  // The settings last written to the shader. They only change when the widget
  // is rebuilt, so they are written once and not on every frame.
  _Settings? _applied;

  LinkChainRope? _rope;
  int _ropeLinks = -1;
  double _ropeLength = -1;
  double _ropeThickness = -1;
  bool _playEntrance = true;
  bool _entering = false;
  double _entranceTime = 0;
  bool _released = false;

  double _lastTime = 0;
  double _accumulated = 0;
  double _swayPhase = 0;
  double _slide = 0;
  int _seenResets = 0;
  bool _usingMotion = false;

  // Where the chain is on screen, kept so touch can be turned into a ray.
  double _scale = 1;
  double _camX = 0;
  double _camY = 0;
  double _camZ = 1;

  // Grab state.
  bool _wasPressed = false;
  int _grabbed = -1;
  double _grabDepth = 0;
  double _grabX = 0;
  double _grabY = 0;
  double _grabZ = 0;

  // Buffers the shader reads, filled once per frame.
  final Float64List _frameA = Float64List(maxLinkCount * 4);
  final Float64List _frameB = Float64List(maxLinkCount * 4);
  final Float64List _frameC = Float64List(maxLinkCount * 4);
  final Float64List _groups = Float64List((maxLinkCount ~/ _groupSize) * 4);

  @override
  void initState() {
    super.initState();
    _playEntrance = widget.entrance;
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
    _syncMotion();
    _loadShader();
  }

  @override
  void didUpdateWidget(LinkChain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _seenResets = widget.controller?.resetCount ?? 0;
    }
    _syncMotion();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    if (_usingMotion) LinkChainMotion.instance.detach();
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ShaderLibrary.load(_shaderAsset);
      if (!mounted) return;
      final shader = program.fragmentShader();
      setState(() {
        _shader = shader;
        _paint = Paint()..shader = shader;
        _applied = null;
      });
    } catch (error) {
      debugPrint('LinkChain: could not load its shader: $error');
    }
  }

  void _syncMotion() {
    if (widget.reactToMotion && !_usingMotion) {
      _usingMotion = true;
      LinkChainMotion.instance.attach();
    } else if (!widget.reactToMotion && _usingMotion) {
      _usingMotion = false;
      LinkChainMotion.instance.detach();
    }
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      // A reset builds the chain again, and lowers it again.
      _rope = null;
      _playEntrance = widget.entrance;
      _released = false;
      _grabbed = -1;
      _lastTime = 0;
      _accumulated = 0;
    }
  }

  /// The gravity the chain feels, in link radii per second squared.
  Offset _pull(_Settings s) {
    final down = widget.reactToMotion
        ? rotateGravity(LinkChainMotion.instance.gravity.value, s.quarterTurns)
        : const Offset(0, -1);
    return Offset(down.dx * ropeGravity, down.dy * ropeGravity);
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame, _Settings s) {
    if (size.isEmpty) return;

    final rope = _ensureRope(s);
    final layout = _Layout.of(size, s, rope);
    if (layout == null) return;
    _scale = layout.scale;
    _camX = layout.camX;
    _camY = layout.camY;
    _camZ = layout.camZ;

    if (frame.time < _lastTime) _lastTime = 0;
    final dt = frame.time - _lastTime;
    _lastTime = frame.time;

    _seedIfNeeded(rope, layout, s);
    _updateGrab(frame, size, s, rope);
    _simulate(dt, rope, layout, s);

    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null) return;
    if (!identical(_applied, s)) {
      _applyStatic(shader, s);
      _applied = s;
    }
    _draw(canvas, size, rope, layout, shader, paint, s);
  }

  LinkChainRope _ensureRope(_Settings s) {
    final existing = _rope;
    if (existing != null &&
        s.links == _ropeLinks &&
        s.linkLength == _ropeLength &&
        s.linkThickness == _ropeThickness) {
      return existing;
    }
    _ropeLinks = s.links;
    _ropeLength = s.linkLength;
    _ropeThickness = s.linkThickness;
    final rope = LinkChainRope(
      links: s.links,
      linkLength: s.linkLength,
      linkThickness: s.linkThickness,
    );
    _rope = rope;
    _needsSeed = true;
    return rope;
  }

  bool _needsSeed = true;

  void _seedIfNeeded(LinkChainRope rope, _Layout layout, _Settings s) {
    if (!_needsSeed) return;
    _needsSeed = false;
    _grabbed = -1;
    _released = false;
    final gap = layout.gap(rope, s);
    if (_playEntrance && s.entrance) {
      _playEntrance = false;
      _entering = true;
      _entranceTime = 0;
      final start = layout.entranceAnchors(rope, s, 0);
      rope.seedStraight(start[0], start[1], 0.0, start[2], start[3], 0.0);
    } else {
      _playEntrance = false;
      _entering = false;
      final a = layout.anchors(gap);
      rope.seedHanging(a[0], a[1], 0.0, a[2], a[3], 0.0);
      final pull = _pull(s);
      for (var i = 0; i < _warmupSteps; i++) {
        rope.step(
          _subDt,
          ax0: a[0],
          ay0: a[1],
          az0: 0.0,
          ax1: a[2],
          ay1: a[3],
          az1: 0.0,
          gx: pull.dx,
          gy: pull.dy,
        );
      }
    }
  }

  void _simulate(double dt, LinkChainRope rope, _Layout layout, _Settings s) {
    if (dt <= 0) return;
    _swayPhase += dt * _swayRate * s.speed;
    _slide += dt * 0.02 * s.drift;
    final pull = _pull(s);
    final pinned = widget.pinned;
    if (!pinned) _released = true;
    if (pinned && _released) {
      // Pinned again after a fall: lower it in once more.
      _released = false;
      _playEntrance = widget.entrance;
      _needsSeed = true;
      return;
    }

    _accumulated += dt;
    var steps = 0;
    while (_accumulated >= _subDt && steps < _maxSubSteps) {
      if (_released) {
        rope.stepFree(_subDt, gx: pull.dx, gy: pull.dy);
      } else {
        double e = 1;
        if (_entering) {
          _entranceTime += _subDt;
          final t = math.min(1.0, _entranceTime / s.entranceSeconds);
          e = t * t * (3 - 2 * t);
          if (t >= 1) _entering = false;
        }
        final a = e < 1
            ? layout.entranceAnchors(rope, s, e)
            : layout.anchors(layout.gap(rope, s));
        final amp = rope.ropeLength * _swayAmp * (s.sway / 100);
        final tt = _swayPhase;
        rope.step(
          _subDt,
          ax0: a[0] + amp * math.sin(tt * 0.9),
          ay0: a[1],
          az0: amp * 0.85 * math.sin(tt * 0.61 + 1.1),
          ax1: a[2] + amp * math.sin(tt * 0.77 + 2.0),
          ay1: a[3],
          az1: amp * 0.95 * math.sin(tt * 1.3 + 0.4),
          gx: pull.dx,
          gy: pull.dy,
          grab: _grabbed,
          grabX: _grabX,
          grabY: _grabY,
          grabZ: _grabZ,
          grabPull: s.grabPull,
        );
      }
      _accumulated -= _subDt;
      steps++;
    }
    if (_accumulated > _subDt * _maxSubSteps) _accumulated = 0;
  }

  /// Turns a point on the widget into a ray from the camera.
  List<double> _rayFor(Offset point, Size size) {
    final qx = (point.dx - size.width / 2) * 2 / size.height;
    final qy = -(point.dy - size.height / 2) * 2 / size.height;
    final inv = 1 / math.sqrt(qx * qx + qy * qy + _lens * _lens);
    return <double>[qx * inv, qy * inv, -_lens * inv];
  }

  void _updateGrab(
    EffectFrame frame,
    Size size,
    _Settings s,
    LinkChainRope rope,
  ) {
    final pointer = frame.pointer;
    final holding = frame.pressed && pointer != null;
    final canGrab = s.drag > 0 && !_released && !_entering;

    if (pointer != null && holding && !_wasPressed && canGrab) {
      final ray = _rayFor(pointer, size);
      var best = -1;
      var bestDistance = math.max(rope.bound * 1.2, _touchTarget / _scale);
      var bestT = 0.0;
      // The two ends are fixed, so only the links between can be grabbed.
      for (var i = 1; i < rope.count - 1; i++) {
        final vx = rope.px[i] - _camX;
        final vy = rope.py[i] - _camY;
        final vz = rope.pz[i] - _camZ;
        final t = vx * ray[0] + vy * ray[1] + vz * ray[2];
        if (t <= 0) continue;
        final ex = vx - ray[0] * t;
        final ey = vy - ray[1] * t;
        final ez = vz - ray[2] * t;
        final d = math.sqrt(ex * ex + ey * ey + ez * ez);
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
          bestT = t;
        }
      }
      if (best >= 0) {
        _grabbed = best;
        _grabDepth = bestT;
      }
    }
    if (!holding || !canGrab) _grabbed = -1;
    if (pointer != null && _grabbed >= 0 && holding) {
      // Hold the link at the depth it was picked at, so a drag slides it across
      // the view instead of shooting it at the camera.
      final ray = _rayFor(pointer, size);
      _grabX = _camX + ray[0] * _grabDepth;
      _grabY = _camY + ray[1] * _grabDepth;
      _grabZ = _camZ + ray[2] * _grabDepth;
    }
    _wasPressed = frame.pressed;
  }

  /// Writes everything that only changes when the widget is rebuilt.
  void _applyStatic(ui.FragmentShader shader, _Settings s) {
    shader
      ..setFloat(3, s.pixel)
      ..setFloat(13, s.finish == LinkChainFinish.metallic ? 1.0 : 0.0)
      ..setFloat(16, 1.0)
      ..setFloat(19, 0.09)
      ..setFloat(21, s.outlineWidth)
      ..setFloat(22, s.palette.length / 4)
      ..setFloat(23, s.metal.r)
      ..setFloat(24, s.metal.g)
      ..setFloat(25, s.metal.b)
      ..setFloat(26, 1.0);
    for (var i = 0; i < s.palette.length; i++) {
      shader.setFloat(547 + i, s.palette[i]);
    }
  }

  void _draw(
    Canvas canvas,
    Size size,
    LinkChainRope rope,
    _Layout layout,
    ui.FragmentShader shader,
    Paint paint,
    _Settings s,
  ) {
    final n = rope.count;
    _packFrames(rope);

    // Hull and groups, and the box on screen that holds the whole chain.
    var hx = 0.0, hy = 0.0, hz = 0.0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i++) {
      hx += rope.px[i];
      hy += rope.py[i];
      hz += rope.pz[i];
      final depth = layout.camZ - rope.pz[i];
      final zoom = depth > 0.1 ? layout.camZ / depth : 1.0;
      final sx = size.width / 2 + layout.scale * (rope.px[i] - layout.camX) * zoom;
      final sy = size.height / 2 - layout.scale * (rope.py[i] - layout.camY) * zoom;
      minX = math.min(minX, sx);
      maxX = math.max(maxX, sx);
      minY = math.min(minY, sy);
      maxY = math.max(maxY, sy);
    }
    hx /= n;
    hy /= n;
    hz /= n;
    var hr = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = rope.px[i] - hx;
      final dy = rope.py[i] - hy;
      final dz = rope.pz[i] - hz;
      hr = math.max(hr, math.sqrt(dx * dx + dy * dy + dz * dz));
    }
    final groupCount = (n + _groupSize - 1) ~/ _groupSize;
    for (var g = 0; g < groupCount; g++) {
      final i0 = g * _groupSize;
      final i1 = math.min(i0 + _groupSize, n);
      var cx = 0.0, cy = 0.0, cz = 0.0;
      for (var i = i0; i < i1; i++) {
        cx += rope.px[i];
        cy += rope.py[i];
        cz += rope.pz[i];
      }
      final c = (i1 - i0).toDouble();
      cx /= c;
      cy /= c;
      cz /= c;
      var r = 0.0;
      for (var i = i0; i < i1; i++) {
        final dx = rope.px[i] - cx;
        final dy = rope.py[i] - cy;
        final dz = rope.pz[i] - cz;
        r = math.max(r, math.sqrt(dx * dx + dy * dy + dz * dz));
      }
      _groups[g * 4] = cx;
      _groups[g * 4 + 1] = cy;
      _groups[g * 4 + 2] = cz;
      _groups[g * 4 + 3] = r + rope.bound;
    }

    final detail = switch (widget.quality) {
      EffectQuality.low => 0.0,
      EffectQuality.medium => 1.0,
      EffectQuality.high => 2.0,
    };

    shader
      ..setFloat(0, size.width / 2)
      ..setFloat(1, size.height / 2)
      ..setFloat(2, size.height)
      ..setFloat(4, layout.camX)
      ..setFloat(5, layout.camY)
      ..setFloat(6, layout.camZ)
      ..setFloat(7, hx)
      ..setFloat(8, hy)
      ..setFloat(9, hz)
      ..setFloat(10, hr + rope.bound)
      ..setFloat(11, n.toDouble())
      ..setFloat(12, groupCount.toDouble())
      ..setFloat(14, detail)
      ..setFloat(15, rope.le)
      ..setFloat(17, rope.r2)
      ..setFloat(18, rope.bound)
      ..setFloat(20, _slide);
    for (var i = 0; i < n * 4; i++) {
      shader
        ..setFloat(27 + i, _frameA[i])
        ..setFloat(187 + i, _frameB[i])
        ..setFloat(347 + i, _frameC[i]);
    }
    for (var i = 0; i < groupCount * 4; i++) {
      shader.setFloat(507 + i, _groups[i]);
    }

    final pad = rope.bound * layout.scale * 1.4 + 8;
    final rect = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad)
        .intersect(Offset.zero & size);
    if (rect.isEmpty) return;
    canvas.drawRect(rect, paint);
  }

  /// Fills the link frames: where each link is, which way it points, and a
  /// normal carried along the chain so the frame does not spin as it turns.
  void _packFrames(LinkChainRope rope) {
    final n = rope.count;
    var rx = 0.0, ry = 0.0, rz = 1.0;
    for (var i = 0; i < n; i++) {
      final ip = math.max(i - 1, 0);
      final iq = math.min(i + 1, n - 1);
      var tx = rope.px[iq] - rope.px[ip];
      var ty = rope.py[iq] - rope.py[ip];
      var tz = rope.pz[iq] - rope.pz[ip];
      final tlRaw = math.sqrt(tx * tx + ty * ty + tz * tz);
      final tl = tlRaw < 1e-6 ? 1e-6 : tlRaw;
      tx /= tl;
      ty /= tl;
      tz /= tl;

      final dp = rx * tx + ry * ty + rz * tz;
      rx -= tx * dp;
      ry -= ty * dp;
      rz -= tz * dp;
      var rl = math.sqrt(rx * rx + ry * ry + rz * rz);
      if (rl < 1e-4) {
        // The tangent swung onto the reference: pick any perpendicular.
        rx = tx.abs() < 0.9 ? 1.0 : 0.0;
        ry = tx.abs() < 0.9 ? 0.0 : 1.0;
        rz = 0.0;
        final d2 = rx * tx + ry * ty + rz * tz;
        rx -= tx * d2;
        ry -= ty * d2;
        rz -= tz * d2;
        rl = math.sqrt(rx * rx + ry * ry + rz * rz);
        if (rl < 1e-6) rl = 1e-6;
      }
      rx /= rl;
      ry /= rl;
      rz /= rl;

      final o = i * 4;
      _frameA[o] = rope.px[i];
      _frameA[o + 1] = rope.py[i];
      _frameA[o + 2] = rope.pz[i];
      _frameA[o + 3] = i.toDouble();
      _frameB[o] = tx;
      _frameB[o + 1] = ty;
      _frameB[o + 2] = tz;
      _frameB[o + 3] = (i % 2).toDouble();
      _frameC[o] = rx;
      _frameC[o + 1] = ry;
      _frameC[o + 2] = rz;
      _frameC[o + 3] = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _Settings(
      widget,
      1 / MediaQuery.devicePixelRatioOf(context),
    );
    return EffectHost(
      onPaint: (canvas, size, frame) =>
          _paintFrame(canvas, size, frame, settings),
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

double _clamp(double value, double low, double high) {
  final safe = value.isFinite ? value : low;
  return math.min(high, math.max(low, safe));
}

/// How the chain sits in the widget's box: where its ends are, how many pixels
/// one link radius covers, and the camera that makes the picture line up.
class _Layout {
  _Layout._({
    required this.scale,
    required this.ux,
    required this.uy,
    required this.camX,
    required this.camY,
    required this.camZ,
  });

  /// Pixels per link radius.
  final double scale;

  /// Direction from the first end to the second, in world axes with y up.
  final double ux, uy;

  final double camX, camY, camZ;

  /// The world origin is halfway between the two ends.
  static _Layout? of(Size size, _Settings s, LinkChainRope rope) {
    final a = s.start.alongSize(size);
    final b = s.end.alongSize(size);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final first = mid + (a - mid) * s.span;
    final second = mid + (b - mid) * s.span;
    final gapPx = (second - first).distance;
    if (gapPx < 2) return null;
    final gapWorld = rope.ropeLength / (1 + s.slack);
    final scale = gapPx / gapWorld;
    return _Layout._(
      scale: scale,
      ux: (second.dx - first.dx) / gapPx,
      uy: -(second.dy - first.dy) / gapPx,
      camX: (size.width / 2 - mid.dx) / scale,
      camY: -(size.height / 2 - mid.dy) / scale,
      camZ: size.height * _lens / (2 * scale),
    );
  }

  /// Distance between the two ends, in link radii.
  double gap(LinkChainRope rope, _Settings s) =>
      rope.ropeLength / (1 + s.slack);

  /// Both ends when the chain is at rest: x0, y0, x1, y1.
  List<double> anchors(double gap) => <double>[
        -ux * gap / 2,
        -uy * gap / 2,
        ux * gap / 2,
        uy * gap / 2,
      ];

  /// Both ends part way through the entrance. At 0 the chain is stretched
  /// straight and lifted clear above the frame, and at 1 it is at rest.
  List<double> entranceAnchors(LinkChainRope rope, _Settings s, double e) {
    final gap = this.gap(rope, s);
    final rest = anchors(gap);
    final out = (rope.ropeLength - gap) / 2;
    final up = 0.5 * gap;
    final k = 1 - e;
    return <double>[
      rest[0] - ux * out * k,
      rest[1] - uy * out * k + up * k,
      rest[2] + ux * out * k,
      rest[3] + uy * out * k + up * k,
    ];
  }
}

/// The widget's numbers, clamped to sensible ranges and turned into the units
/// the shader uses.
class _Settings {
  _Settings(LinkChain w, this.pixel)
      : finish = w.finish,
        start = w.start,
        end = w.end,
        span = _clamp(w.span, 0.1, 1.0),
        slack = _clamp(w.slack, 0.02, 1.5),
        links = math.min(maxLinkCount, math.max(minLinkCount, w.density)),
        linkLength = _clamp(w.linkLength, 0, 100),
        linkThickness = _clamp(w.linkThickness, 0, 100),
        outlineWidth = _clamp(w.outline, 0, 1) * 0.12,
        sway = _clamp(w.sway, 0, 200),
        speed = _clamp(w.speed, 0, 20),
        drift = _clamp(w.drift, 0, 20),
        drag = _clamp(w.drag, 0, 100),
        grabPull = 0.05 + _clamp(w.drag, 0, 100) / 100 * 0.55,
        entrance = w.entrance,
        entranceSeconds = math.max(0.1, w.entranceDuration.inMicroseconds / 1e6),
        quarterTurns = w.motionQuarterTurns,
        metal = w.metalColor,
        palette = _paletteFloats(w.colors);

  /// Size of one device pixel in logical pixels.
  final double pixel;

  final LinkChainFinish finish;
  final Alignment start;
  final Alignment end;
  final double span;
  final double slack;
  final int links;
  final double linkLength;
  final double linkThickness;
  final double outlineWidth;
  final double sway;
  final double speed;
  final double drift;
  final double drag;
  final double grabPull;
  final bool entrance;
  final double entranceSeconds;
  final int quarterTurns;
  final Color metal;

  /// The palette as colours of four numbers each, the last one unused.
  final List<double> palette;
}

List<double> _paletteFloats(List<Color>? colors) {
  final source = (colors == null || colors.isEmpty) ? _defaultColors : colors;
  final used = source.length > _maxPalette
      ? source.sublist(0, _maxPalette)
      : source;
  final out = List<double>.filled(_maxPalette * 4, 0.0);
  for (var i = 0; i < used.length; i++) {
    out[i * 4] = used[i].r;
    out[i * 4 + 1] = used[i].g;
    out[i * 4 + 2] = used[i].b;
  }
  // Only the colours in use are returned, four numbers each, so the length
  // divided by four is the number of colours.
  return out.sublist(0, used.length * 4);
}