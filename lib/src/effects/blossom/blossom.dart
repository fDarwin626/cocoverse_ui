import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const double _tau = math.pi * 2;
const double _deg = math.pi / 180;

// The flower's width as a share of the frame's short side, its width in world
// units (the flower's radius is 1), and the camera's view.
const double _fitShare = 0.38;
const double _flowerWidth = 2.05;
const double _fov = 28 * _deg;
const double _targetY = -0.08;
const double _elevation = 38 * _deg;

// The lamp hidden among the inner petals, and the cool light the sheen
// reflects (a unit vector).
const double _lampRef = 1.0;
const double _lampFalloff = 20;
const double _fillShare = 0.3;
const double _fillFalloff = 5;
const double _keyX = -0.8437;
const double _keyY = 0.4467;
const double _keyZ = 0.2978;

// The seed dome and the receptacle under the petals.
const double _podCenterY = 0.22;
const double _podR = 0.21;
const int _podBeads = 46;
const double _receptacleY = -0.2;
const double _receptacleR = 0.2;
const double _podCap = 80 * _deg;

// How far a closed bud's petals curl inward over their length.
const double _budBend = 1.05;

// Where the flower sits when it is fully closed.
const double _entryScale = 0.82;
const double _entryTurn = 0.6;

const List<Color> _defaultColors = <Color>[
  Color(0xFFFF9AAA),
  Color(0xFFFFD08A),
  Color(0xFF8C9CFF),
];

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

double _smoothstep(double edge0, double edge1, double x) {
  final t = _clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

double _smooth01(double x) {
  final t = _clamp(x, 0, 1);
  return t * t * (3 - 2 * t);
}

/// sRGB (0 to 1) to linear light.
double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// A filmic curve that keeps very bright light from clipping flat.
double _aces(double x) {
  final v = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
  return _clamp(v, 0, 1);
}

double _encode(double x) => math.pow(x, 1 / 2.2).toDouble();

/// A glow colour that is clear where it is dark: its brightest channel is its
/// opacity, so the glow adds light and never adds black.
int _packGlow(double r, double g, double b) {
  final peak = math.max(r, math.max(g, b));
  if (peak < 0.004) return 0;
  return (_byte(peak) << 24) |
      (_byte(r / peak) << 16) |
      (_byte(g / peak) << 8) |
      _byte(b / peak);
}

int _byte(double v) => (_clamp(v, 0, 1) * 255).round();

int _pack(double r, double g, double b) =>
    0xFF000000 | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);

/// A small repeatable stream of numbers from 0 to 1.
class _Rng {
  _Rng(this._n);

  double _n;

  double next() {
    _n += 1;
    final v = math.sin(_n * 12.9898 + 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }
}

/// One whorl of petals. Angles are in degrees, from vertical. A petal's spine
/// leaves its base at [tilt] and turns [bend] radians upward along its length.
class _Layer {
  const _Layer(
    this.share,
    this.tilt,
    this.bend,
    this.length,
    this.width,
    this.cup,
    this.r0,
    this.h0,
    this.bud,
    this.curl,
  );

  final double share;
  final double tilt;
  final double bend;
  final double length;
  final double width;
  final double cup;
  final double r0;
  final double h0;
  final double bud;
  final double curl;
}

// Outermost whorl first.
const List<_Layer> _layers = <_Layer>[
  _Layer(1, 92, 0.6, 0.95, 0.28, 0.55, 0.12, -0.26, 34, 0.5),
  _Layer(1, 55, 0.7, 0.9, 0.26, 0.65, 0.12, -0.2, 26, 0.8),
  _Layer(0.875, 28, 0.4, 0.8, 0.22, 0.75, 0.17, -0.12, 17, 1),
  _Layer(0.625, 30, 0.3, 0.36, 0.17, 0.8, 0.22, -0.04, 9, 0.6),
];

/// The full description of one petal.
class _Petal {
  _Petal({
    required this.phi,
    required this.tilt,
    required this.length,
    required this.width,
    required this.cup,
    required this.bend,
    required this.r0,
    required this.h0,
    required this.seed,
    required this.layer,
    required this.bud,
    required this.curl,
  });

  final double phi;
  final double tilt;
  final double length;
  final double width;
  final double cup;
  final double bend;
  final double r0;
  final double h0;
  final double seed;
  final int layer;
  final double bud;
  final double curl;
}

List<_Petal> _buildPetals(int count, int layers) {
  final rng = _Rng(3 * 7919.0 + 13);
  final used = math.min(_layers.length, math.max(1, layers));
  final first = _layers.length - used;
  final petals = <_Petal>[];
  for (var li = first; li < _layers.length; li++) {
    final layer = _layers[li];
    final n = math.max(3, (math.min(16, math.max(3, count)) * layer.share).round());
    final step = _tau / n;
    final offset = li * 0.5 * step + (rng.next() - 0.5) * 0.3 * step;
    for (var j = 0; j < n; j++) {
      final phi = offset + j * step + (rng.next() - 0.5) * 0.14 * step;
      final tilt = (layer.tilt + (rng.next() - 0.5) * 8) * _deg;
      final length = layer.length * (1 + (rng.next() - 0.5) * 0.12);
      final width = layer.width * (1 + (rng.next() - 0.5) * 0.12);
      // Every other petal sits a touch outside its neighbours, so overlapping
      // edges pass in front instead of through each other.
      final stagger = j.isOdd ? 0.022 : 0.0;
      final seed = rng.next();
      petals.add(
        _Petal(
          phi: phi,
          tilt: tilt,
          length: length,
          width: width,
          cup: layer.cup,
          bend: layer.bend,
          r0: layer.r0 + stagger,
          h0: layer.h0 - stagger,
          seed: seed,
          layer: li,
          bud: layer.bud * _deg,
          curl: layer.curl,
        ),
      );
    }
  }
  return petals;
}

/// The seed dome: beads packed by golden angle on a cap.
class _Pod {
  _Pod()
      : dirX = Float64List(_podBeads),
        dirY = Float64List(_podBeads),
        dirZ = Float64List(_podBeads),
        radius = Float64List(_podBeads),
        seed = Float64List(_podBeads) {
    final rng = _Rng(3 * 104729.0 + 7);
    final golden = math.pi * (3 - math.sqrt(5));
    final cosMax = math.cos(_podCap);
    for (var i = 0; i < _podBeads; i++) {
      final ct = 1 - ((i + 0.5) / _podBeads) * (1 - cosMax);
      final st = math.sqrt(1 - ct * ct);
      final psi = i * golden;
      dirX[i] = st * math.cos(psi);
      dirY[i] = ct;
      dirZ[i] = st * math.sin(psi);
      final theta = math.acos(ct);
      radius[i] =
          _podR * (0.3 - 0.1 * (theta / _podCap)) * (0.9 + 0.2 * rng.next());
      seed[i] = rng.next();
    }
  }

  final Float64List dirX;
  final Float64List dirY;
  final Float64List dirZ;
  final Float64List radius;
  final Float64List seed;
}

/// Faint specks that drift upward past the flower.
class _Motes {
  _Motes(this.count)
      : x = Float64List(count),
        y = Float64List(count),
        z = Float64List(count),
        s = Float64List(count) {
    final rng = _Rng(3 * 31337.0 + 5);
    for (var i = 0; i < count; i++) {
      x[i] = (rng.next() * 2 - 1) * 3.6;
      y[i] = (rng.next() * 2 - 1) * 3.0;
      z[i] = (rng.next() * 2 - 1) * 2.5;
      s[i] = rng.next();
    }
  }

  final int count;
  final Float64List x;
  final Float64List y;
  final Float64List z;
  final Float64List s;
}

/// A lotus cast in pink resin and lit from inside, that opens from a bud.
///
/// There are three ways to open it:
///
/// * **Tap.** By default, tapping the flower opens it, and tapping again
///   closes it.
/// * **Progress.** Set [open] from 0 to 1 and the flower eases to that point
///   each time the value changes, so it can open a little as each step of
///   something is finished.
/// * **Splash.** Set [autoOpen] and the flower opens on its own as soon as it
///   appears, over [openDuration], following [curve]. [onOpened] tells you
///   when it is fully open.
///
/// It fills the space its parent gives it.
class Blossom extends StatefulWidget {
  /// Creates a blossom.
  const Blossom({
    super.key,
    this.colors = _defaultColors,
    this.petals = 14,
    this.layers = 4,
    this.size = 1.0,
    this.glow = 1.0,
    this.bloom = 1.0,
    this.motes = 24,
    this.open,
    this.openOnTap = true,
    this.autoOpen = false,
    this.openDuration = const Duration(milliseconds: 3400),
    this.curve = Curves.easeInOut,
    this.onOpened,
    this.tilt = 1.0,
    this.float = 1.0,
    this.spin = 1.0,
    this.background,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Three colours: the resin of the petals, the light of the lamp inside, and
  /// the cool sheen on the coating. Missing colours keep their defaults.
  final List<Color> colors;

  /// Petals in each of the outer whorls, from 3 to 16. The inner whorls carry
  /// fewer.
  final int petals;

  /// Whorls of petals round the dome, from 1 to 4, counted from the inside.
  final int layers;

  /// Size of the flower, where 1.0 is the default.
  final double size;

  /// Brightness of the lamp inside the flower, where 1.0 is the default.
  final double glow;

  /// How strongly bright light spills past the petals, where 1.0 is the
  /// default. 0 turns it off, which is also the cheapest to draw.
  final double bloom;

  /// How many faint specks drift past. 0 turns them off.
  final int motes;

  /// How open the flower is, from 0 (a closed bud) to 1 (fully open). When it
  /// is set, the flower eases to the value every time it changes, and taps no
  /// longer open it. Null leaves the flower to taps or [autoOpen].
  final double? open;

  /// Whether tapping the flower opens it and closes it again. It has no effect
  /// while [open] is set.
  final bool openOnTap;

  /// Opens the flower on its own as soon as it appears, like a splash screen.
  /// It has no effect while [open] is set.
  final bool autoOpen;

  /// How long a full opening, from closed to open, takes. A smaller change
  /// takes a proportionally shorter time, but never under a third of a second.
  final Duration openDuration;

  /// The easing of every opening and closing.
  final Curve curve;

  /// Called once each time the flower finishes opening fully.
  final VoidCallback? onOpened;

  /// How far the flower leans toward the pointer, where 1.0 is the default.
  final double tilt;

  /// How much the flower bobs and sways, where 1.0 is the default.
  final double float;

  /// How fast the flower turns on its own. Negative turns the other way.
  final double spin;

  /// transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the flower: the lean, the glow under a finger and
  /// the tap.
  final bool interactive;

  /// Level of detail. Low draws a coarse petal mesh and a single glow layer,
  /// medium a finer mesh and two glow layers, and high the finest mesh.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the opening again.
  final EffectController? controller;

  /// Screen-reader description. Null marks the flower as decorative.
  final String? semanticLabel;

  @override
  State<Blossom> createState() => _BlossomState();
}

class _BlossomState extends State<Blossom> {
  final Paint _paint = Paint();
  final Paint _fillPaint = Paint();
  final Paint _motePaint = Paint()..blendMode = BlendMode.plus;
  final _Pod _pod = _Pod();
  _Motes _motes = _Motes(0);
  int _moteCount = -1;

  List<_Petal> _petalList = <_Petal>[];
  int _builtKey = 0;
  int _gridU = 0;
  int _gridV = 0;
  Float64List _pos = Float64List(0);
  Float64List _nor = Float64List(0);
  Float32List _xy = Float32List(0);
  Int32List _col = Int32List(0);
  Int32List _bloomCol = Int32List(0);
  Uint16List _indices = Uint16List(0);
  Float64List _depth = Float64List(0);
  List<int> _order = <int>[];
  Float64List _spR = Float64List(0);
  Float64List _spH = Float64List(0);
  Float64List _spCos = Float64List(0);
  Float64List _spSin = Float64List(0);
  Float64List _spW = Float64List(0);
  Float64List _spLift = Float64List(0);

  // Index 0 is the dome's core, 1 to 46 are the beads.
  final Float64List _beadX = Float64List(_podBeads + 1);
  final Float64List _beadY = Float64List(_podBeads + 1);
  final Float64List _beadR = Float64List(_podBeads + 1);
  final Float64List _beadDepth = Float64List(_podBeads + 1);
  final Int32List _beadMain = Int32List(_podBeads + 1);
  final Int32List _beadBloom = Int32List(_podBeads + 1);
  final List<int> _beadOrder = List<int>.generate(_podBeads, (i) => i + 1);
  double _recX = 0;
  double _recY = 0;
  double _recR = 0;
  int _recColor = 0;

  // The opening: eased from one value to another over time.
  bool _started = false;
  double _lastTime = 0;
  double _value = 0;
  double _from = 0;
  double _to = 0;
  double _tweenT = 1;
  double _tweenSeconds = 1;
  bool _opened = false;

  double _px = 0;
  double _py = 0;
  double _hover = 0;

  // Per-frame values the shading reads.
  double _eyeX = 0;
  double _eyeY = 0;
  double _eyeZ = 0;
  double _midX = 0;
  double _midY = 0;
  double _f = 1;
  double _sinEl = 0;
  double _cosEl = 1;
  double _lampX = 0;
  double _lampY = 0;
  double _lampZ = 0;
  double _lamp = 0;
  double _lightR = 1;
  double _lightG = 1;
  double _lightB = 1;
  double _fillR = 1;
  double _fillG = 1;
  double _fillB = 1;
  double _sheenR = 1;
  double _sheenG = 1;
  double _sheenB = 1;
  double _lnR = 0;
  double _lnG = 0;
  double _lnB = 0;
  double _sqR = 1;
  double _sqG = 1;
  double _sqB = 1;
  bool _bloomOn = true;
  double _projX = 0;
  double _projY = 0;
  double _projDepth = 1;
  int _outMain = 0;
  int _outBloom = 0;

  @override
  void didUpdateWidget(Blossom oldWidget) {
    super.didUpdateWidget(oldWidget);
    final open = widget.open;
    if (open != null && open != oldWidget.open) {
      _retarget(_clamp(open, 0, 1));
    }
  }

  void _onTap() {
    if (!widget.interactive || !widget.openOnTap || widget.open != null) {
      return;
    }
    _retarget(_to > 0.5 ? 0.0 : 1.0);
  }

  /// Starts the opening over, from closed.
  void _begin() {
    _value = 0;
    _from = 0;
    _to = 0;
    _tweenT = 1;
    _tweenSeconds = 1;
    _opened = false;
    final open = widget.open;
    if (open != null) {
      _retarget(_clamp(open, 0, 1));
    } else if (widget.autoOpen) {
      _retarget(1);
    }
  }

  /// Eases from wherever the flower is now to a new value.
  void _retarget(double to) {
    if ((to - _to).abs() < 1e-4) return;
    _from = _value;
    _to = to;
    _tweenT = 0;
    _opened = false;
    final change = (to - _from).abs();
    final full = widget.openDuration.inMicroseconds / 1e6;
    _tweenSeconds = math.max(0.35, full * change);
  }

  void _rebuild(int petals, int layers, int gridU, int gridV) {
    final key = Object.hash(petals, layers, gridU, gridV);
    if (key == _builtKey && _petalList.isNotEmpty) return;
    _builtKey = key;
    _gridU = gridU;
    _gridV = gridV;
    _petalList = _buildPetals(petals, layers);
    final count = _petalList.length;
    final per = (gridU + 1) * (gridV + 1);
    _pos = Float64List(count * per * 3);
    _nor = Float64List(per * 3);
    _xy = Float32List(count * per * 2);
    _col = Int32List(count * per);
    _bloomCol = Int32List(count * per);
    _indices = Uint16List(count * gridU * gridV * 6);
    _depth = Float64List(count + 1);
    _order = List<int>.generate(count + 1, (i) => i);
    _spR = Float64List(gridU + 1);
    _spH = Float64List(gridU + 1);
    _spCos = Float64List(gridU + 1);
    _spSin = Float64List(gridU + 1);
    _spW = Float64List(gridU + 1);
    _spLift = Float64List(gridU + 1);
  }

  /// Camera space: fills [_projX] and [_projY] (pixels) and [_projDepth].
  void _project(double x, double y, double z) {
    final dx = x - _eyeX;
    final dy = y - _eyeY;
    final dz = z - _eyeZ;
    final depth = math.max(0.05, -dy * _sinEl - dz * _cosEl);
    final yc = dy * _cosEl - dz * _sinEl;
    _projX = _midX + _f * dx / depth;
    _projY = _midY - _f * yc / depth;
    _projDepth = depth;
  }

  /// Lights one point of the resin. Writes [_outMain], the colour drawn, and
  /// [_outBloom], the part of it bright enough to spill past the petals.
  void _shade(
    double px,
    double py,
    double pz,
    double nxIn,
    double nyIn,
    double nzIn,
    double u,
    double av,
    double seed,
    double ao,
    bool pod,
    bool faceOn,
  ) {
    var vx = _eyeX - px;
    var vy = _eyeY - py;
    var vz = _eyeZ - pz;
    final vInv = 1 / math.max(math.sqrt(vx * vx + vy * vy + vz * vz), 1e-6);
    vx *= vInv;
    vy *= vInv;
    vz *= vInv;

    var nx = nxIn;
    var ny = nyIn;
    var nz = nzIn;
    if (faceOn || nx * nx + ny * ny + nz * nz < 0.25) {
      nx = vx;
      ny = vy;
      nz = vz;
    }
    // A thin sheet: shade whichever face is toward the eye.
    var nDotV = nx * vx + ny * vy + nz * vz;
    if (nDotV < 0) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
      nDotV = -nDotV;
    }
    final noV = math.max(nDotV, 0.001);

    final lx0 = _lampX - px;
    final ly0 = _lampY - py;
    final lz0 = _lampZ - pz;
    final d2 = lx0 * lx0 + ly0 * ly0 + lz0 * lz0;
    final dl = math.sqrt(d2);
    final lInv = 1 / math.max(dl, 1e-4);
    final lx = lx0 * lInv;
    final ly = ly0 * lInv;
    final lz = lz0 * lInv;
    final noL = nx * lx + ny * ly + nz * lz;
    final lampK = _lamp / (1 + d2 * _lampFalloff);
    final lampR = _lightR * lampK;
    final lampG = _lightG * lampK;
    final lampB = _lightB * lampK;

    // Resin is heavier in the nib and at the base; the outline pipes light.
    final tipT = pod ? 0.0 : _smoothstep(0.8, 1.0, u);
    const rimW = 0.26;
    final rim = pod
        ? 0.0
        : _smoothstep(0.97 - rimW, 0.97, av) * (0.13 / rimW) * (1 - 0.5 * tipT);
    final double thick;
    if (pod) {
      thick = 1.15;
    } else {
      final iu = 1 - u;
      thick = 0.8 + 1.1 * tipT + 0.6 * iu * iu * iu + 0.03;
    }

    // Light that crossed more resin is deeper rose.
    var path = thick / math.max(noV, 0.45);
    // Resin right by the lamp is lit through its near skin only.
    path *= 0.15 + 0.85 * _smoothstep(0.08, 0.6, dl);
    final deepR = math.exp(path * _lnR);
    final deepG = math.exp(path * _lnG);
    final deepB = math.exp(path * _lnB);
    final shallowR = math.exp(path * 0.45 * _lnR);
    final shallowG = math.exp(path * 0.45 * _lnG);
    final shallowB = math.exp(path * 0.45 * _lnB);

    final back = _clamp(-noL * 0.75 + 0.25, 0, 1);
    final front = _clamp(noL * 0.7 + 0.3, 0, 1);
    final towardLamp = _clamp(-(vx * lx + vy * ly + vz * lz), 0, 1);
    final t2 = towardLamp * towardLamp;
    final t4 = t2 * t2;
    final through = t4 * t4;
    final transmit = back * 0.8 + through * 1.8;

    var cr = lampR * (deepR * transmit + shallowR * front * 0.35);
    var cg = lampG * (deepG * transmit + shallowG * front * 0.35);
    var cb = lampB * (deepB * transmit + shallowB * front * 0.35);

    // Light scattered through the resin has no direction left in it.
    final fillK = _lamp * _fillShare / (1 + d2 * _fillFalloff);
    final fR = _fillR * fillK;
    final fG = _fillG * fillK;
    final fB = _fillB * fillK;
    cr += fR * (deepR + (shallowR - deepR) * 0.4);
    cg += fG * (deepG + (shallowG - deepG) * 0.4);
    cb += fB * (deepB + (shallowB - deepB) * 0.4);
    final rimK = rim * 0.8;
    cr += (lampR + fR) * _sqR * rimK;
    cg += (lampG + fG) * _sqG * rimK;
    cb += (lampB + fB) * _sqB * rimK;
    cr *= ao;
    cg *= ao;
    cb *= ao;

    // A thin cool film on the coating, strongest at grazing angles.
    final rx = -vx + 2 * nDotV * nx;
    final ry = -vy + 2 * nDotV * ny;
    final rz = -vz + 2 * nDotV * nz;
    final m = 1 - math.max(noV, 0.22);
    final m2 = m * m;
    final fres = 0.04 + 0.96 * m2 * m2 * m;
    final phase = noV * 1.7 + seed * 0.15;
    final filmR = 0.5 + 0.5 * math.cos(_tau * phase);
    final filmG = 0.5 + 0.5 * math.cos(_tau * (phase + 0.33));
    final filmB = 0.5 + 0.5 * math.cos(_tau * (phase + 0.67));
    final sky = 0.3 +
        0.7 * _clamp((rx * _keyX + ry * _keyY + rz * _keyZ) * 0.5 + 0.5, 0, 1);
    // Where the lamp shines through, its light swamps the reflection.
    final swamp = 1 / (1 + 2.5 * (lampR + lampG + lampB) * 0.333);
    final sheenK = (0.15 + 1.5 * fres) * sky * (pod ? 0.6 : 1.0) * swamp;
    cr += _sheenR * (1 + (filmR - 1) * 0.55) * sheenK;
    cg += _sheenG * (1 + (filmG - 1) * 0.55) * sheenK;
    cb += _sheenB * (1 + (filmB - 1) * 0.55) * sheenK;

    // Gloss: the cool key, and the lamp itself.
    var hx = _keyX + vx;
    var hy = _keyY + vy;
    var hz = _keyZ + vz;
    final hLen = math.max(math.sqrt(hx * hx + hy * hy + hz * hz), 1e-6);
    hx /= hLen;
    hy /= hLen;
    hz /= hLen;
    final nh = nx * hx + ny * hy + nz * hz;
    if (nh > 0.8) {
      final gloss = math.pow(nh, 80).toDouble() * 0.5;
      cr += (1 + (_sheenR - 1) * 0.35) * gloss;
      cg += (1 + (_sheenG - 1) * 0.35) * gloss;
      cb += (1 + (_sheenB - 1) * 0.35) * gloss;
    }
    var lhx = lx + vx;
    var lhy = ly + vy;
    var lhz = lz + vz;
    final lhLen = math.sqrt(lhx * lhx + lhy * lhy + lhz * lhz);
    if (lhLen > 1e-6) {
      lhx /= lhLen;
      lhy /= lhLen;
      lhz /= lhLen;
      final nhl = nx * lhx + ny * lhy + nz * lhz;
      if (nhl > 0.8) {
        final spec = math.pow(nhl, 60).toDouble() * 0.3;
        cr += lampR * spec;
        cg += lampG * spec;
        cb += lampB * spec;
      }
    }

    if (!cr.isFinite || !cg.isFinite || !cb.isFinite) {
      cr = 0;
      cg = 0;
      cb = 0;
    }
    cr = math.min(cr, 64);
    cg = math.min(cg, 64);
    cb = math.min(cb, 64);

    _outMain = _pack(
      _encode(_aces(math.max(cr, 0))),
      _encode(_aces(math.max(cg, 0))),
      _encode(_aces(math.max(cb, 0))),
    );

    // The part bright enough to spill past the petals.
    final peak = math.max(cr, math.max(cg, cb));
    if (_bloomOn && peak > 0.45) {
      final cap = peak > 12 ? 12 / peak : 1.0;
      final knee = _clamp((math.min(peak, 12.0) - 0.45) / 0.9, 0, 1);
      final gain = cap * knee * knee;
      _outBloom = _packGlow(
        _encode(_aces(cr * gain)),
        _encode(_aces(cg * gain)),
        _encode(_aces(cb * gain)),
      );
    } else {
    _outBloom = 0;
    }
  }

  void _drawPetals(Canvas canvas, Int32List colors, int from, int to) {
    if (to <= from) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _xy,
      colors: colors,
      indices: Uint16List.sublistView(_indices, from, to),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
    vertices.dispose();
  }

  void _drawDome(Canvas canvas, bool bloom) {
    _fillPaint.color = Color(bloom ? _beadBloom[0] : _beadMain[0]);
    canvas.drawCircle(Offset(_beadX[0], _beadY[0]), _beadR[0], _fillPaint);
    for (final j in _beadOrder) {
      _fillPaint.color = Color(bloom ? _beadBloom[j] : _beadMain[j]);
      canvas.drawCircle(Offset(_beadX[j], _beadY[j]), _beadR[j], _fillPaint);
    }
  }

  /// One level of glow: the bright part of the flower, blurred and added.
  void _glow(Canvas canvas, Rect rect, double sigma, double weight, int end) {
    if (weight <= 0.001) return;
    final layer = Paint()
      ..blendMode = BlendMode.plus
      ..color = Color.fromRGBO(255, 255, 255, weight)
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    canvas.saveLayer(rect, layer);
    _drawPetals(canvas, _bloomCol, 0, end);
    _drawDome(canvas, true);
    canvas.restore();
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;
    final cfg = widget;

    final gridU = switch (frame.quality) {
      EffectQuality.low => 9,
      EffectQuality.medium => 14,
      EffectQuality.high => 22,
    };
    final gridV = switch (frame.quality) {
      EffectQuality.low => 4,
      EffectQuality.medium => 6,
      EffectQuality.high => 8,
    };
    _rebuild(cfg.petals, cfg.layers, gridU, gridV);
    final petals = _petalList;
    final count = petals.length;
    final row = gridV + 1;
    final per = (gridU + 1) * row;

    if (_moteCount != cfg.motes) {
      _moteCount = cfg.motes;
      _motes = _Motes(math.min(400, math.max(0, cfg.motes)));
    }

    // Colours, in linear light.
    final colors = cfg.colors;
    final petalColor = colors.isNotEmpty ? colors[0] : _defaultColors[0];
    final lightColor = colors.length > 1 ? colors[1] : _defaultColors[1];
    final sheenColor = colors.length > 2 ? colors[2] : _defaultColors[2];
    final petalR = _linear(petalColor.r);
    final petalG = _linear(petalColor.g);
    final petalB = _linear(petalColor.b);
    _lnR = math.log(math.max(petalR, 1e-4));
    _lnG = math.log(math.max(petalG, 1e-4));
    _lnB = math.log(math.max(petalB, 1e-4));
    _sqR = math.sqrt(petalR);
    _sqG = math.sqrt(petalG);
    _sqB = math.sqrt(petalB);
    _lightR = _linear(lightColor.r);
    _lightG = _linear(lightColor.g);
    _lightB = _linear(lightColor.b);
    _fillR = _lightR + (1 - _lightR) * 0.35;
    _fillG = _lightG + (1 - _lightG) * 0.35;
    _fillB = _lightB + (1 - _lightB) * 0.35;
    _sheenR = _linear(sheenColor.r);
    _sheenG = _linear(sheenColor.g);
    _sheenB = _linear(sheenColor.b);
    _bloomOn = cfg.bloom > 0.01;

    // The opening.
    var elapsed = frame.time - _lastTime;
    if (!_started || elapsed < 0) {
      _started = true;
      _begin();
      elapsed = 0;
    }
    _lastTime = frame.time;
    elapsed = math.min(elapsed, 0.05);
    if (_tweenT < 1) {
      _tweenT = math.min(1.0, _tweenT + elapsed / _tweenSeconds);
      _value = _from + (_to - _from) * cfg.curve.transform(_tweenT);
    }
    if (_tweenT >= 1) {
      _value = _to;
      if (_to >= 1 && !_opened) {
        _opened = true;
        final callback = cfg.onOpened;
        if (callback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) callback();
          });
        }
      }
    }
    final e = math.max(0.0, _value);

    // Lean toward the pointer, and the glow under a finger.
    final pointer = frame.pointer;
    final strength = cfg.interactive ? frame.pointerStrength : 0.0;
    final aimX = pointer == null
        ? 0.0
        : _clamp(pointer.dx / size.width * 2 - 1, -1.5, 1.5) * strength;
    final aimY = pointer == null
        ? 0.0
        : _clamp(pointer.dy / size.height * 2 - 1, -1.5, 1.5) * strength;
    final ease = 1 - math.exp(-elapsed * 5.52);
    _px += (aimX - _px) * ease;
    _py += (aimY - _py) * ease;
    _hover += ((strength > 0.5 ? 1.0 : 0.0) - _hover) *
        (1 - math.exp(-elapsed * 3));

    // The flower's pose.
    final t = frame.time;
    final floatAmount = 4.0 * cfg.float;
    final lean = 5.0 * 0.035 * cfg.tilt;
    final rotX =
        _py * lean * 0.7 + floatAmount * 0.006 * math.sin(t * 0.37 + 1);
    final rotZ = -_px * lean + floatAmount * 0.006 * math.sin(t * 0.29);
    final posY = floatAmount * 0.012 * math.sin(t * 0.55);
    final entry = math.min(1.0, e);
    final scale = _entryScale + (1 - _entryScale) * entry;
    final turn = frame.yaw + (1 - entry) * _entryTurn;

    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);
    final cosZ = math.cos(rotZ);
    final sinZ = math.sin(rotZ);
    final cosT = math.cos(turn);
    final sinT = math.sin(turn);
    final q00 = cosZ;
    final q01 = -sinZ;
    final q10 = cosX * sinZ;
    final q11 = cosX * cosZ;
    final q12 = -sinX;
    final q20 = sinX * sinZ;
    final q21 = sinX * cosZ;
    final q22 = cosX;
    final m00 = scale * q00 * cosT;
    final m01 = scale * q01;
    final m02 = scale * q00 * sinT;
    final m10 = scale * (q10 * cosT - q12 * sinT);
    final m11 = scale * q11;
    final m12 = scale * (q10 * sinT + q12 * cosT);
    final m20 = scale * (q20 * cosT - q22 * sinT);
    final m21 = scale * q21;
    final m22 = scale * (q20 * sinT + q22 * cosT);

    final hoverGlow = 5.0 * _hover;
    final open = e + 0.012 * math.sin(t * 0.6) + hoverGlow * 0.008;
    final openC = _clamp(open, 0, 1.25);
    final o1 = math.min(openC, 1.0);
    final lit = 0.15 + 0.85 * _smooth01(e * 1.2);
    final flicker = 1 +
        0.25 *
            0.12 *
            (0.6 * math.sin(t * 1.9) + 0.4 * math.sin(t * 4.3 + 1.3));
    _lamp = _lampRef * cfg.glow * lit * flicker * (1 + hoverGlow * 0.07);
    // The lamp sits among the inner petals and does not turn with them.
    _lampX = scale * (q00 * 0.38 + q01 * 0.20);
    _lampY = scale * (q10 * 0.38 + q11 * 0.20 + q12 * 0.10) + posY;
    _lampZ = scale * (q20 * 0.38 + q21 * 0.20 + q22 * 0.10);

    // The camera: looking down at the flower from 38 degrees.
    final shortSide = math.min(size.width, size.height);
    final share = _fitShare * 1.94 * _clamp(cfg.size, 0.1, 4.0);
    final visibleH = _flowerWidth * size.height / (share * shortSide);
    final tanHalf = math.tan(_fov / 2);
    final dist = visibleH / (2 * tanHalf);
    _f = (size.height / 2) / tanHalf;
    _midX = size.width / 2;
    _midY = size.height / 2;
    _sinEl = math.sin(_elevation);
    _cosEl = math.cos(_elevation);
    _eyeX = 0;
    _eyeY = _targetY + dist * _sinEl;
    _eyeZ = dist * _cosEl;

    final breathRad = 2.5 * _deg;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (var p = 0; p < count; p++) {
      final pt = petals[p];
      final breath = breathRad *
          math.sin(t * 0.83 + pt.seed * _tau) *
          (1.2 - 0.15 * pt.layer);
      final a0 = pt.bud + (pt.tilt - pt.bud) * openC + breath;
      final kk = math.max(
        (_budBend + (pt.bend - _budBend) * o1) / pt.length,
        0.001,
      );
      final baseR = pt.r0 * (0.55 + 0.45 * o1);
      final cupF = pt.cup * (1.5 - 0.5 * o1);
      final cosA0 = math.cos(a0);
      final sinA0 = math.sin(a0);
      final cosPhi = math.cos(pt.phi);
      final sinPhi = math.sin(pt.phi);

      // The spine of the petal, row by row from base to tip.
      for (var i = 0; i <= gridU; i++) {
        final uu = i / gridU;
        final a = a0 - kk * uu * pt.length;
        final ca = math.cos(a);
        final sa = math.sin(a);
        _spCos[i] = ca;
        _spSin[i] = sa;
        _spR[i] = baseR + (ca - cosA0) / kk;
        _spH[i] = pt.h0 + (sinA0 - sa) / kk;
        // Narrow base, broad body, then a pointed nib.
        _spW[i] = pt.width *
            1.93 *
            math.pow(uu, 0.45).toDouble() *
            math.sqrt(1 - uu);
        final tip = _smoothstep(0.72, 1.0, uu);
        _spLift[i] = -pt.curl * tip * tip * pt.length * 0.14;
      }

      // The surface: the spine plus the cup across it.
      for (var i = 0; i <= gridU; i++) {
        final uu = i / gridU;
        final ca = _spCos[i];
        final sa = _spSin[i];
        final wv = _spW[i];
        for (var k = 0; k <= gridV; k++) {
          final vv = k / gridV * 2 - 1;
          final lat = vv * wv;
          final lift = cupF * wv * vv * vv +
              _spLift[i] +
              (pt.seed - 0.5) * 0.06 * vv * wv * uu;
          final lx = cosPhi * _spR[i] - sinPhi * lat - cosPhi * ca * lift;
          final ly = _spH[i] + sa * lift;
          final lz = sinPhi * _spR[i] + cosPhi * lat - sinPhi * ca * lift;
          final o = (p * per + i * row + k) * 3;
          _pos[o] = m00 * lx + m01 * ly + m02 * lz;
          _pos[o + 1] = m10 * lx + m11 * ly + m12 * lz + posY;
          _pos[o + 2] = m20 * lx + m21 * ly + m22 * lz;
        }
      }

      // Surface normals from the neighbouring points.
      final base = p * per;
      for (var i = 1; i < gridU; i++) {
        for (var k = 0; k <= gridV; k++) {
          final kp = math.min(k + 1, gridV);
          final km = math.max(k - 1, 0);
          final a = (base + (i + 1) * row + k) * 3;
          final b = (base + (i - 1) * row + k) * 3;
          final c = (base + i * row + kp) * 3;
          final d = (base + i * row + km) * 3;
          final dux = _pos[a] - _pos[b];
          final duy = _pos[a + 1] - _pos[b + 1];
          final duz = _pos[a + 2] - _pos[b + 2];
          final dvx = _pos[c] - _pos[d];
          final dvy = _pos[c + 1] - _pos[d + 1];
          final dvz = _pos[c + 2] - _pos[d + 2];
          final nx = duy * dvz - duz * dvy;
          final ny = duz * dvx - dux * dvz;
          final nz = dux * dvy - duy * dvx;
          final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
          final o = (i * row + k) * 3;
          if (nl < 1e-9) {
            _nor[o] = 0;
            _nor[o + 1] = 0;
            _nor[o + 2] = 0;
          } else {
            _nor[o] = nx / nl;
            _nor[o + 1] = ny / nl;
            _nor[o + 2] = nz / nl;
          }
        }
      }
      for (var k = 0; k <= gridV; k++) {
        final first = (1 * row + k) * 3;
        final last = ((gridU - 1) * row + k) * 3;
        final o0 = k * 3;
        final o1n = (gridU * row + k) * 3;
        _nor[o0] = _nor[first];
        _nor[o0 + 1] = _nor[first + 1];
        _nor[o0 + 2] = _nor[first + 2];
        _nor[o1n] = _nor[last];
        _nor[o1n + 1] = _nor[last + 1];
        _nor[o1n + 2] = _nor[last + 2];
      }

      // Light every point, and find where it lands on the screen.
      for (var i = 0; i <= gridU; i++) {
        final uu = i / gridU;
        final ao = 0.42 + 0.58 * _smoothstep(0.0, 0.38, uu);
        for (var k = 0; k <= gridV; k++) {
          final id = base + i * row + k;
          final o = id * 3;
          final n = (i * row + k) * 3;
          final av = (k / gridV * 2 - 1).abs();
          _shade(
            _pos[o],
            _pos[o + 1],
            _pos[o + 2],
            _nor[n],
            _nor[n + 1],
            _nor[n + 2],
            uu,
            av,
            pt.seed,
            ao,
            false,
            false,
          );
          _col[id] = _outMain;
          _bloomCol[id] = _outBloom;
          _project(_pos[o], _pos[o + 1], _pos[o + 2]);
          _xy[id * 2] = _projX;
          _xy[id * 2 + 1] = _projY;
          if (_projX < minX) minX = _projX;
          if (_projX > maxX) maxX = _projX;
          if (_projY < minY) minY = _projY;
          if (_projY > maxY) maxY = _projY;
        }
      }

      // How far from the camera the middle of the petal is.
      final mid = (base + (gridU ~/ 2) * row + gridV ~/ 2) * 3;
      _project(_pos[mid], _pos[mid + 1], _pos[mid + 2]);
      _depth[p] = _projDepth;
    }

    // The seed dome rises and swells as the bud opens.
    final g = 0.7 + 0.3 * _clamp(open, 0, 1);

    // The receptacle under the petals.
    {
      final ly = _receptacleY * g;
      final wx = m01 * ly;
      final wy = m11 * ly + posY;
      final wz = m21 * ly;
      _shade(wx, wy, wz, 0, 0, 0, 0.55, 0, 0.5, 0.5, true, true);
      _project(wx, wy, wz);
      _recX = _projX;
      _recY = _projY;
      _recR = _receptacleR * g * scale * _f / _projDepth;
      _recColor = _outMain;
    }

    // The core of the dome.
    {
      final ly = _podCenterY * g;
      final wx = m01 * ly;
      final wy = m11 * ly + posY;
      final wz = m21 * ly;
      _shade(wx, wy, wz, 0, 0, 0, 0.55, 0, 0.5, 0.5, true, true);
      _project(wx, wy, wz);
      _beadX[0] = _projX;
      _beadY[0] = _projY;
      _beadR[0] = _podR * 0.9 * g * scale * _f / _projDepth;
      _beadDepth[0] = _projDepth;
      _beadMain[0] = _outMain;
      _beadBloom[0] = _outBloom;
    }

    // The beads packed over the dome.
    for (var j = 0; j < _podBeads; j++) {
      final dx = _pod.dirX[j];
      final dy = _pod.dirY[j];
      final dz = _pod.dirZ[j];
      final lx = dx * _podR * g;
      final ly = (_podCenterY + dy * _podR) * g;
      final lz = dz * _podR * g;
      final wx = m00 * lx + m01 * ly + m02 * lz;
      final wy = m10 * lx + m11 * ly + m12 * lz + posY;
      final wz = m20 * lx + m21 * ly + m22 * lz;
      var nx = m00 * dx + m01 * dy + m02 * dz;
      var ny = m10 * dx + m11 * dy + m12 * dz;
      var nz = m20 * dx + m21 * dy + m22 * dz;
      final nl = math.max(math.sqrt(nx * nx + ny * ny + nz * nz), 1e-6);
      nx /= nl;
      ny /= nl;
      nz /= nl;
      _shade(wx, wy, wz, nx, ny, nz, 0.55, 0, _pod.seed[j], 0.85, true, false);
      _project(wx, wy, wz);
      _beadX[j + 1] = _projX;
      _beadY[j + 1] = _projY;
      _beadR[j + 1] = _pod.radius[j] * g * scale * _f / _projDepth;
      _beadDepth[j + 1] = _projDepth;
      _beadMain[j + 1] = _outMain;
      _beadBloom[j + 1] = _outBloom;
    }
    _beadOrder.sort((a, b) => _beadDepth[b].compareTo(_beadDepth[a]));

    // Petals from far to near; the dome goes in where its depth falls.
_depth[count] = _beadDepth[0];
// Far to near, starting from last frame's order and only moving a petal
// past another when it is clearly farther, so overlapping petals never flip
// back and forth from one frame to the next.
for (var i = 1; i <= count; i++) {
  final x = _order[i];
  var j = i - 1;
  while (j >= 0 && _depth[x] > _depth[_order[j]] + 0.03) {
    _order[j + 1] = _order[j];
    j--;
  }
  _order[j + 1] = x;
}
    var written = 0;
    var split = -1;
    for (var n = 0; n <= count; n++) {
      final p = _order[n];
      if (p == count) {
        split = written;
        continue;
      }
      final first = p * per;
      for (var i = 0; i < gridU; i++) {
        for (var k = 0; k < gridV; k++) {
          final a = first + i * row + k;
          _indices[written++] = a;
          _indices[written++] = a + row;
          _indices[written++] = a + 1;
          _indices[written++] = a + 1;
          _indices[written++] = a + row;
          _indices[written++] = a + row + 1;
        }
      }
    }
    if (split < 0) split = written;

    _fillPaint.color = Color(_recColor);
    canvas.drawCircle(Offset(_recX, _recY), _recR, _fillPaint);
    _drawPetals(canvas, _col, 0, split);
    _drawDome(canvas, false);
    _drawPetals(canvas, _col, split, written);

    // Bright light spills past the petals: a tight glow and a wide haze.
    if (_bloomOn && minX.isFinite) {
      final px = shortSide / 700;
      final nearSigma = math.max(0.6, 4 * px);
      final wideSigma = math.max(1.5, 28 * px);
      final rect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(wideSigma * 3);
      final nearWeight = _clamp(0.2 * cfg.bloom, 0, 1);
      final wideWeight =
        _clamp(0.3 * cfg.bloom * math.min(1.0, e * 2), 0, 1);
      _glow(canvas, rect, nearSigma, nearWeight, written);
      if (frame.quality != EffectQuality.low) {
        _glow(canvas, rect, wideSigma, wideWeight, written);
      }
    }

    // Faint specks drifting upward.
    final moteScale = _clamp(shortSide / 700, 0.3, 2.0);
    final moteR = (lightColor.r * 255).round();
    final moteG = (lightColor.g * 255).round();
    final moteB = (lightColor.b * 255).round();
    for (var i = 0; i < _motes.count; i++) {
      final s = _motes.s[i];
      final my = (_motes.y[i] + t * 0.05 * (0.4 + s) + 3.0) % 6.0 - 3.0;
      final mx = _motes.x[i] + math.sin(t * 0.3 + s * 20) * 0.08;
      final edge = _smoothstep(3.0, 2.4, my.abs());
      final sevens = s * 7;
      final alpha = (0.25 + 0.75 * (sevens - sevens.floorToDouble())) *
          edge *
          (0.55 + 0.45 * math.sin(t * (0.6 + s) + s * 40));
      if (alpha <= 0.01) continue;
      _project(mx, my, _motes.z[i]);
      final radius = (1 + 1.5 * s) * 14 / _projDepth * moteScale * 0.5;
      _motePaint.color =
          Color.fromRGBO(moteR, moteG, moteB, _clamp(alpha * 0.5, 0, 1));
      canvas.drawCircle(Offset(_projX, _projY), radius, _motePaint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.interactive ? _onTap : null,
      child: EffectHost(
        onPaint: _paintFrame,
        speed: widget.speed,
        paused: widget.paused,
        interactive: widget.interactive,
        rotatesOnDrag: false,
        autoRotate: 0.035 * widget.spin,
        quality: widget.quality,
        controller: widget.controller,
        background: widget.background,
        semanticLabel: widget.semanticLabel,
      ),
    );
  }
}