import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const double _tau = math.pi * 2;
const double _deg = math.pi / 180;

// The look, measured from the website.
const double _swell = 0.19;
const double _swellReach = 0.5;
const double _perspective = 10.0;
const double _rimTint = 0.4;
const int _clumps = 18;
const double _sideLean = 0.2;
const double _backFace = 0.07;
const double _backDim = 0.63;
const double _strandAlpha = 0.92;
const double _tint = 0.55;
const double _streakBright = 0.9;
const double _streakSpread = 0.3;
const double _flowRate = 0.066;

// Tuning knobs. If the bundle is too dim or too bright, change _bodyGain
// first. Dashes are the little lights running along the strands.
const double _bodyGain = 0.34;
const double _dashGain = 2.0;
const double _hotGain = 2.6;
const double _fineDashes = 7.0;

const int _pathN = 1024;
const int _poolSize = 160;
const int _maxStreaks = 120;
const int _slots = 4;

/// A bundle of fine glowing fibres twisting round an infinity loop, with
/// light running along them.
///
/// It only animates: no touch, no drag. It has no background unless you give
/// one, so it works over anything dark. Colours come from [baseColor],
/// [lightA] and [lightB].
///
/// ```dart
/// const SizedBox(
///   height: 300,
///   child: Infiloop(lightA: Color(0xFFFFD60A), lightB: Color(0xFFFF3D00)),
/// )
/// ```
class Infiloop extends StatefulWidget {
  /// Creates an infinity loop.
  const Infiloop({
    super.key,
    this.baseColor = const Color(0xFF632EFF),
    this.lightA = const Color(0xFFE070FF),
    this.lightB = const Color(0xFF3A6BFF),
    this.background,
    this.strands = 120,
    this.size = 5.0,
    this.thickness = 5.0,
    this.twist = 2,
    this.strandWidth = 6.0,
    this.glow = 5.0,
    this.brightness = 5.0,
    this.streaks = 94,
    this.streakLength = 5.0,
    this.lightBShare = 2.5,
    this.tilt = 21.0,
    this.angle = 0.0,
    this.sway = 3.0,
    this.breathe = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.speed = 100.0,
    this.reverse = false,
    this.entrance = true,
    this.progress,
    this.seed = 394,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
    this.child,
  });

  /// The middle colour of the fibres. Their dark and bright tones are made
  /// from it.
  final Color baseColor;

  /// The main colour of the light running along the fibres and of the outer
  /// rim of both loops.
  final Color lightA;

  /// The second light colour: a share of the streaks, and the inner rim.
  final Color lightB;

  /// A colour painted behind it. Null leaves it transparent.
  final Color? background;

  /// How many fibres, from 1 to 160. Lower qualities draw fewer.
  final int strands;

  /// How much of the box it fills, from 0 to 10.
  final double size;

  /// How thick the bundle is, from 0 to 10.
  final double thickness;

  /// How many turns the bundle makes round its own axis per loop, 0 to 8.
  final int twist;

  /// How wide each fibre is, from 0.5 to 20.
  final double strandWidth;

  /// The soft bloom round the bundle and the sparkles, from 0 to 10. 0 turns
  /// it off.
  final double glow;

  /// Overall brightness, from 0 to 10. 5 is normal.
  final double brightness;

  /// How many light streaks, from 0 to 120.
  final int streaks;

  /// How long the streaks are, from 0 to 10.
  final double streakLength;

  /// How much of the light is [lightB], from 0 to 10.
  final double lightBShare;

  /// The viewing angle from above, in degrees, from 0 to 60.
  final double tilt;

  /// Turns the whole figure, in degrees. 90 stands it upright.
  final double angle;

  /// How much the fibres drift inside the bundle, from 0 to 10.
  final double sway;

  /// How much it breathes and rocks, from 0 to 10.
  final double breathe;

  /// Moves it across the box, as a percentage of the width, -50 to 50.
  final double offsetX;

  /// Moves it down the box, as a percentage of the height, -50 to 50.
  final double offsetY;

  /// How fast time runs, as a percentage. 100 is normal, 0 freezes it.
  final double speed;

  /// Runs the light the other way round the loop.
  final bool reverse;

  /// Whether the fibres draw themselves on when it appears.
  final bool entrance;

  /// 0 to 1 turns it into a loader: the light fills the loop to that point.
  /// Null is the plain animation.
  final double? progress;

  /// Changes the fibre and streak layout.
  final int seed;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings draw fewer fibres and no glow.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] plays the entrance again.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative.
  final String? semanticLabel;

  /// A widget in the middle, where the loop crosses.
  final Widget? child;

  @override
  State<Infiloop> createState() => _InfiloopState();
}

// ─── The loop's centre line ──────────────────────────────────────────────────

class _PathTable {
  _PathTable(this.x, this.y, this.nx, this.ny, this.s, this.out);

  final Float64List x;
  final Float64List y;
  final Float64List nx;
  final Float64List ny;
  final Float64List s;
  final Float64List out;
}

_PathTable? _pathCache;

/// A lemniscate (half-width 1, y down) resampled evenly by length.
_PathTable _buildPath() {
  final cached = _pathCache;
  if (cached != null) return cached;
  const dn = 4096;
  final ts = Float64List(dn + 1);
  final cum = Float64List(dn + 1);
  var px = 1.0;
  var py = 0.0;
  for (var i = 0; i <= dn; i++) {
    final t = _tau * i / dn;
    final sn = math.sin(t);
    final d = 1 + sn * sn;
    final x = math.cos(t) / d;
    final y = sn * math.cos(t) / d;
    ts[i] = t;
    if (i > 0) {
      final dx = x - px;
      final dy = y - py;
      cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy);
    }
    px = x;
    py = y;
  }
  final total = cum[dn];
  final xs = Float64List(_pathN);
  final ys = Float64List(_pathN);
  final ss = Float64List(_pathN);
  var k = 0;
  for (var j = 0; j < _pathN; j++) {
    final target = total * j / _pathN;
    while (k < dn - 1 && cum[k + 1] < target) {
      k++;
    }
    final span = cum[k + 1] - cum[k];
    final f = (target - cum[k]) / (span == 0 ? 1.0 : span);
    final t = ts[k] + f * (ts[k + 1] - ts[k]);
    final sn = math.sin(t);
    final d = 1 + sn * sn;
    xs[j] = math.cos(t) / d;
    ys[j] = sn * math.cos(t) / d;
    ss[j] = sn;
  }
  final nxs = Float64List(_pathN);
  final nys = Float64List(_pathN);
  final outs = Float64List(_pathN);
  for (var j = 0; j < _pathN; j++) {
    final a = (j + _pathN - 1) % _pathN;
    final b = (j + 1) % _pathN;
    var tx = xs[b] - xs[a];
    var ty = ys[b] - ys[a];
    final l = math.sqrt(tx * tx + ty * ty);
    final inv = l < 1e-12 ? 1.0 : 1 / l;
    tx *= inv;
    ty *= inv;
    final nx = -ty;
    final ny = tx;
    // How much the normal points out of its own loop (outer rim vs inner rim).
    final lc = xs[j] >= 0 ? 0.62 : -0.62;
    final ox = xs[j] - lc;
    final oy = ys[j];
    final ol0 = math.sqrt(ox * ox + oy * oy);
    final ol = ol0 < 1e-12 ? 1.0 : ol0;
    nxs[j] = nx;
    nys[j] = ny;
    outs[j] = ((nx * ox + ny * oy) / ol) * _clamp(xs[j].abs() / 0.2, 0, 1);
  }
  final built = _PathTable(xs, ys, nxs, nys, ss, outs);
  _pathCache = built;
  return built;
}

// ─── The fibres ──────────────────────────────────────────────────────────────

class _Strand {
  double r = 0;
  double th = 0;
  double fray = 0;
  double fp = 0;
  double p1 = 0;
  double p2 = 0;
  double p3 = 0;
  double p4 = 0;
  double ra = 1;
  double rb = 1;
  double shape = 1;
  double lum = 1;
  double hue = 0;
  double dashSpeed = 1;
  double delay = 0;
  int seed = 0;
}

class _Pool {
  _Pool(this.strands, this.streak, this.perm);

  final List<_Strand> strands;

  /// Per streak: start, speed variance, length, colour pick, pulse factor,
  /// pulse phase.
  final Float64List streak;
  final Int32List perm;
}

_Pool _makePool(int seed) {
  final rng = math.Random(seed * 7919 + 13);
  double rnd() => rng.nextDouble();
  final cTh = Float64List(_clumps);
  final cR = Float64List(_clumps);
  final cHue = Float64List(_clumps);
  final cLum = Float64List(_clumps);
  final cPh = Float64List(_clumps);
  for (var c = 0; c < _clumps; c++) {
    cTh[c] = ((c + rnd() * 0.8) / _clumps) * _tau;
    cR[c] = 0.42 + 0.58 * math.sqrt(rnd());
  }
  final hueTurn = rnd() * _tau;
  for (var c = 0; c < _clumps; c++) {
    cPh[c] = rnd() * _tau;
    cHue[c] = 0.95 * math.sin(cTh[c] + hueTurn) + (rnd() - 0.5) * 0.35;
    cLum[c] = 0.08 + 1.4 * math.pow(rnd(), 1.4).toDouble();
  }
  final list = <_Strand>[];
  for (var i = 0; i < _poolSize; i++) {
    final c = i % _clumps;
    final s = _Strand();
    s.r = _clamp(cR[c] + (rnd() - 0.5) * 0.2, 0.06, 1.08);
    s.th = cTh[c] + (rnd() - 0.5) * 0.3;
    s.fray = rnd() < 0.12 ? 0.1 + rnd() * 0.3 : 0.0;
    s.fp = rnd();
    s.p1 = rnd() * _tau;
    s.p2 = rnd() * _tau;
    s.p3 = rnd() * _tau;
    s.p4 = cPh[c] + (rnd() - 0.5) * 0.4;
    s.ra = 0.6 + rnd() * 0.8;
    s.rb = 0.6 + rnd() * 0.8;
    s.shape = 0.7 + rnd() * 0.4;
    s.lum = cLum[c] * (0.7 + 0.3 * rnd());
    s.hue = cHue[c];
    s.dashSpeed = ((0.8 + rnd() * 0.45) * 1000).round() / 1000;
    s.seed = (rnd() * 65536).floor();
    s.delay = rnd();
    list.add(s);
  }
  final streak = Float64List(_maxStreaks * 6);
  for (var j = 0; j < _maxStreaks; j++) {
    streak[j * 6] = rnd();
    streak[j * 6 + 1] = rnd() * 2 - 1;
    streak[j * 6 + 2] = 0.5 + rnd();
    streak[j * 6 + 3] = rnd();
    streak[j * 6 + 4] = 0.55 + rnd() * 0.9;
    streak[j * 6 + 5] = rnd() * _tau;
  }
  final perm = Int32List(_poolSize);
  for (var i = 0; i < _poolSize; i++) {
    perm[i] = i;
  }
  for (var i = _poolSize - 1; i > 0; i--) {
    final j = (rnd() * (i + 1)).floor();
    final t = perm[i];
    perm[i] = perm[j];
    perm[j] = t;
  }
  return _Pool(list, streak, perm);
}

// ─── The state ───────────────────────────────────────────────────────────────

class _InfiloopState extends State<Infiloop> {
  final Paint _ribbon = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = ui.BlendMode.plus;
  final Paint _glowLayer = Paint()..blendMode = ui.BlendMode.plus;
  final Paint _sparkPaint = Paint()..blendMode = ui.BlendMode.plus;
  final Paint _bgPaint = Paint();

  bool _reduced = false;
  double _lastTime = 0;
  double _clock = 0;
  double _flow = 0;
  double _entranceT = 0;
  int _seenResets = 0;
  double _glowSigma = -10;

  // What was built.
  String _builtKey = '';
  int _nStr = 0;
  int _samples = 0;
  List<_Strand> _strands = <_Strand>[];
  Float64List _streak = Float64List(0);
  Int32List _order = Int32List(0);
  Float64List _heads = Float64List(0);

  // Shared by every fibre, per sample along the loop.
  Float64List _kx = Float64List(0);
  Float64List _ky = Float64List(0);
  Float64List _knx = Float64List(0);
  Float64List _kny = Float64List(0);
  Float64List _kout = Float64List(0);

  // Per fibre and sample.
  Float64List _rrC = Float64List(0);
  Float64List _angC = Float64List(0);
  Float64List _ph1C = Float64List(0);
  Float64List _ph2C = Float64List(0);
  Float64List _leanC = Float64List(0);

  // Streak slots, per fibre.
  Float64List _hd = Float64List(0);
  Float64List _am = Float64List(0);
  Float64List _ln = Float64List(0);

  // The picture buffers.
  Float32List _pos = Float32List(0);
  Int32List _col = Int32List(0);
  Uint16List _idx = Uint16List(0);
  Float64List _tx = Float64List(0);
  Float64List _ty = Float64List(0);
  Float64List _te = Float64List(0);

  // Colours.
  final Float64List _cBase = Float64List(3);
  final Float64List _cShade = Float64List(3);
  final Float64List _cLight = Float64List(3);
  final Float64List _cA = Float64List(3);
  final Float64List _cB = Float64List(3);
  final Float64List _dA = Float64List(3);
  final Float64List _dB = Float64List(3);
  final Float64List _e = Float64List(3);
  final Float64List _c3 = Float64List(3);

  // This frame's geometry.
  double _a = 100;
  double _r = 15;
  double _camD = 1000;
  double _cosT = 1;
  double _sinT = 0;
  double _ca = 1;
  double _sa = 0;
  double _cx = 0;
  double _cy = 0;
  double _swayAmt = 0;
  double _swayClock = 0;
  int _twist = 2;

  // Results of the last point worked out.
  double _pX = 0;
  double _pY = 0;
  double _pNx = 0;
  double _pNy = 0;
  double _pOut = 0;
  double _ex = 0;
  double _ey = 0;
  double _efz = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
  }

  @override
  void didUpdateWidget(Infiloop oldWidget) {
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
      _entranceT = 0;
    }
  }

  // ─── Building ──────────────────────────────────────────────────────────────

  void _ensureBuilt() {
    final w = widget;
    final tier = _tier(w.quality);
    final share = const <double>[0.3, 0.55, 0.85][tier];
    final samples = const <int>[48, 72, 96][tier];
    var n = math.max(1, math.min(_poolSize, (math.max(1, math.min(160, w.strands)) * share).round()));
    while (n > 1 && n * (samples + 1) * 3 > 65000) {
      n--;
    }
    final twist = math.max(0, math.min(8, w.twist));
    final key = '$n|$samples|${w.seed}|$twist';
    if (key == _builtKey) return;
    _builtKey = key;
    _build(n, samples, twist);
  }

  void _pathAt(double u) {
    final t = _buildPath();
    final f = (u - u.floorToDouble()) * _pathN;
    var i0 = f.floor();
    if (i0 >= _pathN) i0 = _pathN - 1;
    final fr = f - i0;
    final i1 = i0 + 1 >= _pathN ? 0 : i0 + 1;
    _pX = t.x[i0] + (t.x[i1] - t.x[i0]) * fr;
    _pY = t.y[i0] + (t.y[i1] - t.y[i0]) * fr;
    var nx = t.nx[i0] + (t.nx[i1] - t.nx[i0]) * fr;
    var ny = t.ny[i0] + (t.ny[i1] - t.ny[i0]) * fr;
    final l = math.sqrt(nx * nx + ny * ny);
    if (l > 1e-9) {
      nx /= l;
      ny /= l;
    }
    _pNx = nx;
    _pNy = ny;
    _pOut = t.out[i0] + (t.out[i1] - t.out[i0]) * fr;
  }

  void _build(int n, int samples, int twist) {
    final w = widget;
    _nStr = n;
    _samples = samples;
    final pool = _makePool(w.seed);
    _strands = pool.strands;
    _streak = pool.streak;
    _order = Int32List(n);
    var c = 0;
    for (var i = 0; i < pool.perm.length; i++) {
      if (pool.perm[i] < n) {
        _order[c++] = pool.perm[i];
      }
    }
    _heads = Float64List(_maxStreaks);
    for (var j = 0; j < _maxStreaks; j++) {
      _heads[j] = _streak[j * 6];
    }

    final len = samples + 1;
    _kx = Float64List(len);
    _ky = Float64List(len);
    _knx = Float64List(len);
    _kny = Float64List(len);
    _kout = Float64List(len);
    for (var k = 0; k < len; k++) {
      _pathAt(k / samples);
      _kx[k] = _pX;
      _ky[k] = _pY;
      _knx[k] = _pNx;
      _kny[k] = _pNy;
      _kout[k] = _pOut;
    }

    final total = n * len;
    _rrC = Float64List(total);
    _angC = Float64List(total);
    _ph1C = Float64List(total);
    _ph2C = Float64List(total);
    _leanC = Float64List(total);
    for (var s = 0; s < n; s++) {
      final st = _strands[s];
      for (var k = 0; k < len; k++) {
        final u = k / samples;
        final i = s * len + k;
        final nearX = math.max(0.0, 1 - _kx[k].abs() / _swellReach);
        final cs = math.max(0.0, math.cos(_tau * (u - st.fp)));
        final frr = 1 + st.fray * math.pow(cs, 12).toDouble();
        _rrC[i] = (1 + _swell * nearX) *
            st.r *
            frr *
            (1 + 0.08 * math.sin(_tau * 3 * u + st.p3));
        _angC[i] = st.th + _tau * twist * u;
        _ph1C[i] = _tau * 2 * u + st.p1;
        _ph2C[i] = _tau * 3 * u + st.p2;
        _leanC[i] = st.hue +
            0.35 * math.sin(_tau * 2 * u + 3 * st.p4) -
            _sideLean * _kx[k];
      }
    }

    _pos = Float32List(total * 3 * 2);
    _col = Int32List(total * 3);
    _tx = Float64List(len);
    _ty = Float64List(len);
    _te = Float64List(len * 3);
    _hd = Float64List(_poolSize * _slots);
    _am = Float64List(_poolSize * _slots);
    _ln = Float64List(_poolSize * _slots);

    // Four triangles a segment: left-centre and centre-right, both sides.
    _idx = Uint16List(n * samples * 12);
    var q = 0;
    for (var s = 0; s < n; s++) {
      for (var k = 0; k < samples; k++) {
        final a = (s * len + k) * 3;
        final b = a + 3;
        _idx[q++] = a;
        _idx[q++] = a + 1;
        _idx[q++] = b;
        _idx[q++] = a + 1;
        _idx[q++] = b + 1;
        _idx[q++] = b;
        _idx[q++] = a + 1;
        _idx[q++] = a + 2;
        _idx[q++] = b + 1;
        _idx[q++] = a + 2;
        _idx[q++] = b + 2;
        _idx[q++] = b + 1;
      }
    }
    _entranceT = 0;
  }

  void _setColors(Infiloop w) {
    void put(Float64List o, Color c) {
      o[0] = c.r;
      o[1] = c.g;
      o[2] = c.b;
    }

    put(_cBase, w.baseColor);
    put(_cA, w.lightA);
    put(_cB, w.lightB);
    for (var q = 0; q < 3; q++) {
      _cShade[q] = _cBase[q] * 0.42;
      _cLight[q] = _cBase[q] + (1 - _cBase[q]) * 0.42;
      // The deep version of each light: same hue, less of the minor channels.
      _dA[q] = _cA[q] * _cA[q];
      _dB[q] = _cB[q] * _cB[q];
    }
  }

  /// How visible a fibre is at [u]: the entrance draw-on and the loader fill.
  double _gainAt(double delay, double u, double reveal, double? progress) {
    var gain = 1.0;
    if (reveal < 0.9999) {
      gain = _clamp((reveal * 1.6 - delay * 0.5 - u) / 0.1, 0, 1);
    }
    if (progress != null) {
      gain *= 0.12 + 0.88 * (1 - _smooth(progress - 0.015, progress + 0.015, u));
    }
    return gain;
  }

  /// Works out where a fibre is at any point of the loop, for the sparkles.
  void _evalAt(_Strand st, double u0) {
    final u = u0 - u0.floorToDouble();
    _pathAt(u);
    final nearX = math.max(0.0, 1 - _pX.abs() / _swellReach);
    final cs = math.max(0.0, math.cos(_tau * (u - st.fp)));
    final frr = 1 + st.fray * math.pow(cs, 12).toDouble();
    final rr = _r *
        (1 + _swell * nearX) *
        st.r *
        frr *
        (1 + 0.08 * math.sin(_tau * 3 * u + st.p3));
    final ang = st.th +
        _tau * _twist * u +
        _swayAmt *
            (0.6 * math.sin(_tau * 2 * u + st.p1 + _swayClock * st.ra) +
                0.4 * math.sin(_tau * 3 * u + st.p2 - _swayClock * st.rb));
    final c = math.cos(ang);
    final sn = math.sin(ang);
    final p3x = _pX * _a + _pNx * rr * c;
    final p3y = _pY * _a + _pNy * rr * c;
    final p3z = rr * sn;
    final yv = p3y * _cosT - p3z * _sinT;
    final zv = p3y * _sinT + p3z * _cosT;
    final kk = _camD / math.max(_camD * 0.2, _camD - zv);
    final qx = p3x * kk;
    final qy = yv * kk;
    _ex = qx * _ca - qy * _sa + _cx;
    _ey = qx * _sa + qy * _ca + _cy;
    _efz = _pNy * c * _sinT + sn * _cosT;
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
    _setColors(w);
    final tier = _tier(w.quality);
    final nS = _nStr;
    final n = _samples;
    final len = n + 1;

    _clock += dt;
    final dir = w.reverse ? -1.0 : 1.0;
    _flow = (_flow + dt * _flowRate * dir) % 1000.0;
    if (!w.entrance || _reduced) {
      _entranceT = 10;
    } else {
      _entranceT += dt;
    }
    final et = _clamp(_entranceT / 2.6, 0, 1);
    final reveal = et * et * (3 - 2 * et);
    final double? progress = w.progress == null ? null : _clamp(w.progress!, 0, 1);

    // The figure's place and size.
    final width = size.width;
    final height = size.height;
    final theta = _clamp(w.angle, -180, 180) * _deg;
    final c0 = math.cos(theta);
    final ext = width * c0 * c0 + height * (1 - c0 * c0);
    final fill = 0.3 + _clamp(w.size, 0, 10) / 10 * 0.7;
    final breathe = _clamp(w.breathe, 0, 10);
    final breath = 1 + breathe / 100 * math.sin(_tau * _clock / 9);
    _a = ext * 0.5 * fill / 1.15 * breath;
    _r = _a * _clamp(w.thickness, 0, 10) * 0.03;
    _camD = _perspective * _a;
    final tilt = _clamp(w.tilt, 0, 60) * _deg;
    _cosT = math.cos(tilt);
    _sinT = math.sin(tilt);
    final roll = breathe * 2 * _deg * math.sin(_tau * _clock / 9 * 0.83 + 1.3);
    final ang = theta + roll;
    _ca = math.cos(ang);
    _sa = math.sin(ang);
    _cx = width / 2 + _clamp(w.offsetX, -50, 50) / 100 * width;
    _cy = height / 2 + _clamp(w.offsetY, -50, 50) / 100 * height;
    _swayAmt = _clamp(w.sway, 0, 10) / 10 * 0.9;
    _swayClock = _clock * _tau / 4.5;
    _twist = math.max(0, math.min(8, w.twist));

    final a = _a;
    final R = _r;
    final sf = _clamp(a / 416, 0.55, 1.6);
    final hw = _clamp(w.strandWidth, 0.5, 20) * sf * 1.3;
    final comp = 120 / nS;
    final bright = _clamp(w.brightness, 0, 10) / 5;
    final cyan = _clamp(w.lightBShare, 0, 10) / 10;
    final glowK = _clamp(w.glow, 0, 10) / 5;

    // Streaks: advance them, pulse them, hand each fibre its slots.
    final D = math.min(math.max(0, math.min(_maxStreaks, w.streaks)), nS * _slots);
    final uLen = 0.055 * _clamp(w.streakLength, 0, 10) / 5;
    _am.fillRange(0, _am.length, 0.0);
    for (var j = 0; j < D; j++) {
      final o = j * 6;
      _heads[j] = (_heads[j] +
              dt * _flowRate * (1 + _streakSpread * _streak[o + 1]) * dir) %
          1.0;
      final sid = _order[j % nS];
      final slot = j ~/ nS;
      final pulse =
          0.5 + 0.5 * math.sin(_clock * _tau / (4.0 * _streak[o + 4]) + _streak[o + 5]);
      final amp = _streakBright * (0.2 + 0.8 * pulse) * (_streak[o + 3] < cyan ? -1 : 1);
      _hd[sid * _slots + slot] = _heads[j];
      _am[sid * _slots + slot] = amp;
      _ln[sid * _slots + slot] = math.max(1e-4, uLen * _streak[o + 2]);
    }

    // The fibres.
    for (var s = 0; s < nS; s++) {
      final st = _strands[s];
      final base = s * len;
      final slotBase = s * _slots;
      var hasStreak = false;
      for (var q = 0; q < _slots; q++) {
        if (_am[slotBase + q] != 0) {
          hasStreak = true;
          break;
        }
      }

      for (var k = 0; k <= n; k++) {
        final idx = base + k;
        final u = k / n;

        // Position.
        final sang = _angC[idx] +
            _swayAmt *
                (0.6 * math.sin(_ph1C[idx] + _swayClock * st.ra) +
                    0.4 * math.sin(_ph2C[idx] - _swayClock * st.rb));
        final cs = math.cos(sang);
        final sn = math.sin(sang);
        final rr = _rrC[idx] * R;
        final p3x = _kx[k] * a + _knx[k] * rr * cs;
        final p3y = _ky[k] * a + _kny[k] * rr * cs;
        final p3z = rr * sn;
        final yv = p3y * _cosT - p3z * _sinT;
        final zv = p3y * _sinT + p3z * _cosT;
        final kk = _camD / math.max(_camD * 0.2, _camD - zv);
        final qx = p3x * kk;
        final qy = yv * kk;
        _tx[k] = qx * _ca - qy * _sa + _cx;
        _ty[k] = qx * _sa + qy * _ca + _cy;

        final gain = _gainAt(st.delay, u, reveal, progress);
        if (gain < 0.002) {
          _te[k * 3] = 0;
          _te[k * 3 + 1] = 0;
          _te[k * 3 + 2] = 0;
          continue;
        }

        // Light and colour.
        final fy = _kny[k] * cs * _cosT - sn * _sinT;
        final fz = _kny[k] * cs * _sinT + sn * _cosT;
        final lit0 = 0.6 * (0.5 + 0.5 * fz) + 0.4 * (0.5 - 0.5 * _clamp(fy, -1, 1));
        final lit = _clamp(lit0 * st.shape, 0, 1);
        final face = _backFace + (1 - _backFace) * _smooth(-0.7, 0.4, fz);
        final lean = _leanC[idx];
        final wb = 1 - _smooth(-0.5, -0.1, lean);
        final wv = _smooth(0.1, 0.5, lean);
        final outer = _kout[k] * cs;
        final rimA = _smooth(0.2, 1.0, outer);
        final rimB = _smooth(0.2, 1.0, -outer);
        final bandA = math.max(0.0, math.sin(_tau * 2 * u - _tau * 2 * _flow + st.p4 + 0.4));
        final bandB = math.max(0.0, math.sin(_tau * 3 * u - _tau * 3.3 * _flow + st.p4 + 2.1));
        final wA = bandA * bandA * _tint;
        final wB = bandB * bandB * bandB * _tint * (cyan / 0.25) * 0.8;
        final wM = _clamp(math.max(wA, wB), 0, 1);
        final bandDeep = wB > wA ? _dB : _dA;
        for (var q = 0; q < 3; q++) {
          final midB = _cBase[q] + (_dB[q] - _cBase[q]) * wb;
          final midA = _cBase[q] + (_dA[q] - _cBase[q]) * 0.5;
          final mid = midB + (midA - midB) * wv;
          var cc = lit < 0.6
              ? _cShade[q] + (mid - _cShade[q]) * (lit / 0.6)
              : mid + (_cLight[q] - mid) * ((lit - 0.6) / 0.4 * 0.35);
          cc += (_dA[q] - cc) * (rimA * _rimTint * (0.4 + 0.6 * lit));
          cc += (_dB[q] - cc) * (rimB * _rimTint * (0.4 + 0.6 * lit));
          cc += (bandDeep[q] - cc) * (wM * (0.3 + 0.4 * lit));
          _c3[q] = cc;
        }
        final dim = 1 - _backDim * math.max(0.0, 1 - (u - 0.25).abs() / 0.1);
        final vLum = _strandAlpha *
            st.lum *
            face *
            (0.15 + 0.85 * lit) *
            (1 + 0.4 * wM) *
            dim;
        final bodyK = _bodyGain * comp * vLum * bright;
        _e[0] = _c3[0] * bodyK;
        _e[1] = _c3[1] * bodyK;
        _e[2] = _c3[2] * bodyK;

        // Little lights running along the fibre.
        final cp = u * _fineDashes -
            _flow * _fineDashes * st.dashSpeed +
            _h01(st.seed, 3);
        final ci = cp.floorToDouble();
        final f = cp - ci;
        final cell = ci.toInt();
        final r1 = _h01(cell, st.seed);
        final r2 = _h01(cell + 7919, st.seed + 31);
        final dl = 0.35 + 0.55 * r2;
        final x = (f - (1 - dl)) / dl;
        if (x > 0 && r1 > 0.2) {
          final dash = math.pow(x, 1.3).toDouble() * _smooth(0.2, 0.9, r1);
          final hot = math.pow(x, 14).toDouble() * _smooth(0.7, 1.0, r1);
          final r3 = _h01(cell + 104729, st.seed + 77);
          final core = vLum * comp * bright;
          for (var q = 0; q < 3; q++) {
            final double dc;
            if (r3 < 0.22) {
              dc = _cA[q];
            } else if (r3 < 0.42) {
              dc = _cB[q] + (_cLight[q] - _cB[q]) * 0.2;
            } else {
              dc = _c3[q] * 1.3;
            }
            _e[q] += (dc * dash * _dashGain + (dc + 1) * 0.5 * hot * _hotGain) * core;
          }
        }

        // Light streaks: a hot head with a trail behind it.
        if (hasStreak) {
          for (var q = 0; q < _slots; q++) {
            final amp = _am[slotBase + q];
            if (amp == 0) continue;
            var d = _hd[slotBase + q] - u;
            d -= d.floorToDouble();
            final L = _ln[slotBase + q];
            final tr = math.exp(-d / L);
            final hd = math.exp(-d / math.max(0.12 * L, 1.0 / n));
            final aa = amp.abs() * face * dim * bright;
            final lc = amp > 0 ? _cA : _cB;
            for (var ch = 0; ch < 3; ch++) {
              _e[ch] += (lc[ch] * tr + (lc[ch] + (1 - lc[ch]) * 0.55) * hd) * aa;
            }
          }
        }

        // The loader's bright leading edge.
        if (progress != null && progress > 0 && progress < 1) {
          final dd = u - progress;
          final lead = math.exp(-(dd * dd) / (2 * 0.012 * 0.012));
          final lk = lead * 0.25 * comp * face * bright;
          for (var ch = 0; ch < 3; ch++) {
            _e[ch] += (_cA[ch] * 0.7 + 0.3) * lk;
          }
        }

        _te[k * 3] = _e[0] * gain;
        _te[k * 3 + 1] = _e[1] * gain;
        _te[k * 3 + 2] = _e[2] * gain;
      }

      // Second pass: turn the points into ribbons, with the tangent from the
      // neighbours (the loop is closed, so the ends wrap round).
      for (var k = 0; k <= n; k++) {
        final kp = k == 0 ? n - 1 : k - 1;
        final kn = k == n ? 1 : k + 1;
        var tx = _tx[kn] - _tx[kp];
        var ty = _ty[kn] - _ty[kp];
        final l = math.sqrt(tx * tx + ty * ty);
        if (l < 1e-6) {
          tx = 1;
          ty = 0;
        } else {
          tx /= l;
          ty /= l;
        }
        final nx = -ty * hw;
        final ny = tx * hw;
        final vi = (base + k) * 3;
        _pos[vi * 2] = (_tx[k] - nx);
        _pos[vi * 2 + 1] = (_ty[k] - ny);
        _pos[(vi + 1) * 2] = _tx[k];
        _pos[(vi + 1) * 2 + 1] = _ty[k];
        _pos[(vi + 2) * 2] = (_tx[k] + nx);
        _pos[(vi + 2) * 2 + 1] = (_ty[k] + ny);

        final r = _te[k * 3];
        final g = _te[k * 3 + 1];
        final b = _te[k * 3 + 2];
        final m = math.max(r, math.max(g, b));
        var packed = 0;
        if (m > 0.002) {
          final tm = 1 - math.exp(-m);
          final wh = _smooth(0.9, 3.0, m) * 0.55;
          final nr = r / m;
          final ng = g / m;
          final nb = b / m;
          packed = (_b8(tm) << 24) |
              (_b8(nr + (1 - nr) * wh) << 16) |
              (_b8(ng + (1 - ng) * wh) << 8) |
              _b8(nb + (1 - nb) * wh);
        }
        _col[vi] = 0;
        _col[vi + 1] = packed;
        _col[vi + 2] = 0;
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (w.background != null) {
      _bgPaint.color = w.background!;
      canvas.drawRect(Offset.zero & size, _bgPaint);
    }

    final nv = nS * len * 3;
    final ni = nS * n * 12;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, 0, nv * 2),
      colors: Int32List.sublistView(_col, 0, nv),
      indices: Uint16List.sublistView(_idx, 0, ni),
    );

    // The soft bloom: the same fibres, blurred, added on top.
    if (tier > 0 && glowK > 0) {
      final sigma = 7 * sf;
      if ((sigma - _glowSigma).abs() > 0.25) {
        _glowSigma = sigma;
        _glowLayer.imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: ui.TileMode.decal,
        );
      }
      _glowLayer.color =
          Color.fromARGB(_b8(_clamp(0.35 * glowK, 0, 0.9)), 255, 255, 255);
      canvas.saveLayer(
        Rect.fromCircle(center: Offset(_cx, _cy), radius: a * 1.5 + R * 2),
        _glowLayer,
      );
      canvas.drawVertices(vertices, ui.BlendMode.modulate, _ribbon);
      canvas.restore();
    }
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _ribbon);
    vertices.dispose();

    // Sparkles on the brightest streak heads.
    if (tier > 0 && D > 0 && glowK > 0) {
      final haloR = 7 * sf;
      final coreR = 1.3 * sf;
      for (var j = 0; j < D; j++) {
        final sid = _order[j % nS];
        final slot = j ~/ nS;
        final amp = _am[sid * _slots + slot];
        final pk = amp.abs() / _streakBright;
        final inten = pk * pk * pk * pk * pk;
        if (inten < 0.03) continue;
        final st = _strands[sid];
        final u = _hd[sid * _slots + slot];
        final gain = _gainAt(st.delay, u, reveal, progress);
        if (gain < 0.05) continue;
        _evalAt(st, u);
        final face = 0.25 + 0.75 * _smooth(-0.7, 0.4, _efz);
        final kv = _clamp(inten * face * gain * bright * glowK, 0, 1);
        if (kv < 0.02) continue;
        final lc = amp > 0 ? _cA : _cB;
        final r = lc[0] + (_cA[0] - lc[0]) * 0.6;
        final g = lc[1] + (_cA[1] - lc[1]) * 0.6;
        final b = lc[2] + (_cA[2] - lc[2]) * 0.6;
        final r8 = _b8(r);
        final g8 = _b8(g);
        final b8 = _b8(b);
        final at = Offset(_ex, _ey);
        _sparkPaint.color = Color.fromARGB(_b8(kv * 0.28), r8, g8, b8);
        canvas.drawCircle(at, haloR, _sparkPaint);
        _sparkPaint.color = Color.fromARGB(_b8(kv * 0.43), r8, g8, b8);
        canvas.drawCircle(at, haloR * 0.55, _sparkPaint);
        _sparkPaint.color = Color.fromARGB(_b8(kv * 0.63), r8, g8, b8);
        canvas.drawCircle(at, haloR * 0.28, _sparkPaint);
        _sparkPaint.color = Color.fromARGB(
          _b8(kv),
          _b8((r + 1) * 0.5),
          _b8((g + 1) * 0.5),
          _b8((b + 1) * 0.5),
        );
        canvas.drawCircle(at, coreR, _sparkPaint);
      }
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget;

    final Widget host = IgnorePointer(
      child: RepaintBoundary(
        child: EffectHost(
          onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
          paused: w.paused,
          interactive: false,
          rotatesOnDrag: false,
          quality: w.quality,
          controller: w.controller,
          background: null,
          semanticLabel: w.semanticLabel,
        ),
      ),
    );

    final child = w.child;
    if (child == null) return host;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[host, Center(child: child)],
    );
  }
}

// ─── Small maths ─────────────────────────────────────────────────────────────

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

int _b8(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).round());

/// A repeatable number from 0 to 1 for two whole numbers. It uses sin and not
/// bit tricks, so it gives the same answer on the web as on a phone.
double _h01(int a, int b) {
  final v = math.sin(a * 127.1 + b * 311.7) * 43758.5453;
  return v - v.floorToDouble();
}