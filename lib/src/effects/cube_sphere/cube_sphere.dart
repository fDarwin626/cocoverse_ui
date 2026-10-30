import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

// Distance from the camera to the centre of the sphere, and how much of the
// view the sphere spans at size 1.0, both in the units of the cube positions.
const double _cameraDistance = 6.6667;
const double _viewSpan = 5.4118;

// Light directions as unit vectors, as seen from the camera.
const double _keyX = 0.4511;
const double _keyY = 0.7018;
const double _keyZ = 0.5514;
const double _fillX = -0.6116;
const double _fillY = -0.2039;
const double _fillZ = 0.7645;

// Depth buckets used to draw the cubes from far to near.
const int _depthBuckets = 1024;

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

int _byte(double v) => (_clamp(v, 0, 1) * 255).round();

int _pack(double r, double g, double b) =>
    0xFF000000 | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);

/// Where every cube sits on the sphere, and its own fixed random numbers.
class _CubeData {
  _CubeData(this.count)
      : dir = Float64List(count * 3),
        axis = Float64List(count * 3),
        seed = Float64List(count),
        phase = Float64List(count) {
    // Spread the cubes evenly over the sphere along a golden-angle spiral.
    final golden = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < count; i++) {
      final y = 1 - (i / math.max(1, count - 1)) * 2;
      final ring = math.sqrt(math.max(0.0, 1 - y * y));
      final theta = golden * i;
      final x = math.cos(theta) * ring;
      final z = math.sin(theta) * ring;
      dir[i * 3] = x;
      dir[i * 3 + 1] = y;
      dir[i * 3 + 2] = z;

      // The axis this cube tumbles around.
      final ax = x + 0.4;
      final ay = y + 0.2;
      final az = z + 0.7;
      final length = math.sqrt(ax * ax + ay * ay + az * az);
      axis[i * 3] = ax / length;
      axis[i * 3 + 1] = ay / length;
      axis[i * 3 + 2] = az / length;

      final h = math.sin(i * 12.9898 + 78.233) * 43758.5453;
      seed[i] = h - h.floorToDouble();

      // Cubes with the same phase breathe at the same moment.
      phase[i] = x * 0.3 + y + z * 0.2;
    }
  }

  /// Number of cubes.
  final int count;

  /// Unit direction of each cube from the centre, 3 values per cube.
  final Float64List dir;

  /// Unit axis each cube tumbles around, 3 values per cube.
  final Float64List axis;

  /// A fixed random number from 0 to 1 for each cube.
  final Float64List seed;

  /// Where each cube sits in the breathing wave.
  final Float64List phase;
}

/// A sphere of small glossy cubes that tumble and breathe outward in waves.
///
/// Drag to spin it; it keeps turning with a little inertia. The cubes shift
/// from the first colour to the second as they are pushed outward. It fills
/// the space its parent gives it.
class CubeSphere extends StatefulWidget {
  /// Creates a cube sphere.
  const CubeSphere({
    super.key,
    this.colors = const <Color>[Color(0xFFFFD000), Color(0xFF0081FF)],
    this.sheen = const Color(0xFFFFFFFF),
    this.density = 1.0,
    this.cubeSize = 1.0,
    this.breath = 1.0,
    this.wave = 1.0,
    this.gap = 1.0,
    this.gloss = 0.47,
    this.tumble = 1.0,
    this.spin = -1.0,
    this.size = 1.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// The first colour is the cubes at rest, the second is where they are
  /// pushed outward. With only one colour, every cube keeps that colour.
  final List<Color> colors;

  /// Colour of the shiny highlight on the cube faces.
  final Color sheen;

  /// How many cubes there are, from 0 to 1. 1.0 is the most.
  final double density;

  /// Size of each cube, where 1.0 is the default.
  final double cubeSize;

  /// How far the cubes are pushed outward by the wave, where 1.0 is the
  /// default. 0 turns the breathing off.
  final double breath;

  /// How many waves fit across the sphere, where 1.0 is the default.
  final double wave;

  /// Radius of the sphere when the cubes are not pushed out, where 1.0 is the
  /// default.
  final double gap;

  /// How tight the highlight is, from 0 to 1. Higher is shinier.
  final double gloss;

  /// How fast the cubes tumble, where 1.0 is the default. 0 stops them.
  final double tumble;

  /// How fast the sphere turns on its own. Negative turns left, positive
  /// turns right and 0 keeps it still.
  final double spin;

  /// Size of the sphere, where 1.0 is the default.
  final double size;

  /// Fill behind the sphere. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the sphere.
  final bool interactive;

  /// How strongly a drag turns the sphere.
  final double dragSensitivity;

  /// Level of detail. Low draws about 770 cubes, medium about 2,060 and high
  /// about 3,640, so high is the heaviest.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the animation from the start.
  final EffectController? controller;

  /// Screen-reader description. Null marks the sphere as decorative.
  final String? semanticLabel;

  @override
  State<CubeSphere> createState() => _CubeSphereState();
}

class _CubeSphereState extends State<CubeSphere> {
  final Paint _paint = Paint();

  _CubeData? _data;
  Float32List _xy = Float32List(0);
  Int32List _colors = Int32List(0);
  Uint16List _indices = Uint16List(0);
  Int32List _bucketOf = Int32List(0);
  Int32List _order = Int32List(0);
  final Int32List _counts = Int32List(_depthBuckets);

  double _originX = 0;
  double _originY = 0;
  double _scale = 1;

  double _tipR = 0;
  double _tipG = 0;
  double _tipB = 0;
  double _sheenR = 1;
  double _sheenG = 1;
  double _sheenB = 1;
  double _glossPower = 80;

  _CubeData _dataFor(int count) {
    final existing = _data;
    if (existing != null && existing.count == count) return existing;
    final data = _CubeData(count);
    _data = data;
    // Every cube draws the three faces that point at the camera, 4 corners
    // each, so 12 corners and 18 indices per cube.
    _xy = Float32List(count * 24);
    _colors = Int32List(count * 12);
    _indices = Uint16List(count * 18);
    _bucketOf = Int32List(count);
    _order = Int32List(count);
    return data;
  }

  /// The colour of one cube face from its light, view and highlight terms.
  int _shade(
    double baseR,
    double baseG,
    double baseB,
    double key,
    double fill,
    double half,
    double facing,
  ) {
    final diffuse =
        0.28 + math.max(0.0, key) * 0.75 + math.max(0.0, fill) * 0.4;
    final spec =
        math.pow(math.max(0.0, half), _glossPower).toDouble() * 0.7;
    final edge = 1 - facing;
    final edge2 = edge * edge;
    final rim = edge2 * edge2 * 0.35;
    return _pack(
      baseR * diffuse + _sheenR * spec + _tipR * rim,
      baseG * diffuse + _sheenG * spec + _tipG * rim,
      baseB * diffuse + _sheenB * spec + _tipB * rim,
    );
  }

  void _put(int vertex, double x, double y, double z, int color) {
    final depth = math.max(0.05, _cameraDistance - z);
    _xy[vertex * 2] = _originX + _scale * x / depth;
    _xy[vertex * 2 + 1] = _originY - _scale * y / depth;
    _colors[vertex] = color;
  }

  /// Writes the 4 corners of one face: the cube centre, plus the face offset
  /// (f), plus or minus the two edge directions (u and w).
  void _face(
    int vertex,
    double cx,
    double cy,
    double cz,
    double fx,
    double fy,
    double fz,
    double ux,
    double uy,
    double uz,
    double wx,
    double wy,
    double wz,
    int color,
  ) {
    final ox = cx + fx;
    final oy = cy + fy;
    final oz = cz + fz;
    _put(vertex, ox + ux + wx, oy + uy + wy, oz + uz + wz, color);
    _put(vertex + 1, ox - ux + wx, oy - uy + wy, oz - uz + wz, color);
    _put(vertex + 2, ox - ux - wx, oy - uy - wy, oz - uz - wz, color);
    _put(vertex + 3, ox + ux - wx, oy + uy - wy, oz + uz - wz, color);
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;

    final levelCap = switch (frame.quality) {
      EffectQuality.low => 9,
      EffectQuality.medium => 15,
      EffectQuality.high => 20,
    };
    final wanted = (1 + _clamp(widget.density, 0, 1) * 19).round();
    final level = math.min(wanted, levelCap);
    final n = 40 + level * level * 9;
    final data = _dataFor(n);

    final colors = widget.colors;
    final base = colors.isNotEmpty ? colors.first : const Color(0xFFFFD000);
    final tip = colors.length > 1 ? colors[1] : base;
    final sheen = widget.sheen;
    final baseR = base.r;
    final baseG = base.g;
    final baseB = base.b;
    _tipR = tip.r;
    _tipG = tip.g;
    _tipB = tip.b;
    _sheenR = sheen.r;
    _sheenG = sheen.g;
    _sheenB = sheen.b;
    _glossPower = 6 + (1 - _clamp(widget.gloss, 0, 1)) * 147;

    final shortSide = math.min(size.width, size.height);
    final span = _viewSpan / _clamp(widget.size, 0.3, 2.0);
    _scale = shortSide * _cameraDistance / span;
    _originX = size.width / 2;
    _originY = size.height / 2;

    final time = frame.time;
    final tumbleRate = 3.6 * widget.tumble;
    final waveFactor = 7.0 * widget.wave;
    final breathDistance = 1.32 * widget.breath;
    final baseRadius = 0.94 * widget.gap;
    final cubeEdge = 0.08 * widget.cubeSize;
    final depthRange = baseRadius + breathDistance + cubeEdge * 2;

    // The sphere's turn: yaw, then pitch, with a small tilt toward the finger.
    var yaw = frame.yaw;
    var pitch = frame.pitch;
    final pointer = frame.pointer;
    if (widget.interactive && pointer != null) {
      final reach = 0.25 * frame.pointerStrength / (shortSide / 2);
      yaw += (pointer.dx - size.width / 2) * reach;
      pitch += (pointer.dy - size.height / 2) * reach;
    }
    pitch = _clamp(pitch, -1.2, 1.2);
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);
    final g00 = cosYaw;
    const g01 = 0.0;
    final g02 = sinYaw;
    final g10 = sinPitch * sinYaw;
    final g11 = cosPitch;
    final g12 = -sinPitch * cosYaw;
    final g20 = -cosPitch * sinYaw;
    final g21 = sinPitch;
    final g22 = cosPitch * cosYaw;

    final dir = data.dir;
    final axis = data.axis;
    final seed = data.seed;
    final phase = data.phase;

    for (var i = 0; i < n; i++) {
      final k = i * 3;
      final sd = seed[i];
      final push = math.sin(time * 1.2 + phase[i] * waveFactor) * 0.5 + 0.5;
      final radius = baseRadius + push * breathDistance;
      final hs = 0.5 * cubeEdge * (1.1 - push * 0.35) * (0.7 + sd * 0.6);

      // Where the cube sits, turned with the sphere.
      final dx = dir[k] * radius;
      final dy = dir[k + 1] * radius;
      final dz = dir[k + 2] * radius;
      final cx = g00 * dx + g01 * dy + g02 * dz;
      final cy = g10 * dx + g11 * dy + g12 * dz;
      final cz = g20 * dx + g21 * dy + g22 * dz;

      // The cube's own tumble: its three edge directions.
      final angle = time * tumbleRate * (0.5 + sd);
      final cs = math.cos(angle);
      final sn = math.sin(angle);
      final t = 1 - cs;
      final ax = axis[k];
      final ay = axis[k + 1];
      final az = axis[k + 2];
      final u0x = t * ax * ax + cs;
      final u0y = t * ax * ay + sn * az;
      final u0z = t * ax * az - sn * ay;
      final u1x = t * ax * ay - sn * az;
      final u1y = t * ay * ay + cs;
      final u1z = t * ay * az + sn * ax;
      final u2x = t * ax * az + sn * ay;
      final u2y = t * ay * az - sn * ax;
      final u2z = t * az * az + cs;

      // Turn them with the sphere too.
      final e0x = g00 * u0x + g01 * u0y + g02 * u0z;
      final e0y = g10 * u0x + g11 * u0y + g12 * u0z;
      final e0z = g20 * u0x + g21 * u0y + g22 * u0z;
      final e1x = g00 * u1x + g01 * u1y + g02 * u1z;
      final e1y = g10 * u1x + g11 * u1y + g12 * u1z;
      final e1z = g20 * u1x + g21 * u1y + g22 * u1z;
      final e2x = g00 * u2x + g01 * u2y + g02 * u2z;
      final e2y = g10 * u2x + g11 * u2y + g12 * u2z;
      final e2z = g20 * u2x + g21 * u2y + g22 * u2z;

      // From the cube toward the camera, and the highlight's half vector.
      var vx = -cx;
      var vy = -cy;
      var vz = _cameraDistance - cz;
      final vLength = math.sqrt(vx * vx + vy * vy + vz * vz);
      vx /= vLength;
      vy /= vLength;
      vz /= vLength;
      var hx = _keyX + vx;
      var hy = _keyY + vy;
      var hz = _keyZ + vz;
      final hLength = math.sqrt(hx * hx + hy * hy + hz * hz);
      hx /= hLength;
      hy /= hLength;
      hz /= hLength;

      // Of each pair of opposite faces, the one that points at the camera.
      final d0 = e0x * vx + e0y * vy + e0z * vz;
      final d1 = e1x * vx + e1y * vy + e1z * vz;
      final d2 = e2x * vx + e2y * vy + e2z * vz;
      final s0 = d0 >= 0 ? 1.0 : -1.0;
      final s1 = d1 >= 0 ? 1.0 : -1.0;
      final s2 = d2 >= 0 ? 1.0 : -1.0;

      final br = baseR + (_tipR - baseR) * push;
      final bg = baseG + (_tipG - baseG) * push;
      final bb = baseB + (_tipB - baseB) * push;

      final slot = i * 12;
      _face(
        slot,
        cx,
        cy,
        cz,
        s0 * hs * e0x,
        s0 * hs * e0y,
        s0 * hs * e0z,
        hs * e1x,
        hs * e1y,
        hs * e1z,
        hs * e2x,
        hs * e2y,
        hs * e2z,
        _shade(
          br,
          bg,
          bb,
          s0 * (e0x * _keyX + e0y * _keyY + e0z * _keyZ),
          s0 * (e0x * _fillX + e0y * _fillY + e0z * _fillZ),
          s0 * (e0x * hx + e0y * hy + e0z * hz),
          d0.abs(),
        ),
      );
      _face(
        slot + 4,
        cx,
        cy,
        cz,
        s1 * hs * e1x,
        s1 * hs * e1y,
        s1 * hs * e1z,
        hs * e2x,
        hs * e2y,
        hs * e2z,
        hs * e0x,
        hs * e0y,
        hs * e0z,
        _shade(
          br,
          bg,
          bb,
          s1 * (e1x * _keyX + e1y * _keyY + e1z * _keyZ),
          s1 * (e1x * _fillX + e1y * _fillY + e1z * _fillZ),
          s1 * (e1x * hx + e1y * hy + e1z * hz),
          d1.abs(),
        ),
      );
      _face(
        slot + 8,
        cx,
        cy,
        cz,
        s2 * hs * e2x,
        s2 * hs * e2y,
        s2 * hs * e2z,
        hs * e0x,
        hs * e0y,
        hs * e0z,
        hs * e1x,
        hs * e1y,
        hs * e1z,
        _shade(
          br,
          bg,
          bb,
          s2 * (e2x * _keyX + e2y * _keyY + e2z * _keyZ),
          s2 * (e2x * _fillX + e2y * _fillY + e2z * _fillZ),
          s2 * (e2x * hx + e2y * hy + e2z * hz),
          d2.abs(),
        ),
      );

      final bucket =
          (((cz / depthRange) * 0.5 + 0.5) * (_depthBuckets - 1)).floor();
      _bucketOf[i] = bucket < 0
          ? 0
          : (bucket >= _depthBuckets ? _depthBuckets - 1 : bucket);
    }

    // Draw the cubes from far to near: a counting sort on depth.
    _counts.fillRange(0, _depthBuckets, 0);
    for (var i = 0; i < n; i++) {
      _counts[_bucketOf[i]]++;
    }
    var running = 0;
    for (var b = 0; b < _depthBuckets; b++) {
      final c = _counts[b];
      _counts[b] = running;
      running += c;
    }
    for (var i = 0; i < n; i++) {
      final b = _bucketOf[i];
      _order[_counts[b]++] = i;
    }

    var w = 0;
    for (var j = 0; j < n; j++) {
      final first = _order[j] * 12;
      for (var f = 0; f < 3; f++) {
        final v = first + f * 4;
        _indices[w++] = v;
        _indices[w++] = v + 1;
        _indices[w++] = v + 2;
        _indices[w++] = v;
        _indices[w++] = v + 2;
        _indices[w++] = v + 3;
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _xy,
      colors: _colors,
      indices: _indices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
    vertices.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EffectHost(
      onPaint: _paintFrame,
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      rotatesOnDrag: true,
      dragSensitivity: widget.dragSensitivity,
      autoRotate: 0.84 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}