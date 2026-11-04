import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_quality.dart';

double _clamp(double v, double lo, double hi) =>
    math.min(hi, math.max(lo, v));

double _mix(double a, double b, double t) => a + (b - a) * t;


double _ss(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

double _h(double x) {
  final s = math.sin(x * 127.1) * 43758.5453;
  return s - s.floorToDouble();
}

double _vn(double x) {
  final i = x.floorToDouble();
  final f = x - i;
  final t = f * f * (3 - 2 * f);
  return _mix(_h(i), _h(i + 1), t);
}

int _byte(double v) => (v * 255 + 0.5).floor().clamp(0, 255).toInt();

int _toneByte(double x) {
  final v = 1 - math.exp(-math.max(x, 0.0));
  return _byte(math.pow(v, 1 / 2.2).toDouble());
}

// ---- the body's outline, as the fins need it (same as the shader's)

const double _pse = 2.3;

double _halfH(double s) {
  final t = math.pow(_clamp(s, 0, 1), 1.16).toDouble();
  final w = math.sin(math.pi * t);
  return 0.07 + 0.24 * math.pow(w < 0 ? 0.0 : w, 0.85).toDouble();
}

double _centerY(double s) =>
    -0.012 * math.sin(math.pi * _clamp(s, 0, 1)) +
    0.045 * _ss(0.7, 1.0, s) -
    0.04 * (1 - _ss(0.0, 0.16, s));

/// A point on the body's skin at ring s, normalised height yn, side sigma.
(double, double, double) _skin(
    double s, double yn, double sigma, double depth) {
  final h = _halfH(s) * depth;
  final zn = math
      .pow(math.max(0.0, 1 - math.pow(yn.abs(), _pse)), 1 / _pse)
      .toDouble();
  return (0.5 - s, _centerY(s) + h * yn, sigma * 0.78 * h * zn);
}

List<double> _n3(double x, double y, double z) {
  final l = math.sqrt(x * x + y * y + z * z);
  return [x / l, y / l, z / l];
}

List<double> _nfOf(List<double> a, List<double> b) => _n3(
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    );

(double, double, double) _rot(double vx, double vy, double vz, double ax,
    double ay, double az, double ang) {
  final c = math.cos(ang);
  final s = math.sin(ang);
  final d = (vx * ax + vy * ay + vz * az) * (1 - c);
  return (
    vx * c + (ay * vz - az * vy) * s + ax * d,
    vy * c + (az * vx - ax * vz) * s + ay * d,
    vz * c + (ax * vy - ay * vx) * s + az * d,
  );
}

double _lenAt(List<double> len, double v) {
  final x = v * 4;
  final fi = math.min(x.floor(), 3);
  var t = x - fi;
  t = t * t * (3 - 2 * t);
  return _mix(len[fi], len[fi + 1], t);
}

// Key light, in view space.
const double _lx = -0.409, _ly = 0.879, _lz = 0.245;

enum _Root { dorsal, tail, body }

/// One fin: where it is rooted, how it fans out and how it moves.
class _Fin {
  _Fin({
    required this.root,
    required this.sigma,
    required this.style,
    required this.s0,
    required this.s1,
    required this.y0,
    required this.y1,
    required this.d0,
    required this.dm,
    required this.d1,
    required this.nf,
    required this.len,
    required this.rays,
    required this.wave,
    required this.wave2,
    required this.sway,
    required this.pliancy,
    required this.droop,
    required this.capMix,
    this.tail = false,
    this.flap = 0,
    this.behind = false,
  });

  final _Root root;
  final double sigma; // which side of the body (+1 or -1)
  final int style; // which baked texture
  final double s0, s1, y0, y1; // where the root line sits on the body
  final List<double> d0, dm, d1; // direction of the rays across the fin
  final List<double> nf; // the fin's face
  final List<double> len; // ray length across the fin, 5 knots
  final int rays;
  final List<double> wave; // amp, wave number, beat share, own rate
  final List<double> wave2; // across-ray phase, offset, billow amp, billow rate
  final List<double> sway; // in-plane sway: amp, wave number, beat share, rate
  final double pliancy;
  final List<double> droop;
  final double capMix; // how much of the hood colour the root takes
  final bool tail;
  final double flap; // pectoral sculling, radians
  final bool behind; // always drawn behind the body

  int nu = 0;
  int nv = 0;
  Float64List us = Float64List(0);
  Float64List vs = Float64List(0);
  Float32List pos = Float32List(0);
  Float32List uv = Float32List(0);
  Int32List col = Int32List(0);
  Uint16List index = Uint16List(0);
  EffectQuality? built;
}

List<_Fin> _buildFins() {
  final fins = <_Fin>[];
  // Dorsal: a tall comb of dark rays from mid-back toward the tail stalk.
  fins.add(_Fin(
    root: _Root.dorsal,
    sigma: 1,
    style: 3,
    behind: true,
    s0: 0.5,
    s1: 0.93,
    y0: 0.012,
    y1: 0.008,
    d0: _n3(-0.55, 1, 0),
    dm: _n3(-0.95, 0.8, 0),
    d1: _n3(-1, 0.2, 0),
    nf: const [0.0, 0.0, 1.0],
    len: const [0.37, 0.33, 0.25, 0.16, 0.07],
    rays: 9,
    wave: const [0.45, 2.2, 0.0, 1.31],
    wave2: const [-3.0, 0.0, 0.3, 0.57],
    sway: const [0.28, 1.8, 0.0, 1.03],
    pliancy: 0.45,
    droop: const [-0.4, -0.05, 0.0],
    capMix: 0.25,
  ));
  for (final sg in const [1.0, -1.0]) {
    // Tail: one half on each side of the stalk, forked in the middle.
    fins.add(_Fin(
      root: _Root.tail,
      sigma: sg,
      style: 0,
      tail: true,
      s0: 1.0,
      s1: 1.0,
      y0: 0.062,
      y1: -0.062,
      d0: _n3(-1, 0.22, sg * 0.38),
      dm: _n3(-1, -0.25, sg * 0.18),
      d1: _n3(-0.55, -0.9, sg * 0.4),
      nf: [0.0, 0.0, sg],
      len: const [0.86, 0.9, 0.56, 0.82, 0.72],
      rays: 26,
      wave: const [1.35, 2.4, 1.0, 0.0],
      wave2: [0.5, sg > 0 ? 0.0 : math.pi, 0.28, 0.41],
      sway: const [0.7, 2.2, 1.0, 0.0],
      pliancy: 1,
      droop: const [0.0, -0.5, 0.0],
      capMix: 0.55,
    ));
    // Pectoral: small fans low behind the gill, sculling.
    final pd0 = _n3(-0.2, -0.75, sg * 0.75);
    final pd1 = _n3(-0.75, -0.6, sg * 0.45);
    fins.add(_Fin(
      root: _Root.body,
      sigma: sg,
      style: 2,
      s0: 0.3,
      s1: 0.335,
      y0: -0.42,
      y1: -0.55,
      d0: pd0,
      dm: _n3(-0.45, -0.75, sg * 0.6),
      d1: pd1,
      nf: _nfOf(pd0, pd1),
      len: const [0.2, 0.25, 0.26, 0.22, 0.15],
      rays: 10,
      wave: const [0.6, 2.2, 0.0, 0.0],
      wave2: const [1.2, 0.0, 0.3, 0.79],
      sway: const [0.4, 1.8, 0.0, 1.43],
      pliancy: 0.6,
      droop: const [0.0, -0.1, 0.0],
      capMix: 0.45,
      flap: 0.32,
    ));
    // Pelvic: long paired fins hanging from the belly.
    fins.add(_Fin(
      root: _Root.body,
      sigma: sg,
      style: 1,
      s0: 0.58,
      s1: 0.66,
      y0: -0.93,
      y1: -0.91,
      d0: _n3(-0.15, -1, sg * 0.3),
      dm: _n3(-0.55, -0.9, sg * 0.26),
      d1: _n3(-1, -0.55, sg * 0.2),
      nf: [0.0, 0.0, sg],
      len: const [0.42, 0.46, 0.42, 0.34, 0.22],
      rays: 9,
      wave: const [0.45, 2.2, 0.5, 0.37],
      wave2: [1.4, sg > 0 ? 0.0 : 1.3, 0.3, 0.53],
      sway: const [0.35, 2.0, 0.5, 0.67],
      pliancy: 0.8,
      droop: const [0.0, -0.05, 0.0],
      capMix: 0.35,
    ));
    // Anal: the fancy goldfish's paired anal fins, just ahead of the tail.
    fins.add(_Fin(
      root: _Root.body,
      sigma: sg,
      style: 1,
      s0: 0.84,
      s1: 0.93,
      y0: -0.9,
      y1: -0.85,
      d0: _n3(-0.3, -1, sg * 0.28),
      dm: _n3(-0.75, -0.8, sg * 0.24),
      d1: _n3(-1, -0.35, sg * 0.18),
      nf: [0.0, 0.0, sg],
      len: const [0.4, 0.44, 0.38, 0.3, 0.18],
      rays: 8,
      wave: const [0.65, 2.2, 0.9, 0.0],
      wave2: [0.9, sg > 0 ? 0.4 : 1.9, 0.25, 0.47],
      sway: const [0.4, 2.0, 0.8, 0.0],
      pliancy: 0.9,
      droop: const [0.0, -0.1, 0.0],
      capMix: 0.4,
    ));
  }
  return fins;
}

/// Where the fish is and how it moves, as the fins need to know it.
class PiscesPose {
  double k = 100;
  double cx = 0;
  double cy = 0;
  final Float64List fwd = Float64List(3);
  final Float64List up = Float64List(3);
  final Float64List side = Float64List(3);
  double beat = 0;
  double beatAmp = 0.3;
  double bend = 0;
  double time = 0;
  final Float64List dragBase = Float64List(3);
  final Float64List dragTip = Float64List(3);
  double speedBl = 0;
  double alpha = 1;
  double depth = 1.1;
  double tailScale = 1;
  double sway = 1;
  final Float64List capLin = Float64List(3);
  final Float64List finLin = Float64List(3);
  EffectQuality quality = EffectQuality.medium;

  /// Sideways offset of the spine at s.
  double lat(double s) {
    final sc = math.max(s, 0.0);
    return beatAmp *
            (0.09 * math.pow(sc, 2.2) * math.sin(beat - 3.2 * sc) -
                0.014 * (1 - sc) * math.sin(beat + 0.9)) +
        bend * (1.3 * math.pow(math.max(sc - 0.2, 0.0), 2) - 0.03);
  }

  /// Slope of the spine at s.
  double dlat(double s) {
    final sc = math.max(s, 0.0);
    final s12 = math.pow(math.max(sc, 1e-4), 1.2).toDouble();
    final s22 = s12 * sc;
    final a1 = beat - 3.2 * sc;
    return beatAmp *
            (0.09 * (2.2 * s12 * math.sin(a1) - 3.2 * s22 * math.cos(a1)) +
                0.014 * math.sin(beat + 0.9)) +
        bend * 2.6 * math.max(sc - 0.2, 0.0);
  }
}

/// The fish's fins and tail.
class PiscesFins {
  final List<_Fin> _fins = _buildFins();
  final List<ui.Image?> _images = List<ui.Image?>.filled(4, null);
  final List<ui.ImageShader?> _shaders =
      List<ui.ImageShader?>.filled(4, null);
  final Paint _paint = Paint();
  bool _ready = false;
  bool _disposed = false;

  /// Bakes the ray-and-membrane textures. Fins appear once this is done.
  Future<void> load() async {
    // base alpha, tip alpha, rim, ray tone (negative: dark rays)
    const styles = <(double, double, double, double)>[
      (0.92, 0.24, 0.9, 0.12), // tail
      (0.72, 0.26, 0.7, 0.32), // pelvic and anal
      (0.45, 0.12, 0.6, 0.2), // pectoral
      (0.2, 0.04, 0.25, -1.0), // dorsal
    ];
    for (var i = 0; i < styles.length; i++) {
      final st = styles[i];
      final image = await _bake(st.$1, st.$2, st.$3, st.$4);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[i] = image;
      _shaders[i] = ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.clamp,
        Float64List.fromList(
            <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: FilterQuality.medium,
      );
    }
    _ready = true;
  }

  void dispose() {
    _disposed = true;
    _ready = false;
    for (final s in _shaders) {
      s?.dispose();
    }
    for (final i in _images) {
      i?.dispose();
    }
  }

  /// Draws the fins on one side of the body: those behind it, or those in
  /// front of it.
  void draw(Canvas canvas, PiscesPose p, {required bool near}) {
    if (!_ready) return;
    for (final f in _fins) {
      final isNear = !f.behind && f.sigma * p.side[2] > 0;
      if (isNear != near) continue;
      _ensure(f, p.quality);
      _fill(f, p);
      final verts = ui.Vertices.raw(
        ui.VertexMode.triangles,
        f.pos,
        textureCoordinates: f.uv,
        colors: f.col,
        indices: f.index,
      );
      _paint.shader = _shaders[f.style];
      canvas.drawVertices(verts, ui.BlendMode.modulate, _paint);
      verts.dispose();
    }
  }

  void _ensure(_Fin f, EffectQuality q) {
    if (f.built == q) return;
    f.built = q;
    final big = f.tail;
    final (nu, nv) = switch (q) {
      EffectQuality.low => big ? (14, 40) : (9, 18),
      EffectQuality.medium => big ? (20, 56) : (12, 26),
      EffectQuality.high => big ? (26, 80) : (16, 36),
    };
    f.nu = nu;
    f.nv = nv;
    f.us = Float64List(nu);
    f.vs = Float64List(nv);
    for (var i = 0; i < nu; i++) {
      f.us[i] = math.pow(i / (nu - 1), 1.1).toDouble();
    }
    for (var j = 0; j < nv; j++) {
      f.vs[j] = j / (nv - 1);
    }
    f.pos = Float32List(nu * nv * 2);
    f.col = Int32List(nu * nv);
    f.uv = Float32List(nu * nv * 2);
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        final idx = j * nu + i;
        // 16 px per ray across, and the length of the fin down the texture
        f.uv[idx * 2] = f.vs[j] * f.rays * 16;
        f.uv[idx * 2 + 1] = f.us[i] * 250;
      }
    }
    f.index = Uint16List((nu - 1) * (nv - 1) * 6);
    var q2 = 0;
    for (var j = 0; j < nv - 1; j++) {
      for (var i = 0; i < nu - 1; i++) {
        final a = j * nu + i;
        final b = a + 1;
        final c = a + nu;
        final d = c + 1;
        f.index[q2++] = a;
        f.index[q2++] = b;
        f.index[q2++] = c;
        f.index[q2++] = b;
        f.index[q2++] = d;
        f.index[q2++] = c;
      }
    }
  }

  /// Works out where every vertex of the fin is this frame, and its colour.
  void _fill(_Fin f, PiscesPose p) {
    final nu = f.nu;
    final nv = f.nv;
    final depth = p.depth;
    final sg = f.sigma;

    // The line along the body where the fin is rooted.
    double b0x, b0y, b0z, b1x, b1y, b1z;
    switch (f.root) {
      case _Root.dorsal:
        b0x = 0.5 - f.s0;
        b0y = _centerY(f.s0) + _halfH(f.s0) * depth - f.y0;
        b0z = 0;
        b1x = 0.5 - f.s1;
        b1y = _centerY(f.s1) + _halfH(f.s1) * depth - f.y1;
        b1z = 0;
      case _Root.tail:
        final cyT = _centerY(f.s0);
        b0x = 0.5 - f.s0;
        b1x = b0x;
        b0y = cyT + f.y0;
        b1y = cyT + f.y1;
        b0z = sg * 0.016;
        b1z = b0z;
      case _Root.body:
        final a = _skin(f.s0, f.y0, sg, depth);
        final b = _skin(f.s1, f.y1, sg, depth);
        b0x = a.$1;
        b0y = a.$2;
        b0z = a.$3;
        b1x = b.$1;
        b1y = b.$2;
        b1z = b.$3;
    }

    var d0x = f.d0[0], d0y = f.d0[1], d0z = f.d0[2];
    var dmx = f.dm[0], dmy = f.dm[1], dmz = f.dm[2];
    var d1x = f.d1[0], d1y = f.d1[1], d1z = f.d1[2];
    var nfx = f.nf[0], nfy = f.nf[1], nfz = f.nf[2];
    if (f.flap > 0) {
      // Pectorals scull: the whole fan swings about its root.
      var ax = b1x - b0x, ay = b1y - b0y, az = b1z - b0z;
      final al = math.sqrt(ax * ax + ay * ay + az * az);
      if (al > 1e-9) {
        ax /= al;
        ay /= al;
        az /= al;
      }
      final hover = 1 - _clamp(p.speedBl / 1.5, 0, 1);
      final ang = sg *
          f.flap *
          (0.45 + 0.55 * hover) *
          p.sway *
          math.sin(p.time * 2 * math.pi * 0.85 + (sg > 0 ? 0.0 : 2.2));
      final r0 = _rot(d0x, d0y, d0z, ax, ay, az, ang);
      d0x = r0.$1;
      d0y = r0.$2;
      d0z = r0.$3;
      final rm = _rot(dmx, dmy, dmz, ax, ay, az, ang);
      dmx = rm.$1;
      dmy = rm.$2;
      dmz = rm.$3;
      final r1 = _rot(d1x, d1y, d1z, ax, ay, az, ang);
      d1x = r1.$1;
      d1y = r1.$2;
      d1z = r1.$3;
      final rn = _rot(nfx, nfy, nfz, ax, ay, az, ang);
      nfx = rn.$1;
      nfy = rn.$2;
      nfz = rn.$3;
    }

    final fwd = p.fwd, upv = p.up, sdv = p.side;
    final ls = f.tail ? p.tailScale : 1.0;
    final waveAmp = f.wave[0] * p.sway * (f.tail ? p.beatAmp : 1.0);
    final swayAmp = f.sway[0] * p.sway * (f.tail ? 0.5 + p.beatAmp : 1.0);
    final billow = f.wave2[2] * p.sway;
    // The water the fin feels: quick at the root, slow at the tip.
    final pk = f.pliancy * 0.45;
    final gbx = p.dragBase[0] * pk + f.droop[0];
    final gby = p.dragBase[1] * pk + f.droop[1];
    final gbz = p.dragBase[2] * pk + f.droop[2];
    final gtx = p.dragTip[0] * pk + f.droop[0];
    final gty = p.dragTip[1] * pk + f.droop[1];
    final gtz = p.dragTip[2] * pk + f.droop[2];

    // Colours: the hood's at the root, bleeding out to amber at the margin.
    final cb0 = _mix(p.finLin[0], p.capLin[0], f.capMix);
    final cb1 = _mix(p.finLin[1], p.capLin[1], f.capMix);
    final cb2 = _mix(p.finLin[2], p.capLin[2], f.capMix);
    final cf0 = p.finLin[0] * 0.85;
    final cf1 = p.finLin[1] * 0.62;
    final cf2 = p.finLin[2] * 0.36;

    for (var j = 0; j < nv; j++) {
      final v = f.vs[j];
      final iv = 1 - v;
      var px = b0x + (b1x - b0x) * v;
      var py = b0y + (b1y - b0y) * v;
      var pz = b0z + (b1z - b0z) * v;
      var dx = iv * iv * d0x + 2 * v * iv * dmx + v * v * d1x;
      var dy = iv * iv * d0y + 2 * v * iv * dmy + v * v * d1y;
      var dz = iv * iv * d0z + 2 * v * iv * dmz + v * v * d1z;
      final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
      dx /= dl;
      dy /= dl;
      dz /= dl;
      final nd0 = nfx * dx + nfy * dy + nfz * dz;
      var nx = nfx - dx * nd0;
      var ny = nfy - dy * nd0;
      var nz = nfz - dz * nd0;
      final nl0 = math.sqrt(nx * nx + ny * ny + nz * nz);
      nx /= nl0;
      ny /= nl0;
      nz /= nl0;
      final rayLen = _lenAt(f.len, v) * ls;

      // The body's turn and bend where this ray is rooted.
      final sr = _mix(f.s0, f.s1, v);
      final lat = p.lat(sr);
      final dp = p.dlat(sr);
      final m = 1 / math.sqrt(1 + dp * dp);
      final bx = 0.5 - sr;
      final aByte = _byte(_ss(0, 0.04, v) * (1 - _ss(0.96, 1, v)) * p.alpha);

      for (var i = 0; i < nu; i++) {
        final u = f.us[i];
        if (i > 0) {
          // Walk the ray on: each step bends it out of the fin's plane (a
          // wave running to the tip, plus a slow billow) and toward the
          // water's drag, so the membrane trails and ripples.
          final uPrev = f.us[i - 1];
          final du = u - uPrev;
          final w = 0.5 * (u + uPrev);
          final grow = w * (0.6 + 0.4 * w);
          final ph = p.beat * f.wave[2] +
              p.time * f.wave[3] -
              f.wave[1] * w +
              f.wave2[0] * v +
              f.wave2[1];
          final kn = waveAmp * (0.2 + grow) * math.sin(ph) +
              billow *
                  grow *
                  math.sin(p.time * f.wave2[3] + 2.3 * v + 1.7 * w);
          final kb = swayAmp *
              (0.15 + grow) *
              math.sin(p.beat * f.sway[2] +
                  p.time * f.sway[3] -
                  f.sway[1] * w +
                  1.3 * v +
                  f.wave2[1]);
          final bpx = ny * dz - nz * dy;
          final bpy = nz * dx - nx * dz;
          final bpz = nx * dy - ny * dx;
          final drx = _mix(gbx, gtx, w);
          final dry = _mix(gby, gty, w);
          final drz = _mix(gbz, gtz, w);
          final dd = drx * dx + dry * dy + drz * dz;
          final dpx = drx - dx * dd;
          final dpy = dry - dy * dd;
          final dpz = drz - dz * dd;
          dx += (nx * kn + bpx * kb + dpx * (0.35 + w)) * du;
          dy += (ny * kn + bpy * kb + dpy * (0.35 + w)) * du;
          dz += (nz * kn + bpz * kb + dpz * (0.35 + w)) * du;
          final dl2 = math.sqrt(dx * dx + dy * dy + dz * dz);
          dx /= dl2;
          dy /= dl2;
          dz /= dl2;
          final nd = nx * dx + ny * dy + nz * dz;
          nx -= dx * nd;
          ny -= dy * nd;
          nz -= dz * nd;
          final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
          nx /= nl;
          ny /= nl;
          nz /= nl;
          px += dx * (rayLen * du);
          py += dy * (rayLen * du);
          pz += dz * (rayLen * du);
        }

        // Into the bent body, then onto the screen.
        final relx = px - bx;
        final bX = bx + m * relx + dp * m * pz;
        final bY = py;
        final bZ = lat - dp * m * relx + m * pz;
        final idx = j * nu + i;
        f.pos[idx * 2] =
            p.cx + p.k * (fwd[0] * bX + upv[0] * bY + sdv[0] * bZ);
        f.pos[idx * 2 + 1] =
            p.cy - p.k * (fwd[1] * bX + upv[1] * bY + sdv[1] * bZ);

        // Light: thin fins glow lit from either side.
        final nX = m * nx + dp * m * nz;
        final nY = ny;
        final nZ = -dp * m * nx + m * nz;
        final vnx = fwd[0] * nX + upv[0] * nY + sdv[0] * nZ;
        final vny = fwd[1] * nX + upv[1] * nY + sdv[1] * nZ;
        final vnz = fwd[2] * nX + upv[2] * nY + sdv[2] * nZ;
        final ndl = vnx * _lx + vny * _ly + vnz * _lz;
        final lit = 0.38 + 0.9 * math.max(ndl, 0.0) + 0.55 * math.max(-ndl, 0.0);
        final root = 1 - _ss(0, 0.4, u);
        final r = _mix(cf0, cb0, root) * lit * 1.65;
        final g = _mix(cf1, cb1, root) * lit * 1.65;
        final b = _mix(cf2, cb2, root) * lit * 1.65;
        f.col[idx] =
            (aByte << 24) | (_toneByte(r) << 16) | (_toneByte(g) << 8) | _toneByte(b);
      }
    }
  }
}

/// Draws one tile of rays and membrane: 4 rays across, the length of the fin
/// down. Each ray thickens at the root, forks twice toward the margin and has
/// jointed segments; the margin is scalloped between ray tips.
Future<ui.Image> _bake(
    double aBase, double aTip, double rim, double tone) async {
  const w = 64;
  const h = 256;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..isAntiAlias = false
    ..blendMode = ui.BlendMode.src;
  for (var y = 0; y < h; y++) {
    final u = math.min(1.0, y / 250.0);
    for (var x = 0; x < w; x++) {
      final xr = (x + 0.5) / 16.0;
      final rayId = xr.floor();
      final q = (xr - rayId - 0.5).abs();
      final hw = _mix(0.15, 0.045, u) * (0.88 + 0.24 * _h(rayId + 5.0));
      const aa = 0.07;
      final l1 = 1 - _ss(hw - aa, hw + aa, q);
      final fork1 = _ss(0.38, 0.58, u + 0.1 * (_h(rayId.toDouble()) - 0.5));
      final fork2 = _ss(0.66, 0.86, u + 0.1 * (_h(rayId * 1.7) - 0.5));
      final x2 = (xr * 2) % 1.0;
      final x4 = (xr * 4) % 1.0;
      final l2 = 1 - _ss(hw * 1.1 - aa, hw * 1.1 + aa, (x2 - 0.5).abs());
      final l4 =
          1 - _ss(hw * 1.25 - aa * 2, hw * 1.25 + aa * 2, (x4 - 0.5).abs());
      final rays = _mix(_mix(l1, l2, fork1), l4, fork2);
      final seg = 1 - 0.45 * _ss(0.8, 0.97, (u * 30 + _h(rayId + 3.0)) % 1.0);
      final thick = _vn(u * 6 + rayId * 3.1) * 0.6 +
          _vn(u * 17 + 40 - rayId * 1.3) * 0.4;
      final a = _mix(aBase, aTip, _ss(0, 0.85, u)) * (0.72 + 0.56 * thick);
      final rayA = math.min(1.0, a + 0.32 + 0.25 * math.max(-tone, 0.0));
      var alpha = _mix(a, rayA, rays * seg);

      // The margin: scalloped between ray tips, with a few torn splits.
      final gapId = (xr + 0.5).floor() % 4;
      final gap = _ss(0.2, 0.5, q);
      final tear =
          _h(gapId * 3.3) > 0.84 ? 0.07 + 0.1 * _h(gapId + 9.0) : 0.0;
      final tipU =
          1 - (0.035 * gap + tear * gap + 0.035 * _vn(rayId * 0.9));
      var edge = 1 - _ss(tipU - 0.1, tipU, u);
      edge = math.max(edge, rays * (1 - _ss(tipU - 0.03, tipU + 0.018, u)));
      final rimV = _ss(tipU - 0.14, tipU - 0.02, u) * rim;
      alpha = math.max(alpha, 0.45 * rimV);
      // fade in from the root, so there is no hard line on the body
      alpha *= edge * _ss(0.0, 0.07, u);

      final rayRgb = tone < 0 ? 0.22 : 1.0;
      var rgb = _mix(0.8, rayRgb, rays * seg);
      rgb = _mix(rgb, 1.0, rimV * 0.5);
      paint.color =
          Color.fromARGB(_byte(alpha), _byte(rgb), _byte(rgb), _byte(rgb));
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}