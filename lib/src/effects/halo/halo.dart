import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

// The original's camera: a gentle perspective, 1 / 0.15 units from the rings.
const double _perspective = 0.15;

// World units per slider pixel, as in the original.
const double _pxPerUnit = 100;

const int _maxRings = 6;

// The pose the rings start in.
const double _startX = 0.5;
const double _startY = 0.4;

// Which axis each ring turns about, in order: y, x, z (0 is x, 1 is y, 2 is z).
const List<int> _axisOrder = <int>[1, 0, 2];

// The chrome is looked up from a small table made once, by which way a
// point on the surface faces.
const int _lutSide = 128;

// Where the cartoon light comes from: upper right, in front.
const double _lightX = 0.31;
const double _lightY = 0.543;
const double _lightZ = 0.776;

/// The candy colours of the cartoon finish, one per ring.
const List<Color> _candy = <Color>[
  Color(0xFFF0521E),
  Color(0xFFEFE2C3),
  Color(0xFF1B4BE0),
  Color(0xFF0E6B22),
  Color(0xFFB9BEF2),
  Color(0xFFE8A317),
];

/// How the rings are painted.
enum HaloFinish {
  /// Polished chrome that reflects a studio. Coloured by [Halo.tint].
  metallic,

  /// Flat colour bands with an ink outline, like a drawing.
  cartoon,
}

/// A set of rings turning inside each other like a gyroscope.
///
/// Use it as a loading indicator, as a progress ring, or as a frame around
/// a logo or an avatar. Drag it to turn the whole thing and it keeps
/// turning after you let go. Pointing at it speeds the rings up.
///
/// It fills the space it is given, so size it from outside:
///
/// ```dart
/// SizedBox(
///   width: 96,
///   height: 96,
///   child: Halo(semanticLabel: 'Loading'),
/// )
/// ```
class Halo extends StatefulWidget {
  /// Creates a halo.
  const Halo({
    super.key,
    this.finish = HaloFinish.metallic,
    this.tint = const Color(0xFFEDEDED),
    this.colors,
    this.ink = const Color(0xFF1B140F),
    this.outline = 0.3,
    this.rings = 6,
    this.thickness = 5.0,
    this.innerRadius = 40.0,
    this.gap = 0.0,
    this.spin = 2.0,
    this.hoverBoost = 10.0,
    this.dragSensitivity = 3.0,
    this.sizePercent = 104.0,
    this.progress,
    this.child,
    this.interactive = true,
    this.paused = false,
    this.quality = EffectQuality.high,
    this.background,
    this.controller,
    this.semanticLabel,
  });

  /// Chrome or cartoon.
  final HaloFinish finish;

  /// The colour the chrome is tinted with, for the metallic finish. Silver
  /// by default. Gold or copper work well, and the glints stay white.
  final Color tint;

  /// The colours the rings take, outermost first, for the cartoon finish.
  /// They repeat if there are fewer than rings. If null, the candy colours
  /// are used.
  final List<Color>? colors;

  /// The colour of the outline in the cartoon finish.
  final Color ink;

  /// How thick the outline is in the cartoon finish, from 0 to 1.
  final double outline;

  /// How many rings, 1 to 6. The first is the outermost.
  final int rings;

  /// How thick each ring's tube is, from 1 to 20.
  final double thickness;

  /// Size of the innermost ring, from 20 to 200.
  final double innerRadius;

  /// Space between neighbouring rings, from 0 to 50.
  final double gap;

  /// How fast the rings turn, from 1 to 20. Use [paused] to stop them.
  final double spin;

  /// How much pointing at it speeds the rings up, from 0 to 10. 0 turns it off.
  final double hoverBoost;

  /// How far a drag turns it, from 0 to 10. 0 turns dragging off.
  final double dragSensitivity;

  /// How much of the box the rings fill, from 20 to 200 percent.
  final double sizePercent;

  /// Progress from 0 to 1. Null means an endless loader with every ring lit.
  /// A number lights the rings one at a time from the innermost out, and
  /// the rings not yet lit stay dark.
  final double? progress;

  /// Anything to show in the middle, such as a percentage, a logo or a
  /// photo. It is decorative and sits behind the rings.
  final Widget? child;

  /// Whether dragging and pointing do anything. Turn it off when the halo
  /// sits inside something that scrolls.
  final bool interactive;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings build the rings from fewer pieces.
  final EffectQuality quality;

  /// Fill behind the rings. Null means transparent.
  final Color? background;

  /// Optional control. [EffectController.reset] puts the rings back to
  /// their starting pose.
  final EffectController? controller;

  /// Screen-reader description. Null marks the halo as decorative. For a
  /// loader, use something like 'Loading'.
  final String? semanticLabel;

  @override
  State<Halo> createState() => _HaloState();
}

class _HaloState extends State<Halo> {
  // The colours come with the mesh, so the paint is plain white and
  // modulate leaves them exactly as they are.
  final Paint _paint = Paint()..color = const Color(0xFFFFFFFF);

  // The pose. The whole halo turns by _ax and _ay, and each ring turns on its
  // own by _theta.
  double _ax = _startX;
  double _ay = _startY;
  double _vx = 0;
  double _vy = 0;
  double _boost = 0;
  bool _dragging = false;
  bool _hovered = false;
  bool _reduced = false;
  double _lastTime = 0;
  int _seenResets = 0;
  final Float64List _theta = Float64List(_maxRings);

  // Scratch space, so a frame makes no garbage of its own.
  final Float64List _a = Float64List(9);
  final Float64List _b = Float64List(9);
  final Float64List _cum = Float64List(9);
  final Float64List _pivot = Float64List(9);
  final Float64List _ring = Float64List(9);
  final Float64List _tmp = Float64List(9);
  late final List<Float64List> _orient = _makeOrient();

  // The mesh: every ring is segments around, each made of sides around the
  // tube. Rebuilt only when those numbers change.
  int _meshRings = 0;
  int _meshSegs = 0;
  int _meshSides = 0;
  Float32List _pos = Float32List(0);
  Int32List _vcol = Int32List(0);
  Float64List _facing = Float64List(0);
  Uint16List _idx = Uint16List(0);
  Float64List _cu = Float64List(0);
  Float64List _su = Float64List(0);
  Float64List _cv = Float64List(0);
  Float64List _sv = Float64List(0);
  Float64List _segDepth = Float64List(0);
  List<int> _segOrder = <int>[];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
  }

  @override
  void didUpdateWidget(Halo oldWidget) {
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
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _ax = _startX;
      _ay = _startY;
      _vx = 0;
      _vy = 0;
      _boost = 0;
      _theta.fillRange(0, _maxRings, 0.0);
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
    _vx = 0;
    _vy = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final s = _clamp(widget.dragSensitivity, 0, 10) * 0.007;
    _ay += details.delta.dx * s;
    _ax += details.delta.dy * s;
  }

  void _onPanEnd(DragEndDetails details) {
    _dragging = false;
    final s = _clamp(widget.dragSensitivity, 0, 10) * 0.007;
    _vy = _clamp(details.velocity.pixelsPerSecond.dx * s, -9, 9);
    _vx = _clamp(details.velocity.pixelsPerSecond.dy * s, -9, 9);
  }

  void _onPanCancel() {
    _dragging = false;
  }

  void _step(double dt) {
    if (dt <= 0) return;
    if (!_dragging) {
      final decay = math.exp(-dt * 2.6);
      _ay += _vy * dt;
      _ax += _vx * dt;
      _vx *= decay;
      _vy *= decay;
    }
    final want =
        (_hovered || _dragging) ? _clamp(widget.hoverBoost, 0, 10) / 5 : 0.0;
    _boost += (want - _boost) * (1 - math.exp(-dt * 4));
    final base = _clamp(widget.spin, 1, 20) * 0.09 * (1 + _boost);
    for (var i = 0; i < _maxRings; i++) {
      final rate = (i + 1) * (i.isOdd ? -1 : 1);
      _theta[i] += base * rate * dt;
    }
  }

  void _ensureMesh(int rings, int segs, int sides) {
    if (_meshRings == rings && _meshSegs == segs && _meshSides == sides) return;
    _meshRings = rings;
    _meshSegs = segs;
    _meshSides = sides;
    final verts = rings * segs * sides;
    _pos = Float32List(verts * 2);
    _vcol = Int32List(verts);
    _facing = Float64List(verts);
    _idx = Uint16List(verts * 6);
    _segDepth = Float64List(rings * segs);
    _segOrder = List<int>.generate(rings * segs, (i) => i);
    _cu = Float64List(segs);
    _su = Float64List(segs);
    for (var i = 0; i < segs; i++) {
      final angle = 2 * math.pi * i / segs;
      _cu[i] = math.cos(angle);
      _su[i] = math.sin(angle);
    }
    _cv = Float64List(sides);
    _sv = Float64List(sides);
    for (var j = 0; j < sides; j++) {
      final angle = 2 * math.pi * j / sides;
      _cv[j] = math.cos(angle);
      _sv[j] = math.sin(angle);
    }
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;

    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0 || widget.paused || _reduced) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _step(dt);
    _draw(canvas, size);
  }

  void _draw(Canvas canvas, Size size) {
    final count = math.max(1, math.min(_maxRings, widget.rings));
    final inner = _clamp(widget.innerRadius, 20, 200) / _pxPerUnit;
    final gap = _clamp(widget.gap, 0, 50) / _pxPerUnit;
    final tube = _clamp(widget.thickness, 1, 20) / 100 * 0.6;
    final pitch = gap + tube * 2;
    final framing = inner + (count - 1) * pitch + tube;

    // The camera, as the original sets it up.
    final distance = 1 / _perspective;
    final span = framing * 2.9 * (100 / _clamp(widget.sizePercent, 20, 200));
    final aspect = size.width / size.height;
    final visible = aspect < 1 ? span / aspect : span;
    final f = size.height * distance / visible;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final metallic = widget.finish == HaloFinish.metallic;
    final (segs, sides) = switch (widget.quality) {
      EffectQuality.low => (48, metallic ? 10 : 16),
      EffectQuality.medium => (80, metallic ? 14 : 22),
      EffectQuality.high => (120, metallic ? 18 : 28),
    };
    _ensureMesh(count, segs, sides);

    final tint = widget.tint;
    final tintR = tint.r * 255;
    final tintG = tint.g * 255;
    final tintB = tint.b * 255;
    final given = widget.colors;
    final palette = (given == null || given.isEmpty) ? _candy : given;
    final ink = widget.ink;
    final inkR = ink.r * 255;
    final inkG = ink.g * 255;
    final inkB = ink.b * 255;
    final inkEdge = 0.06 + _clamp(widget.outline, 0, 1) * 0.5;
    final lut = metallic ? _metalLut() : null;
    final progress = widget.progress;

    // The whole halo turns first, then each ring inside the one before it.
    _rotAxis(_a, 0, _ax);
    _rotAxis(_b, 1, _ay);
    _mul(_cum, _a, _b, _tmp);

    for (var i = 0; i < count; i++) {
      final axis = _axisOrder[i % 3];
      _rotAxis(_pivot, axis, _theta[i]);
      _mul(_cum, _cum, _pivot, _tmp);
      _mul(_ring, _cum, _orient[axis], _tmp);

      final w00 = _ring[0];
      final w01 = _ring[1];
      final w02 = _ring[2];
      final w10 = _ring[3];
      final w11 = _ring[4];
      final w12 = _ring[5];
      final w20 = _ring[6];
      final w21 = _ring[7];
      final w22 = _ring[8];

      final k = count - 1 - i;
      final radius = inner + k * pitch;
      final lit = progress == null ? 1.0 : _clamp(progress * count - k, 0, 1);
      final dim = progress == null ? 1.0 : 0.22 + 0.78 * lit;
      final ringColor = palette[i % palette.length];
      final ringR = ringColor.r * 255;
      final ringG = ringColor.g * 255;
      final ringB = ringColor.b * 255;
      final ringBase = i * segs * sides;

      for (var s = 0; s < segs; s++) {
        final cu = _cu[s];
        final su = _su[s];

        // How far this piece of the ring is from the viewer, for ordering.
        final centreZ = radius * (w20 * cu + w21 * su);
        _segDepth[i * segs + s] = distance - centreZ;

        final segBase = ringBase + s * sides;
        for (var j = 0; j < sides; j++) {
          final cv = _cv[j];
          final sv = _sv[j];

          // A point on the tube and the way the surface faces there.
          final rr = radius + tube * cv;
          final lx = rr * cu;
          final ly = rr * su;
          final lz = tube * sv;
          final x = w00 * lx + w01 * ly + w02 * lz;
          final y = w10 * lx + w11 * ly + w12 * lz;
          final z = w20 * lx + w21 * ly + w22 * lz;
          final nlx = cv * cu;
          final nly = cv * su;
          final nx = w00 * nlx + w01 * nly + w02 * sv;
          final ny = w10 * nlx + w11 * nly + w12 * sv;
          final nz = w20 * nlx + w21 * nly + w22 * sv;

          final d = math.max(0.3, distance - z);
          final inv = f / d;
          final v = segBase + j;
          _pos[v * 2] = cx + x * inv;
          _pos[v * 2 + 1] = cy - y * inv;

          // How squarely it faces the viewer: 1 straight on, 0 at the edge.
          final vl = math.sqrt(x * x + y * y + d * d);
          final facing = (-nx * x - ny * y + nz * d) / vl;
          _facing[v] = facing;

          // Pieces nearer the viewer are a little brighter.
          final depthShade =
              0.82 + 0.18 * _clamp((z + framing) / (2 * framing), 0, 1);

          double r;
          double g;
          double b;
          if (metallic) {
            final table = lut!;
            final fx = (nx * 0.5 + 0.5) * (_lutSide - 1);
            final fy = (ny * 0.5 + 0.5) * (_lutSide - 1);
            final x0 = math.min(_lutSide - 2, math.max(0, fx.floor()));
            final y0 = math.min(_lutSide - 2, math.max(0, fy.floor()));
            final tx = fx - x0;
            final ty = fy - y0;
            final o00 = (y0 * _lutSide + x0) * 2;
            final o10 = o00 + 2;
            final o01 = o00 + _lutSide * 2;
            final o11 = o01 + 2;
            final body = (table[o00] * (1 - tx) + table[o10] * tx) * (1 - ty) +
                (table[o01] * (1 - tx) + table[o11] * tx) * ty;
            final spec =
                (table[o00 + 1] * (1 - tx) + table[o10 + 1] * tx) * (1 - ty) +
                    (table[o01 + 1] * (1 - tx) + table[o11 + 1] * tx) * ty;
            final edge = 1 - math.max(facing, 0.0);
            final shade = (1 - 0.38 * edge * edge * edge) * depthShade * dim;
            r = (tintR * body + 255 * spec) * shade;
            g = (tintG * body + 255 * spec) * shade;
            b = (tintB * body + 255 * spec) * shade;
          } else {
            // Three flat bands of light and shade, a pale highlight, and an
            // ink line where the surface turns away from the viewer.
            final dl = nx * _lightX + ny * _lightY + nz * _lightZ;
            final band = 0.56 +
                0.20 * _smooth(0.0, 0.10, dl) +
                0.24 * _smooth(0.32, 0.44, dl);
            final glow = _smooth(0.76, 0.86, dl) * 0.4;
            r = ringR * band;
            g = ringG * band;
            b = ringB * band;
            r += (255 - r) * glow;
            g += (255 - g) * glow;
            b += (255 - b) * glow;
            final inkAmount = 1 - _smooth(inkEdge - 0.05, inkEdge + 0.02, facing);
            r += (inkR - r) * inkAmount;
            g += (inkG - g) * inkAmount;
            b += (inkB - b) * inkAmount;
            r *= dim;
            g *= dim;
            b *= dim;
          }
          _vcol[v] = 0xFF000000 | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);
        }
      }
    }

    // Back to front, so nearer pieces cover farther ones.
    _segOrder.sort((p, q) => _segDepth[q].compareTo(_segDepth[p]));

    // Only the faces turned toward the viewer are drawn.
    var used = 0;
    final segTotal = count * segs;
    for (var o = 0; o < segTotal; o++) {
      final seg = _segOrder[o];
      final ring = seg ~/ segs;
      final s = seg % segs;
      final ringBase = ring * segs * sides;
      final from = ringBase + s * sides;
      final to = ringBase + ((s + 1) % segs) * sides;
      for (var j = 0; j < sides; j++) {
        final j1 = j + 1 == sides ? 0 : j + 1;
        final qa = from + j;
        final qb = to + j;
        final qc = to + j1;
        final qd = from + j1;
        if (_facing[qa] + _facing[qb] + _facing[qc] + _facing[qd] <= 0) continue;
        _idx[used] = qa;
        _idx[used + 1] = qb;
        _idx[used + 2] = qc;
        _idx[used + 3] = qa;
        _idx[used + 4] = qc;
        _idx[used + 5] = qd;
        used += 6;
      }
    }
    if (used == 0) return;

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _pos,
      colors: _vcol,
      indices: Uint16List.sublistView(_idx, 0, used),
    );
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _paint);
    vertices.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget host = EffectHost(
      onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
      paused: widget.paused,
      interactive: false,
      rotatesOnDrag: false,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );

    if (widget.interactive) {
      host = MouseRegion(
        onEnter: (_) {
          _hovered = true;
        },
        onExit: (_) {
          _hovered = false;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanCancel,
          child: host,
        ),
      );
    }

    final inside = widget.child;
    if (inside == null) return host;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[Center(child: inside), host],
    );
  }
}

double _clamp(double value, double low, double high) {
  final safe = value.isFinite ? value : low;
  return math.min(high, math.max(low, safe));
}

double _smooth(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

int _byte(double value) {
  if (value <= 0) return 0;
  if (value >= 255) return 255;
  return value.round();
}

/// A turn of [angle] radians about axis 0 (x), 1 (y) or 2 (z), as a 3 by 3
/// matrix stored row by row.
void _rotAxis(Float64List m, int axis, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  switch (axis) {
    case 0:
      m[0] = 1;
      m[1] = 0;
      m[2] = 0;
      m[3] = 0;
      m[4] = c;
      m[5] = -s;
      m[6] = 0;
      m[7] = s;
      m[8] = c;
    case 1:
      m[0] = c;
      m[1] = 0;
      m[2] = s;
      m[3] = 0;
      m[4] = 1;
      m[5] = 0;
      m[6] = -s;
      m[7] = 0;
      m[8] = c;
    default:
      m[0] = c;
      m[1] = -s;
      m[2] = 0;
      m[3] = s;
      m[4] = c;
      m[5] = 0;
      m[6] = 0;
      m[7] = 0;
      m[8] = 1;
  }
}

/// out = a x b. [out] may be the same list as [a] or [b].
void _mul(Float64List out, Float64List a, Float64List b, Float64List tmp) {
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      tmp[r * 3 + c] =
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  for (var i = 0; i < 9; i++) {
    out[i] = tmp[i];
  }
}

/// How each ring sits before it starts turning: the ring that turns on x is
/// laid flat, the one that turns on z is stood on its edge, as in the
/// original.
List<Float64List> _makeOrient() {
  final x = Float64List(9);
  _rotAxis(x, 0, math.pi / 2);
  final y = Float64List(9);
  _rotAxis(y, 1, 0);
  final z = Float64List(9);
  _rotAxis(z, 1, math.pi / 2);
  return <Float64List>[x, y, z];
}

Float32List? _lutCache;

/// What a mirror ball shows, by which way the surface faces: two numbers for
/// every direction, the reflected light (tinted) and the white glints. Made
/// once and shared.
Float32List _metalLut() {
  final cached = _lutCache;
  if (cached != null) return cached;
  final lut = Float32List(_lutSide * _lutSide * 2);
  for (var y = 0; y < _lutSide; y++) {
    for (var x = 0; x < _lutSide; x++) {
      var nx = x / (_lutSide - 1) * 2 - 1;
      var ny = y / (_lutSide - 1) * 2 - 1;
      final r2 = nx * nx + ny * ny;
      var nz = 0.0;
      if (r2 >= 1) {
        final inv = 1 / math.sqrt(r2);
        nx *= inv;
        ny *= inv;
      } else {
        nz = math.sqrt(1 - r2);
      }
      final (body, spec) = _chrome(nx, ny, nz);
      final o = (y * _lutSide + x) * 2;
      lut[o] = body;
      lut[o + 1] = spec;
    }
  }
  _lutCache = lut;
  return lut;
}

double _glint(
  double rx,
  double ry,
  double rz,
  double lx,
  double ly,
  double lz,
  double power,
) {
  final len = math.sqrt(lx * lx + ly * ly + lz * lz);
  final d = (rx * lx + ry * ly + rz * lz) / len;
  return d <= 0 ? 0.0 : math.pow(d, power).toDouble();
}

/// Polished chrome in a studio: a bright sky over a dark floor with a thin
/// bright horizon between them, a tall softbox on the left, a dark flag on
/// the right, and a few white glints on top.
(double, double) _chrome(double nx, double ny, double nz) {
  final rx = 2 * nz * nx;
  final ry = 2 * nz * ny;
  final rz = 2 * nz * nz - 1;

  final sky = 0.58 + 0.42 * math.pow(math.max(ry, 0.0), 0.6).toDouble();
  final floor = 0.20 - 0.14 * math.pow(math.max(-ry, 0.0), 0.5).toDouble();
  var body = floor + (sky - floor) * _smooth(-0.05, 0.05, ry);
  body += 0.5 * math.exp(-(ry - 0.04) * (ry - 0.04) * 500);

  final az = math.atan2(rx, rz);
  final box = _smooth(-1.3, -1.12, az) *
      (1 - _smooth(-0.62, -0.48, az)) *
      _smooth(0.0, 0.12, ry) *
      (1 - _smooth(0.75, 0.9, ry));
  body += 0.6 * box;
  final flag = _smooth(0.5, 0.62, az) * (1 - _smooth(0.95, 1.1, az));
  body *= 1 - 0.55 * flag;

  var spec = 0.0;
  spec += 1.0 * _glint(rx, ry, rz, -0.45, 0.65, 0.62, 30);
  spec += 0.55 * _glint(rx, ry, rz, 0.72, 0.22, 0.66, 24);
  spec += 0.22 * _glint(rx, ry, rz, 0.0, -0.75, 0.66, 16);
  return (body, spec);
}