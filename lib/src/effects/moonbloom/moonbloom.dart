import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const double _tau = math.pi * 2;
const double _step5 = _tau / 5;

// The artwork's own space is 736 by 414. The crown reaches about 475 across.
const double _refH = 414;
const double _crownW = 475;

// Per quality (low, medium, high): flowers in total, hanging sprays, the
// sharpest the baked pictures get, and the share of petals drawn.
const List<int> _flowerBudget = <int>[3500, 6000, 9000];
const List<int> _sprayCount = <int>[14, 22, 30];
const List<double> _bakeCap = <double>[1.0, 1.5, 2.0];
const List<double> _petalShare = <double>[0.4, 0.7, 1.0];

// Limbs: start, control, end, width.
const List<List<double>> _limbs = <List<double>>[
  <double>[-20, 10, 200, -30, 430, 60, 5],
  <double>[-20, 60, 230, 40, 470, 185, 6],
  <double>[60, -20, 250, 20, 370, 140, 4],
  <double>[-20, 130, 190, 140, 425, 285, 5],
  <double>[-20, 205, 150, 235, 335, 385, 5],
  <double>[-15, 280, 90, 320, 210, 430, 4],
  <double>[-20, 350, 60, 380, 120, 440, 3],
];

// The ragged right edge of the crown: y, then x.
const List<List<double>> _edge = <List<double>>[
  <double>[-20, 390],
  <double>[0, 395],
  <double>[40, 420],
  <double>[110, 440],
  <double>[185, 475],
  <double>[230, 455],
  <double>[270, 430],
  <double>[330, 400],
  <double>[390, 352],
  <double>[414, 320],
  <double>[440, 300],
];

/// Which side of the screen the tree grows in from.
enum MoonbloomSide {
  /// The tree grows in from the left edge. The open sky is on the right.
  left,

  /// The tree grows in from the right edge. The open sky is on the left.
  right,
}

/// A night scene: a tree in blossom lit from behind, with petals drifting
/// down through the dark. Made to sit behind a sign-up sheet or an
/// onboarding page.
///
/// It fills the space it is given. On a tall phone screen the tree grows in
/// from one side and runs the full height.
///
/// ```dart
/// Scaffold(
///   resizeToAvoidBottomInset: false,
///   body: Stack(
///     children: [
///       Positioned.fill(
///         child: Moonbloom.backdrop(side: MoonbloomSide.right),
///       ),
///       YourSignUpSheet(),
///     ],
///   ),
/// )
/// ```
class Moonbloom extends StatefulWidget {
  /// Creates the scene.
  const Moonbloom({
    super.key,
    this.blossom = const Color(0xFFCFA0FF),
    this.petalColor = const Color(0xFFEDE6EA),
    this.branch = const Color(0xFF3E3539),
    this.background,
    this.side = MoonbloomSide.left,
    this.blur = 0.0,
    this.dim = 0.0,
    this.speed = 100.0,
    this.petals = 140,
    this.wind = 30.0,
    this.glow = 50.0,
    this.scale = 100.0,
    this.reach = 100.0,
    this.density = 100.0,
    this.seed = 7,
    this.interactive = false,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// A soft backdrop for a screen with content on top: the tree is gently
  /// blurred and dimmed, and everything moves a little slower.
  factory Moonbloom.backdrop({
    Key? key,
    MoonbloomSide side = MoonbloomSide.left,
    double blur = 45,
    double dim = 25,
    Color blossom = const Color(0xFFCFA0FF),
    Color? background,
    bool paused = false,
    EffectQuality quality = EffectQuality.medium,
    EffectController? controller,
    String? semanticLabel,
  }) {
    return Moonbloom(
      key: key,
      side: side,
      blur: blur,
      dim: dim,
      blossom: blossom,
      background: background,
      speed: 60,
      petals: 90,
      paused: paused,
      quality: quality,
      controller: controller,
      semanticLabel: semanticLabel,
    );
  }

  /// The colour of the blossoms.
  final Color blossom;

  /// The colour of the drifting petals. They lean toward [blossom].
  final Color petalColor;

  /// The colour of the branches.
  final Color branch;

  /// What is behind the tree.
  final Color? background;

  /// Which side the tree grows in from.
  final MoonbloomSide side;

  /// A gentle blur on the tree, from 0 to 100. 0 is sharp. Built once, so it
  /// costs nothing while the scene moves. Petals stay sharp. Try 35 to 60
  /// behind a sheet.
  final double blur;

  /// Darkens the tree, from 0 to 100, so content on top reads clearly.
  /// Petals are not dimmed.
  final double dim;

  /// How fast everything moves, from 0 to 200. 100 is the original pace and
  /// 0 stops it.
  final double speed;

  /// How many petals drift down, from 0 to 600. Lower qualities draw fewer.
  final int petals;

  /// How much the wind sways the sprays and sets the petals wobbling, from
  /// 0 to 100.
  final double wind;

  /// The light round the brightest blossoms, from 0 to 100.
  final double glow;

  /// Size of the tree, from 20 to 160 percent. Below 100 more of the tree
  /// shows.
  final double scale;

  /// How far the crown reaches across the screen, from 40 to 160 percent.
  final double reach;

  /// How many blossoms, from 10 to 200 percent of the quality's amount.
  final double density;

  /// Changes the shape of the tree and the petals.
  final int seed;

  /// Whether touch and hover sway the sprays and push the petals. Off by
  /// default, because on a sign-up screen the touches belong to the sheet.
  final bool interactive;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings bake the tree smaller, with fewer
  /// blossoms.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] restarts the petals.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative, which is right
  /// for a background.
  final String? semanticLabel;

  @override
  State<Moonbloom> createState() => _MoonbloomState();
}

class _MoonbloomState extends State<Moonbloom> {
  final Paint _imgPaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _addPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..blendMode = ui.BlendMode.plus;
  final Paint _petalPaint = Paint()..isAntiAlias = true;
  final Paint _bokehPaint = Paint()..blendMode = ui.BlendMode.plus;

  _Scene? _scene;
  String _sceneKey = '';
  double _dpr = 1;
  bool _reduced = false;
  double _lastTime = 0;
  double _t = 0;
  int _seenResets = 0;

  List<_Petal> _petals = <_Petal>[];
  String _petalKey = '';
  math.Random _live = math.Random(1);
  List<List<int>> _petalCols = <List<int>>[];

  List<_Bokeh> _bokeh = <_Bokeh>[];
  String _bokehKey = '';
  double _bokehNext = 0;
  final double _bokehEvery = 6;
  math.Random _bokehRng = math.Random(1);

  double _px = 0;
  double _py = 0;
  bool _inside = false;
  bool _down = false;
  double _over = 0;
  double _press = 0;
  double _pvx = 0;
  double _pvy = 0;
  double _lastPx = -1;
  double _lastPy = -1;

  Paint? _vig;
  Size _vigSize = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
  }

  @override
  void didUpdateWidget(Moonbloom oldWidget) {
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
    _scene?.dispose();
    _scene = null;
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _t = 0;
      _petalKey = '';
      _bokehKey = '';
    }
  }

  void _onPointer(PointerEvent e) {
    _px = e.localPosition.dx;
    _py = e.localPosition.dy;
    _inside = true;
  }

  void _onDown(PointerDownEvent e) {
    _onPointer(e);
    _down = true;
  }

  void _onUp(PointerEvent e) {
    _down = false;
    if (e.kind == ui.PointerDeviceKind.touch) _inside = false;
  }

  /// Builds the tree and bakes it into pictures, once per size and setting.
  void _ensureScene(Size size) {
    final w = widget;
    final tier = _tier(w.quality);
    final bs = math.min(_dpr, _bakeCap[tier]);
    final key = <Object>[
      size.width.round(),
      size.height.round(),
      bs,
      tier,
      w.scale,
      w.reach,
      w.density,
      w.seed,
      w.blossom.toARGB32(),
      w.petalColor.toARGB32(),
      w.branch.toARGB32(),
      w.background?.toARGB32() ?? -1,
      w.blur,
    ].join('|');
    if (key == _sceneKey) return;
    _scene?.dispose();
    _scene = null;

    final width = size.width;
    final height = size.height;
    final reach = _clamp(w.reach, 40, 160) / 100;
    final stretch = _clamp(width / height / 1.778, 0.8, 1.25);
    // Fit the crown to the width on a tall screen, the height on a wide one.
    final fit = math.min(
      height / _refH,
      width * 0.78 / (_crownW * reach * stretch),
    );
    final u = fit * _clamp(w.scale, 20, 160) / 100;
    final bottom = math.max(_refH, height / u);

    // A taller frame holds more tree, so fewer, bigger blossoms keep the
    // same coverage within the flower budget.
    final total =
        (_flowerBudget[tier] * _clamp(w.density, 10, 200) / 100).round();
    final dens = total * _refH / (11000 * reach * bottom);
    final fsK = _clamp(1 / math.sqrt(math.max(dens, 0.01)), 1, 2.4);

    final geo = _buildTree(
      seed: w.seed,
      total: total,
      fs: 6 * fsK,
      clumpSize: 11 * fsK,
      sprays: _sprayCount[tier],
      reach: reach * 100,
      bottom: bottom,
    );

    final blur01 = _clamp(w.blur, 0, 100) / 100;
    final sigma =
        math.pow(blur01, 1.2).toDouble() * 0.022 * math.min(width, height);

    _scene = _bakeScene(
      w: width,
      h: height,
      bs: bs,
      u: u,
      sx: u * stretch,
      sy: u,
      seed: w.seed,
      geo: geo,
      blossom: w.blossom,
      branch: w.branch,
      background: w.background,
      blurSigma: sigma,
      tier: tier,
    );

    final bl = _rgb(w.blossom);
    final pc = _rgb(w.petalColor);
    _petalCols = <List<int>>[
      for (var i = 0; i < 8; i++) _ints(_mix(pc, bl, i / 7 * 0.6)),
    ];
    _sceneKey = key;
  }

  void _buildPetals(int count, int seed) {
    final r = math.Random(seed + 5);
    _live = math.Random(seed + 17);
    final k = math.log(0.7) / math.log(1 - 0.16);
    final list = <_Petal>[];
    for (var i = 0; i < count; i++) {
      final z = math.pow(r.nextDouble(), k).toDouble();
      final x = _spawnX(r);
      final y = -0.04 + r.nextDouble() * 1.08;
      final ph = r.nextDouble() * _tau;
      final wob = _tau / (1 + r.nextDouble());
      final spin = r.nextDouble() * _tau;
      final spinV = 1.5 + r.nextDouble() * 2.5;
      final rot = r.nextDouble() * _tau;
      final ci = (r.nextDouble() * 8).floor();
      final a = _clamp(0.45 + 0.55 * z + (r.nextDouble() - 0.5) * 0.2, 0.3, 1);
      list.add(
        _Petal(
          x: x,
          y: y,
          z: z,
          ph: ph,
          wob: wob,
          spin: spin,
          spinV: spinV,
          rot: rot,
          ci: ci,
          a: a,
        ),
      );
    }
    list.sort((a, b) => a.z.compareTo(b.z));
    _petals = list;
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 8 || size.height < 8) return;
    final w = widget;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    if (w.paused) dt = 0;

    _ensureScene(size);
    final scene = _scene;
    if (scene == null) return;

    final sw = size.width;
    final sh = size.height;
    final tier = _tier(w.quality);
    final spd = _reduced ? 0.0 : _clamp(w.speed, 0, 200) / 50;
    final dts = dt * spd;
    _t += dts;
    final flip = w.side == MoonbloomSide.right;
    final gA = math.max(0.0, w.glow) / 60;
    final windMul = math.max(0.0, w.wind) / 30;

    // The pointer, in the scene's own (unmirrored) space.
    final live = w.interactive;
    _over += ((live && _inside ? 1.0 : 0.0) - _over) * (1 - math.exp(-dt * 4));
    _press += ((live && _down ? 1.0 : 0.0) - _press) * (1 - math.exp(-dt * 6));
    final pAmt = _over;
    final pxd = flip ? sw - _px : _px;
    final pyd = _py;
    var rvx = 0.0;
    var rvy = 0.0;
    if (live && _inside && _lastPx >= 0 && dt > 0) {
      rvx = _clamp((pxd - _lastPx) / dt, -4 * sw, 4 * sw);
      rvy = _clamp((pyd - _lastPy) / dt, -4 * sw, 4 * sw);
    }
    _lastPx = live && _inside ? pxd : -1;
    _lastPy = live && _inside ? pyd : -1;
    final kV = 1 - math.exp(-dt * 12);
    _pvx += (rvx - _pvx) * kV;
    _pvy += (rvy - _pvy) * kV;

    // The sprays sway in the wind, and swing when touched.
    final rg = 0.26 * sw;
    final swayA = 0.008 * sw * windMul;
    for (final s in scene.sprites) {
      final rch = _clamp(s.tx / (0.55 * sw), 0.15, 1.3);
      final thA = swayA * rch / math.max(s.len, 8);
      final om = _tau / (3.0 * s.pf);
      final base = thA *
          (math.sin(om * _t + s.ph) + 0.35 * math.sin(2.27 * om * _t + s.ph2)) /
          1.35;
      var gt = 0.0;
      var kick = 0.0;
      if (pAmt > 0.001) {
        final dx = s.tx - pxd;
        final dy = s.ty - pyd;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < rg) {
          final f = math.pow(1 - d / rg, 2).toDouble();
          final vx = s.tx - s.ax;
          final vy = s.ty - s.ay;
          final vl0 = math.sqrt(vx * vx + vy * vy);
          final vl = vl0 == 0 ? 1.0 : vl0;
          final dir = ((-vy / vl) * dx + (vx / vl) * dy) / (d == 0 ? 1.0 : d);
          gt = dir * f * 0.15 * pAmt * (1 + _press);
          kick = (((-vy / vl) * _pvx + (vx / vl) * _pvy) /
                  math.max(s.len, 8)) *
              f *
              2 *
              pAmt;
        }
      }
      s.gv += ((gt - s.g) * 40 - s.gv * 4.5 + kick) * dt;
      s.g = _clamp(s.g + s.gv * dt, -0.35, 0.35);
      s.th = base + s.g;
    }

    // Petals and the near-lens bokeh need their lists built.
    final count =
        (math.min(600, math.max(0, w.petals)) * _petalShare[tier]).round();
    final pk = '$count|${w.seed}';
    if (pk != _petalKey) {
      _petalKey = pk;
      _buildPetals(count, w.seed);
    }
    final bk = '${w.seed}';
    if (bk != _bokehKey) {
      _bokehKey = bk;
      _bokehRng = math.Random(w.seed + 23);
      const first = 2.33;
      _bokeh = <_Bokeh>[_Bokeh(0.39, 0.81, 0.22), _Bokeh(first, 0.3, 1.0)];
      _bokehNext = first + _bokehEvery * (0.7 + 0.6 * _bokehRng.nextDouble());
    }
    while (_bokehNext < _t + 1) {
      final x = 0.2 + 0.65 * _bokehRng.nextDouble();
      final s = 0.45 + 0.55 * _bokehRng.nextDouble();
      _bokeh.add(_Bokeh(_bokehNext, x, s));
      _bokehNext += _bokehEvery * (0.7 + 0.6 * _bokehRng.nextDouble());
    }
    if (_bokeh.length > 6) {
      _bokeh = _bokeh.where((e) => _t - e.t0 < 2).toList();
    }

    // Draw.
    canvas.save();
    if (flip) {
      canvas.translate(sw, 0);
      canvas.scale(-1, 1);
    }
    final full = Rect.fromLTWH(0, 0, sw, sh);
    final dimK = 1 - _clamp(w.dim, 0, 100) / 100 * 0.75;
    _imgPaint.colorFilter = dimK >= 0.999
        ? null
        : ColorFilter.matrix(<double>[
            dimK, 0, 0, 0, 0, //
            0, dimK, 0, 0, 0, //
            0, 0, dimK, 0, 0, //
            0, 0, 0, 1, 0,
          ]);
    final bgImg = scene.bg;
    if (bgImg != null) _blit(canvas, bgImg, full, _imgPaint);
    _add(canvas, scene.halo, full, 0.5 * gA);
    _blit(canvas, scene.coreBlur, full, _imgPaint);
    _drawSprites(canvas, scene, true);
    _blit(canvas, scene.core, full, _imgPaint);
    _drawSprites(canvas, scene, false);
    _add(canvas, scene.bloom, full, 0.14 * gA);


    // Petals.
    final uP = math.max(scene.u, 1.0);
    final drift = -0.005;
    final rp = 0.14 * sw;
    final push = 0.05 * sw * pAmt * (1 + _press);
    final kE = 1 - math.exp(-dt * 5);
    for (final p in _petals) {
      p.y += (0.03 + 0.14 * p.z) * dts;
      p.x += drift * (0.5 + p.z) * windMul * dts;
      p.spin += p.spinV * dts;
      if (p.y > 1.05) {
        p.y = -0.04 - _live.nextDouble() * 0.04;
        p.x = _spawnX(_live);
      }
      if (p.x < -0.06) {
        p.x += 1.12;
      } else if (p.x > 1.06) {
        p.x -= 1.12;
      }
      final wx = math.sin(p.wob * _t + p.ph) * (0.006 + 0.012 * p.z) * sw * windMul;
      final bx = p.x * sw + wx;
      final by = p.y * sh;
      var tx = 0.0;
      var ty = 0.0;
      if (push > 0.01) {
        final dx = bx - pxd;
        final dy = by - pyd;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < rp) {
          final f = math.pow(1 - d / rp, 2).toDouble() * (0.5 + p.z);
          final dd = d == 0 ? 1.0 : d;
          tx = dx / dd * f * push;
          ty = dy / dd * f * push;
        }
      }
      p.ox += (tx - p.ox) * kE;
      p.oy += (ty - p.oy) * kE;
      final x = bx + p.ox;
      final y = by + p.oy;
      final r = (0.6 + 2.6 * math.pow(p.z, 1.5).toDouble()) * uP;
      final face = math.cos(p.spin).abs();
      final ang = p.rot + 0.5 * math.sin(p.wob * _t + p.ph);
      final al = p.a * (0.55 + 0.45 * face);
      final c = _petalCols[p.ci];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(ang);
      if (p.z > 0.7) {
        _petalPaint.color = Color.fromARGB((al * 0.18 * 255).round(), c[0], c[1], c[2]);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: r * 3.6,
            height: 2 * math.max(0.6 * r, 1.4 * r * face),
          ),
          _petalPaint,
        );
      }
      _petalPaint.color = Color.fromARGB((al * 255).round(), c[0], c[1], c[2]);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: r * 2,
          height: 2 * math.max(0.35 * r, 0.8 * r * face),
        ),
        _petalPaint,
      );
      canvas.restore();
    }

    // Near-lens bokeh petals.
    if (!_reduced) {
      final bl = _rgb(w.blossom);
      final pink = _mix(bl, const <double>[255, 255, 255], 0.35);
      for (final e in _bokeh) {
        final age = _t - e.t0;
        final life = 0.2 + 0.1 * e.s;
        if (age < 0 || age > life) continue;
        final a = math.pow(math.sin(math.pi * age / life), 0.8).toDouble() * 0.85;
        final r = 0.08 * sw * 0.5 * e.s;
        final x = e.x * sw - 0.47 * sw * age;
        final y = -r + 2.2 * sh * age;
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(1.15, 0.9);
        _bokehPaint.shader = ui.Gradient.radial(
          Offset.zero,
          r,
          <Color>[
            Color.fromRGBO(255, 250, 252, _clamp01(a)),
            Color.fromRGBO(255, 244, 250, _clamp01(a * 0.85)),
            _colA(pink, a * 0.35),
            _colA(pink, 0),
          ],
          const <double>[0, 0.45, 0.75, 1],
        );
        canvas.drawCircle(Offset.zero, r, _bokehPaint);
        canvas.restore();
      }
    }
    canvas.restore();

    // Vignette, the same on both sides.
    if (_vig == null || _vigSize != size) {
      final diag = math.sqrt(sw * sw + sh * sh) / 2;
      _vig = Paint()
        ..shader = ui.Gradient.radial(
          Offset(sw / 2, sh / 2),
          diag,
          const <Color>[Color(0x00000000), Color(0x3E000000)],
          const <double>[0.35, 1.0],
        );
      _vigSize = size;
    }
    if (w.background != null) canvas.drawRect(Offset.zero & size, _vig!);
  }

  void _add(Canvas c, ui.Image im, Rect dst, double a) {
    var left = a;
    while (left > 0.001) {
      _addPaint.color = Color.fromRGBO(255, 255, 255, math.min(1.0, left));
      _blit(c, im, dst, _addPaint);
      left -= 1;
    }
  }

  void _drawSprites(Canvas c, _Scene scene, bool back) {
    for (final s in scene.sprites) {
      if (s.back != back) continue;
      c.save();
      c.translate(s.ax, s.ay);
      c.rotate(s.th);
      _blit(
        c,
        s.img,
        Rect.fromLTWH(s.bx - s.ax, s.by - s.ay, s.bw, s.bh),
        _imgPaint,
      );
      c.restore();
    }
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

    final host = RepaintBoundary(
      child: EffectHost(
        onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
        paused: widget.paused,
        interactive: false,
        rotatesOnDrag: false,
        quality: widget.quality,
        controller: widget.controller,
        background: widget.background,
        semanticLabel: widget.semanticLabel,
      ),
    );

    if (!widget.interactive) return IgnorePointer(child: host);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onPointer,
      onPointerDown: _onDown,
      onPointerMove: _onPointer,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: MouseRegion(
        onExit: (_) {
          _inside = false;
        },
        child: host,
      ),
    );
  }
}

// ─── Small helpers ───────────────────────────────────────────────────────────

class _Petal {
  _Petal({
    required this.x,
    required this.y,
    required this.z,
    required this.ph,
    required this.wob,
    required this.spin,
    required this.spinV,
    required this.rot,
    required this.ci,
    required this.a,
  });

  double x;
  double y;
  final double z;
  final double ph;
  final double wob;
  double spin;
  final double spinV;
  final double rot;
  final int ci;
  final double a;
  double ox = 0;
  double oy = 0;
}

class _Bokeh {
  _Bokeh(this.t0, this.x, this.s);

  final double t0;
  final double x;
  final double s;
}

int _tier(EffectQuality q) => switch (q) {
      EffectQuality.low => 0,
      EffectQuality.medium => 1,
      EffectQuality.high => 2,
    };

double _clamp(double v, double lo, double hi) {
  final safe = v.isFinite ? v : lo;
  return math.min(hi, math.max(lo, safe));
}

double _clamp01(double v) => _clamp(v, 0, 1);

double _smooth(double a, double b, double x) {
  final d = b - a == 0 ? 1.0 : b - a;
  final t = _clamp01((x - a) / d);
  return t * t * (3 - 2 * t);
}

double _spawnX(math.Random r) {
  return r.nextDouble() < 0.22
      ? 0.2 + 0.42 * r.nextDouble()
      : 0.5 + 0.5 * ((r.nextDouble() + r.nextDouble()) / 2);
}

double _hash2(int i, int j, int s) {
  final v = math.sin(i * 127.1 + j * 311.7 + s * 74.7) * 43758.5453;
  return v - v.floorToDouble();
}

double _vnoise(double x, double y, int s) {
  final i = x.floor();
  final j = y.floor();
  final fx = x - i;
  final fy = y - j;
  final u = fx * fx * (3 - 2 * fx);
  final v = fy * fy * (3 - 2 * fy);
  final a = _hash2(i, j, s);
  final b = _hash2(i + 1, j, s);
  final c = _hash2(i, j + 1, s);
  final d = _hash2(i + 1, j + 1, s);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

List<double> _rgb(Color c) => <double>[c.r * 255, c.g * 255, c.b * 255];

List<double> _mix(List<double> a, List<double> b, double k) => <double>[
      a[0] + (b[0] - a[0]) * k,
      a[1] + (b[1] - a[1]) * k,
      a[2] + (b[2] - a[2]) * k,
    ];

int _b(double v) => v.isFinite ? math.min(255, math.max(0, v.round())) : 0;

List<int> _ints(List<double> c) => <int>[_b(c[0]), _b(c[1]), _b(c[2])];

Color _col(List<double> c) => Color.fromARGB(255, _b(c[0]), _b(c[1]), _b(c[2]));

Color _colA(List<double> c, double a) =>
    Color.fromRGBO(_b(c[0]), _b(c[1]), _b(c[2]), _clamp01(a));

void _blit(Canvas c, ui.Image im, Rect dst, Paint p) {
  c.drawImageRect(
    im,
    Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
    dst,
    p,
  );
}

Float64List _mat(double a, double tx, double ty) {
  final c = math.cos(a);
  final s = math.sin(a);
  return Float64List.fromList(<double>[
    c, s, 0, 0, //
    -s, c, 0, 0, //
    0, 0, 1, 0, //
    tx, ty, 0, 1,
  ]);
}

// ─── The blossom, drawn at unit size ─────────────────────────────────────────

Path _ovals(double dist, double rx, double ry) {
  final p = Path();
  for (var k = 0; k < 5; k++) {
    final a = k * _step5;
    final o = Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2));
    p.addPath(
      o.transform(_mat(a, math.cos(a) * dist, math.sin(a) * dist)),
      Offset.zero,
    );
  }
  return p;
}

Path _notches() {
  final p = Path();
  for (var k = 0; k < 5; k++) {
    final a = k * _step5;
    p.addOval(
      Rect.fromCircle(
        center: Offset(math.cos(a) * 0.98, math.sin(a) * 0.98),
        radius: 0.09,
      ),
    );
  }
  return p;
}

Path _stamenLines() {
  final p = Path();
  for (var k = 0; k < 7; k++) {
    final a = 0.4 + k * 0.8976;
    p.moveTo(0, 0);
    p.lineTo(math.cos(a) * 0.42, math.sin(a) * 0.42);
  }
  return p;
}

Path _stamenDots() {
  final p = Path();
  for (var k = 0; k < 7; k++) {
    final a = 0.4 + k * 0.8976;
    p.addOval(
      Rect.fromCircle(
        center: Offset(math.cos(a) * 0.44, math.sin(a) * 0.44),
        radius: 0.06,
      ),
    );
  }
  return p;
}

final Path _petalsPath = _ovals(0.5, 0.5, 0.34);
final Path _sheenPath = _ovals(0.6, 0.26, 0.16);
final Path _notchPath = _notches();
final Path _stamenLinePath = _stamenLines();
final Path _stamenDotPath = _stamenDots();

/// The blossom's colours at 65 levels of light.
class _Palette {
  _Palette(List<double> blossom) {
    const white = <double>[255, 255, 255];
    final eyeBase = _mix(blossom, const <double>[190, 50, 105], 0.5);
    for (var i = 0; i <= 64; i++) {
      final l = i / 64;
      final b = math.min(1.3, 0.32 + 0.98 * math.pow(l, 1.1).toDouble());
      final c = b <= 1
          ? <double>[blossom[0] * b, blossom[1] * b, blossom[2] * b]
          : _mix(blossom, white, math.min(0.3, b - 1));
      pal.add(_col(c));
      dark.add(_col(_mix(c, const <double>[20, 10, 18], 0.45)));
      lite.add(_col(_mix(c, white, 0.28)));
      final b0 = math.min(1.0, b);
      eye.add(_col(<double>[eyeBase[0] * b0, eyeBase[1] * b0, eyeBase[2] * b0]));
      final sb = math.min(1.0, 0.35 + b * 0.75);
      stam.add(_col(<double>[255 * sb, 240 * sb, 215 * sb]));
    }
    peak = _col(_mix(blossom, white, 0.35));
  }

  final List<Color> pal = <Color>[];
  final List<Color> dark = <Color>[];
  final List<Color> lite = <Color>[];
  final List<Color> eye = <Color>[];
  final List<Color> stam = <Color>[];
  late final Color peak;
}

class _FlowerPainter {
  _FlowerPainter(this.pal, this.sx, this.sy, this.u, this.tier);

  final _Palette pal;
  final double sx;
  final double sy;
  final double u;
  final int tier;
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _line = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  /// Draws flowers dimmest first. [res] is pixels per layout pixel, and it
  /// decides how much detail a flower is given.
  void draw(Canvas g, List<_Flower> flowers, double res) {
    final list = List<_Flower>.of(flowers)..sort((a, b) => a.l.compareTo(b.l));
    for (final f in list) {
      final x = f.x * sx;
      final y = f.y * sy;
      final r = f.r * u;
      final ci = (f.l * 64).round();
      final px = r * res;
      if (px < 3.2) {
        _fill.color = pal.pal[ci];
        for (var k = 0; k < 5; k++) {
          final a = f.rot + k * _step5;
          g.drawCircle(
            Offset(x + math.cos(a) * r * 0.45, y + math.sin(a) * r * 0.45),
            r * 0.5,
            _fill,
          );
        }
      } else {
        final sq = 0.62 + 0.38 * math.cos(f.rot * 2.3).abs();
        final tilt = f.rot * 0.7;
        g.save();
        g.translate(x, y);
        g.rotate(tilt);
        g.scale(1, sq);
        g.rotate(f.rot - tilt);
        g.scale(r, r);
        _fill.color = pal.pal[ci];
        g.drawPath(_petalsPath, _fill);
        if (tier > 0 && px >= 6) {
          _line.color = pal.dark[ci].withValues(alpha: 0.55);
          _line.strokeWidth = math.max(0.5 / px, 0.07);
          g.drawPath(_petalsPath, _line);
          _fill.color = pal.lite[ci].withValues(alpha: 0.45 * f.l);
          g.drawPath(_sheenPath, _fill);
          _fill.color = pal.dark[ci].withValues(alpha: 0.8);
          g.drawPath(_notchPath, _fill);
        }
        _fill.color = pal.eye[ci];
        g.drawCircle(Offset.zero, 0.26, _fill);
        if (tier > 1 && px >= 8) {
          _line.color = pal.stam[ci].withValues(alpha: 0.7);
          _line.strokeWidth = math.max(0.4 / px, 0.04);
          g.drawPath(_stamenLinePath, _line);
          _fill.color = pal.stam[ci].withValues(alpha: 0.9);
          g.drawPath(_stamenDotPath, _fill);
        }
        g.restore();
      }
      if (f.l > 0.78) {
        _fill.color = pal.peak.withValues(alpha: 0.35 * _smooth(0.78, 1, f.l));
        g.drawCircle(Offset(x + r * 0.2, y - r * 0.2), r * 0.4, _fill);
      }
    }
  }
}

// ─── The tree ────────────────────────────────────────────────────────────────

class _Pt {
  const _Pt(this.x, this.y);

  final double x;
  final double y;
}

class _Flower {
  const _Flower(this.x, this.y, this.r, this.l, this.rot);

  final double x;
  final double y;
  final double r;
  final double l;
  final double rot;
}

class _Branch {
  const _Branch(this.pts, this.w);

  final List<_Pt> pts;
  final double w;
}

class _Group {
  _Group(this.pts, this.flowers, this.anchor, this.tip, this.back);

  final List<_Pt> pts;
  final List<_Flower> flowers;
  final _Pt anchor;
  final _Pt tip;
  final bool back;
}

class _Geo {
  const _Geo(this.branches, this.groups, this.core, this.coreBlur);

  final List<_Branch> branches;
  final List<_Group> groups;
  final List<_Flower> core;
  final List<_Flower> coreBlur;
}

double _edgeX(double y) {
  if (y <= _edge[0][0]) return _edge[0][1];
  for (var i = 0; i < _edge.length - 1; i++) {
    final y0 = _edge[i][0];
    final x0 = _edge[i][1];
    final y1 = _edge[i + 1][0];
    final x1 = _edge[i + 1][1];
    if (y <= y1) return x0 + (x1 - x0) * (y - y0) / (y1 - y0);
  }
  return _edge[_edge.length - 1][1];
}

bool _isBlur(double x, double y) => (x < 160 && y > 255) || (x < 35 && y > 140);

_Pt _quad(_Pt a, _Pt c, _Pt b, double t) {
  final m = 1 - t;
  return _Pt(
    m * m * a.x + 2 * m * t * c.x + t * t * b.x,
    m * m * a.y + 2 * m * t * c.y + t * t * b.y,
  );
}

double _quadAngle(_Pt a, _Pt c, _Pt b, double t) {
  final dx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x);
  final dy = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y);
  return math.atan2(dy, dx);
}

_Geo _buildTree({
  required int seed,
  required int total,
  required double fs,
  required double clumpSize,
  required int sprays,
  required double reach,
  required double bottom,
}) {
  final rng = math.Random(seed);
  double rnd() => rng.nextDouble();
  final rr = reach / 100;
  double ex(double y) => _edgeX(y) * rr;
  final branches = <_Branch>[];

  List<_Pt> clipLine(List<_Pt> pts) {
    final out = <_Pt>[];
    for (final p in pts) {
      if (p.x > ex(p.y) + 25 || p.y > bottom + 16) break;
      out.add(p);
    }
    return out;
  }

  void grow(double x0, double y0, double a0, double len, double w, int depth) {
    var x = x0;
    var y = y0;
    var a = a0;
    final pts = <_Pt>[_Pt(x, y)];
    const steps = 5;
    final seg = len / steps;
    for (var s = 0; s < steps; s++) {
      a += (math.pi / 2 - a) * 0.1 + (rnd() - 0.5) * 0.35;
      x += math.cos(a) * seg;
      y += math.sin(a) * seg;
      pts.add(_Pt(x, y));
    }
    final c = clipLine(pts);
    if (c.length > 1) branches.add(_Branch(c, w));
    if (depth > 0 && c.length > 1) {
      for (var k = 0; k < 2; k++) {
        final idx = 1 + (rnd() * (c.length - 1)).floor();
        if (idx >= c.length) continue;
        final p = c[idx];
        grow(
          p.x,
          p.y,
          a + (k == 0 ? -0.55 : 0.55) + (rnd() - 0.5) * 0.3,
          len * 0.62,
          w * 0.62,
          depth - 1,
        );
      }
    }
  }

  // Extra low limbs from the left edge to fill a taller frame.
  final limbs = <List<double>>[..._limbs];
  for (var y0 = 425.0; y0 < bottom; y0 += 75) {
    limbs.add(<double>[-20, y0, 60, y0 + 30, 140, y0 + 90, 3]);
  }
  for (final ld in limbs) {
    final a = _Pt(ld[0], ld[1]);
    final c = _Pt(ld[2] * rr, ld[3]);
    final b = _Pt(ld[4] * rr, ld[5]);
    final w = ld[6];
    final pts = <_Pt>[for (var i = 0; i <= 24; i++) _quad(a, c, b, i / 24)];
    final cl = clipLine(pts);
    if (cl.length > 1) branches.add(_Branch(cl, w));
    for (var j = 0; j < 7; j++) {
      final t = 0.15 + 0.8 * (j + rnd()) / 7;
      final q = _quad(a, c, b, t);
      grow(
        q.x,
        q.y,
        _quadAngle(a, c, b, t) + (j.isOdd ? 0.5 : -0.4),
        45 + rnd() * 55,
        w * 0.4,
        2,
      );
    }
  }

  double density(double x, double y) {
    final e = ex(y);
    if (x > e) return 0;
    var d = 1.0;
    final ax = (x - 235 * rr) / (80 * rr);
    final ay = (y - 200) / 68;
    final cv = ax * ax + ay * ay;
    if (cv < 1) d *= 0.05 + 0.6 * cv * cv;
    if (y > 235 && x > 165 * rr) d *= 0.12;
    if (y > bottom - 29) d *= 0.5;
    d *= _clamp(0.35 + 1.1 * _vnoise(x / 38, y / 38, seed), 0, 1.2);
    return _clamp01(d);
  }

  double light(double fx, double fy, double cx, double cy, double r) {
    final e = ex(fy);
    var l = 0.28 +
        0.55 * (fx / (470 * rr)) -
        0.35 * math.min(1.1, math.max(0.0, (fy - 170) / 240));
    l += (0.25 * (fx - cx - (fy - cy))) / (2 * r + 1);
    l += 0.15 * _smooth(e - 70, e, fx);
    l += (rnd() - 0.5) * 0.2;
    if (_isBlur(fx, fy)) l -= 0.08;
    return _clamp01(l);
  }

  final core = <_Flower>[];
  final coreBlur = <_Flower>[];
  final groups = <_Group>[];
  final lobeMap = <int, _Group>{};
  final kClumps = math.max(20, (total / 13).round());
  var made = 0;
  final xMax = ex(185) + 20;
  for (var tries = 0; tries < kClumps * 30 && made < kClumps; tries++) {
    final x = -12 + rnd() * xMax;
    final y = -12 + rnd() * (bottom + 26);
    if (rnd() >= density(x, y)) continue;
    made++;
    final r = clumpSize * (0.6 + 0.6 * rnd());
    final q = r / clumpSize;
    final n = math.max(3, (13 * q * q).round());
    _Group? lobe;
    if (x > ex(y) - 55 && y > 15 && y < 250) {
      final key = (y / 40).floor();
      lobe = lobeMap[key];
      if (lobe == null) {
        final yc = key * 40 + 20.0;
        lobe = _Group(
          <_Pt>[],
          <_Flower>[],
          _Pt(ex(yc) - 120, yc),
          _Pt(ex(yc), yc),
          false,
        );
        lobeMap[key] = lobe;
        groups.add(lobe);
      }
    }
    for (var k = 0; k < n; k++) {
      final a = rnd() * _tau;
      final dd = math.sqrt(rnd()) * r;
      final fx = x + math.cos(a) * dd;
      final fy = y + math.sin(a) * dd * 0.85;
      if (fx > ex(fy) + 6 || fy < -12 || fy > bottom + 12 || fx < -12) continue;
      final fr = fs * 0.5 * (0.65 + rnd() * 0.65);
      final fl = light(fx, fy, x, y, r);
      final f = _Flower(fx, fy, fr, fl, rnd() * _tau);
      if (lobe != null) {
        lobe.flowers.add(f);
      } else if (_isBlur(fx, fy)) {
        coreBlur.add(f);
      } else {
        core.add(f);
      }
    }
  }

  // Hanging sprays in the lower right of the crown.
  for (var i = 0; i < sprays; i++) {
    final xr = 195 + 265 * ((i + rnd()) / math.max(1, sprays));
    var x = xr * rr;
    var y = 135 + 0.18 * (xr - 195) + rnd() * 45;
    final len = (60 + rnd() * 130) * (xr < 330 ? 1 : 0.7);
    var a = math.pi / 2 + (rnd() - 0.5) * 0.5;
    final pts = <_Pt>[_Pt(x, y)];
    final flowers = <_Flower>[];
    var dist = 0.0;
    var nextF = 12 + rnd() * 8;
    final steps = (len / 6).ceil();
    for (var s = 0; s < steps; s++) {
      a += (math.pi / 2 - a) * 0.1 + (rnd() - 0.5) * 0.15;
      x += math.cos(a) * 6;
      y += math.sin(a) * 6;
      if (y > bottom - 16) break;
      pts.add(_Pt(x, y));
      dist += 6;
      if (dist >= nextF) {
        nextF = dist + 10 + rnd() * 7;
        final last = s >= steps - 2;
        final fr = last ? 7 + rnd() * 3 : 4 + rnd() * 4;
        final ox = x + (rnd() - 0.5) * 8;
        final oy = y;
        if (ox > ex(oy) + 28) continue;
        final n = (fr * fr * 0.18).round() + 3;
        for (var k = 0; k < n; k++) {
          final aa = rnd() * _tau;
          final dd = math.sqrt(rnd()) * fr;
          final fx = ox + math.cos(aa) * dd;
          final fy = oy + math.sin(aa) * dd * 0.85;
          final rad = fs * 0.5 * (0.65 + rnd() * 0.65);
          final lit = _clamp01(light(fx, fy, ox, oy, fr) + 0.1);
          flowers.add(_Flower(fx, fy, rad, lit, rnd() * _tau));
        }
      }
    }
    if (flowers.isNotEmpty) {
      groups.add(_Group(pts, flowers, pts.first, pts.last, rnd() < 0.3));
    }
  }
  return _Geo(branches, groups, core, coreBlur);
}

// ─── Baking ──────────────────────────────────────────────────────────────────

class _Sprite {
  _Sprite({
    required this.img,
    required this.bx,
    required this.by,
    required this.bw,
    required this.bh,
    required this.ax,
    required this.ay,
    required this.tx,
    required this.ty,
    required this.len,
    required this.back,
    required this.pf,
    required this.ph,
    required this.ph2,
  });

  final ui.Image img;
  final double bx;
  final double by;
  final double bw;
  final double bh;
  final double ax;
  final double ay;
  final double tx;
  final double ty;
  final double len;
  final bool back;
  final double pf;
  final double ph;
  final double ph2;
  double g = 0;
  double gv = 0;
  double th = 0;
}

class _Scene {
  _Scene({
    required this.bg,
    required this.core,
    required this.coreBlur,
    required this.halo,
    required this.bloom,
    required this.sprites,
    required this.u,
  });

  final ui.Image? bg;
  final ui.Image core;
  final ui.Image coreBlur;
  final ui.Image halo;
  final ui.Image bloom;
  final List<_Sprite> sprites;
  final double u;

  void dispose() {
    bg?.dispose();
    core.dispose();
    coreBlur.dispose();
    halo.dispose();
    bloom.dispose();
    for (final s in sprites) {
      s.img.dispose();
    }
  }
}

/// Records [draw] at [scale], optionally blurs it, and keeps it as a picture.
ui.Image _bakeLayer(
  int pw,
  int ph,
  double scale,
  double sigmaPx,
  ui.TileMode tile,
  void Function(Canvas) draw,
) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(scale, scale);
  draw(c);
  final pic = rec.endRecording();
  if (sigmaPx <= 0.3) {
    final img = pic.toImageSync(pw, ph);
    pic.dispose();
    return img;
  }
  final rec2 = ui.PictureRecorder();
  final c2 = Canvas(rec2);
  c2.saveLayer(
    Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()),
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigmaPx,
        sigmaY: sigmaPx,
        tileMode: tile,
      ),
  );
  c2.drawPicture(pic);
  c2.restore();
  pic.dispose();
  final pic2 = rec2.endRecording();
  final img = pic2.toImageSync(pw, ph);
  pic2.dispose();
  return img;
}

void _strokeLine(
  Canvas g,
  List<_Pt> pts,
  double w0,
  double taper,
  Paint p,
  double sx,
  double sy,
) {
  for (var i = 0; i < pts.length - 1; i++) {
    p.strokeWidth = math.max(0.6, w0 * (1 - (i / pts.length) * taper));
    g.drawLine(
      Offset(pts[i].x * sx, pts[i].y * sy),
      Offset(pts[i + 1].x * sx, pts[i + 1].y * sy),
      p,
    );
  }
}

_Scene _bakeScene({
  required double w,
  required double h,
  required double bs,
  required double u,
  required double sx,
  required double sy,
  required int seed,
  required _Geo geo,
  required Color blossom,
  required Color branch,
  required Color? background,
  required double blurSigma,
  required int tier,
}) {
  final pal = _Palette(_rgb(blossom));
  final painter = _FlowerPainter(pal, sx, sy, u, tier);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true
    ..color = branch;

  final pw = math.max(1, (w * bs).ceil());
  final ph = math.max(1, (h * bs).ceil());

  // The static mass of the crown, with its branches behind it.
  final core = _bakeLayer(pw, ph, bs, blurSigma * bs, ui.TileMode.clamp, (g) {
    for (final l in geo.branches) {
      _strokeLine(g, l.pts, l.w * u * 0.5, 0.6, line, sx, sy);
    }
    painter.draw(g, geo.core, bs);
  });

  // The out-of-focus lower left, baked small and stretched back up.
  final fb = 1 / _clamp(1 + 3 * u * 0.5, 1, 12);
  final cbw = math.max(1, (w * bs * fb).ceil());
  final cbh = math.max(1, (h * bs * fb).ceil());
  final coreBlur = _bakeLayer(
    cbw,
    cbh,
    bs * fb,
    blurSigma * bs * fb,
    ui.TileMode.clamp,
    (g) => painter.draw(g, geo.coreBlur, bs * fb),
  );

  // Sprays and lobes that sway.
  final srng = math.Random(seed + 3);
  final sprites = <_Sprite>[];
  final pad = 4 + blurSigma * 3;
  for (final gr in geo.groups) {
    if (gr.flowers.isEmpty) continue;
    var x0 = double.infinity;
    var y0 = double.infinity;
    var x1 = -double.infinity;
    var y1 = -double.infinity;
    for (final p in gr.pts) {
      x0 = math.min(x0, p.x * sx);
      y0 = math.min(y0, p.y * sy);
      x1 = math.max(x1, p.x * sx);
      y1 = math.max(y1, p.y * sy);
    }
    for (final f in gr.flowers) {
      final r = f.r * u;
      x0 = math.min(x0, f.x * sx - r);
      y0 = math.min(y0, f.y * sy - r);
      x1 = math.max(x1, f.x * sx + r);
      y1 = math.max(y1, f.y * sy + r);
    }
    x0 -= pad;
    y0 -= pad;
    x1 += pad;
    y1 += pad;
    final iw = math.max(1, ((x1 - x0) * bs).ceil());
    final ih = math.max(1, ((y1 - y0) * bs).ceil());
    final left = x0;
    final top = y0;
    final img = _bakeLayer(iw, ih, bs, blurSigma * bs, ui.TileMode.decal, (g) {
      g.translate(-left, -top);
      if (gr.pts.length > 1) {
        _strokeLine(g, gr.pts, 0.9 * u * 0.5, 0.4, line, sx, sy);
      }
      painter.draw(g, gr.flowers, bs);
    });
    final ax = gr.anchor.x * sx;
    final ay = gr.anchor.y * sy;
    final tx = gr.tip.x * sx;
    final ty = gr.tip.y * sy;
    final pf = 0.7 + srng.nextDouble() * 0.6;
    final sph = srng.nextDouble() * _tau;
    final sph2 = srng.nextDouble() * _tau;
    sprites.add(
      _Sprite(
        img: img,
        bx: x0,
        by: y0,
        bw: x1 - x0,
        bh: y1 - y0,
        ax: ax,
        ay: ay,
        tx: tx,
        ty: ty,
        len: math.sqrt((tx - ax) * (tx - ax) + (ty - ay) * (ty - ay)),
        back: gr.back,
        pf: pf,
        ph: sph,
        ph2: sph2,
      ),
    );
  }

  // The glow: the brightest blossoms at a quarter size, and a soft halo.
  const hq = 0.25;
  final hw = math.max(2, (w * bs * hq).ceil());
  final hh = math.max(2, (h * bs * hq).ceil());
  final hi = <_Flower>[
    for (final f in geo.core)
      if (f.l >= 0.78) f,
    for (final f in geo.coreBlur)
      if (f.l >= 0.78) f,
    for (final gr in geo.groups)
      for (final f in gr.flowers)
        if (f.l >= 0.78) f,
  ];
  void drawHi(Canvas g) {
    final p = Paint()..isAntiAlias = true;
    for (final f in hi) {
      p.color = pal.peak.withValues(alpha: 0.7 * ((f.l - 0.78) / 0.22));
      g.drawCircle(Offset(f.x * sx, f.y * sy), f.r * u * 1.4, p);
    }
  }

  final bloom = _bakeLayer(hw, hh, bs * hq, 0, ui.TileMode.clamp, drawHi);
  final target = math.max(4.0, 10 * u);
  final halo = _bakeLayer(
    hw,
    hh,
    bs * hq,
    math.max(1.0, target * bs * hq * 0.4),
    ui.TileMode.clamp,
    drawHi,
  );

  // The backdrop, at a smaller size: a fade to dark below and a haze.
  final k = bs * 0.4;
  final bgw = math.max(2, (w * k).ceil());
  final bgh = math.max(2, (h * k).ceil());
  final bgColor = background;
  final bg = bgColor == null ? null : _bakeLayer(bgw, bgh, k, 0, ui.TileMode.clamp, (g) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    g.drawRect(rect, Paint()..color = bgColor);
    g.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.7),
          Offset(0, h),
          const <Color>[Color(0x00000000), Color(0x59000000)],
        ),
    );
    const haze = Color(0xFF2F2A2C);
    g.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(410 * sx, 150 * sy),
          250 * u,
          <Color>[haze.withValues(alpha: 0.4), haze.withValues(alpha: 0)],
        ),
    );
  });

  return _Scene(
    bg: bg,
    core: core,
    coreBlur: coreBlur,
    halo: halo,
    bloom: bloom,
    sprites: sprites,
    u: u,
  );
}