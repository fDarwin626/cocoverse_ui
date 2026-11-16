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
const double _deg = math.pi / 180;

// Hair length at 100 percent, in ball radii, and how far combed fur stands
// proud of the skin per unit of length.
const double _furMax = 0.4;
const double _furReach = 0.6;

// The pebbled core inside the ribbon, in radii, and the ribbon's thickness.
const double _coreR = 0.8;
const double _shellThick = 0.035;

// The pose the ball starts in, and the camera, as in the reference.
const double _restYaw = 240 * _deg;
const double _camD = 3.7320508; // 1 / tan(15 degrees): a 30 degree lens
const double _camTilt = 9 * _deg;
const double _axisLean = -3 * _deg;

// The light: from up and a little left, in front.
const double _lightAngle = -20 * _deg;
const double _lightElev = 40 * _deg;
const double _ambient = 0.32;
const double _specular = 0.7;

// The coat.
const double _strandTilt = 0.3;
const double _comb = 0.55;
const double _splay = 0.2;
const double _lenJitter = 0.3;
const double _hairLift = 0.4;
const double _clumpPull = 0.1;
const int _clumpSize = 3;
const double _clumpR = 0.02;
const double _semEdge = 1.2;
const double _fringeK = 0.9;

// Body radius at the reference size, so hair width scales with the ball.
const double _refRadiusPx = 480 / 2 / (1 + 0.5 * _furMax * _furReach);

// The pebble texture: its size in pixels and the tile size in radii.
const int _pebbleN = 128;
const double _cell = 0.3277;
const int _coreTiles = 15;

// Numbers per strand in the strand table.
const int _furStride = 16;
const int _maxStrands = 12000;
const int _maxRibV = 3000;
const int _maxCoreV = 2800;

// Depth buckets for ordering hair without allocating.
const int _sortBuckets = 256;

// Per-row hair values for root, middle and tip. They never change, so they
// are worked out once here, not per strand per frame.
const List<double> _rowOccl = <double>[0.25, 0.7117, 1.0];
const List<double> _rowMix = <double>[0.0, 1.0, 1.0];

/// A furry ball peeled into one spiral ribbon, wound about two and a half
/// times round a glowing pebbled core. It turns on its axis, so the almond
/// shaped gaps between the windings screw down its face.
///
/// Use it as a loading screen (give it [progress]), as the hero of an
/// onboarding page, or as an empty state. It fills the space it is given.
///
/// ```dart
/// SizedBox(
///   width: 220,
///   height: 220,
///   child: Plush.loader(progress: 0.4, child: Text('40%')),
/// )
/// ```
class Plush extends StatefulWidget {
  /// Creates a plush ball.
  const Plush({
    super.key,
    this.fur = const Color(0xFF0074FF),
    this.highlight = const Color(0xFFF2F2F2),
    this.core = const Color(0xFFFFF300),
    this.skin,
    this.root,
    this.showCore = true,
    this.glow = 60.0,
    this.windings = 5,
    this.furLength = 22.0,
    this.furDensity = 70.0,
    this.speed = 50.0,
    this.hover = 50.0,
    this.progress,
    this.child,
    this.scale = 92.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.angle = 0.0,
    this.tilt = 0.0,
    this.seed = 7,
    this.background,
    this.interactive = true,
    this.paused = false,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// A loading indicator: it turns briskly, ignores touch and uses a lighter
  /// coat. Give it [progress] from 0 to 1 and the ribbon winds up as it
  /// goes, with the core glowing through the part not yet wound. Leave
  /// [progress] null for an endless loader.
  factory Plush.loader({
    Key? key,
    double? progress,
    Widget? child,
    Color fur = const Color(0xFF0074FF),
    Color highlight = const Color(0xFFF2F2F2),
    Color core = const Color(0xFFFFF300),
    double scale = 92,
    Color? background,
    bool paused = false,
    EffectController? controller,
    String? semanticLabel = 'Loading',
  }) {
    return Plush(
      key: key,
      fur: fur,
      highlight: highlight,
      core: core,
      progress: progress,
      scale: scale,
      background: background,
      paused: paused,
      controller: controller,
      semanticLabel: semanticLabel,
      windings: 4,
      furLength: 20,
      furDensity: 60,
      speed: 80,
      hover: 0,
      interactive: false,
      quality: EffectQuality.medium,
      child: child,
    );
  }

  /// A calm hero for an onboarding page or an empty state: it turns slowly
  /// and can be dragged round, picking up speed while you hold it.
  factory Plush.calm({
    Key? key,
    Widget? child,
    Color fur = const Color(0xFF0074FF),
    Color highlight = const Color(0xFFF2F2F2),
    Color core = const Color(0xFFFFF300),
    double scale = 92,
    Color? background,
    bool paused = false,
    EffectController? controller,
    String? semanticLabel,
  }) {
    return Plush(
      key: key,
      fur: fur,
      highlight: highlight,
      core: core,
      scale: scale,
      background: background,
      paused: paused,
      controller: controller,
      semanticLabel: semanticLabel,
      speed: 12,
      hover: 50,
      interactive: true,
      child: child,
    );
  }

  /// The mid-tone colour of the fur.
  final Color fur;

  /// The colour of the lit hair tips and the white rim along the gaps.
  final Color highlight;

  /// The colour of the glowing core and of the pebbled inner face seen
  /// through the gaps.
  final Color core;

  /// The colour of the ribbon's outer surface under the fur.
/// Null, the default, uses a dark shade of [fur], so any gap between hairs
  /// looks like undercoat and not like bare skin.
  final Color? skin;
  /// The colour at the base of each hair.
  final Color? root;

  /// Whether the pebbled core shows inside the ribbon. Hidden, the gaps
  /// open onto the hollow shell.
  final bool showCore;

  /// Light the core gives off, from 0 to 100. 0 turns it off.
  final double glow;

  /// How many windings of the ribbon cross the front, from 2 to 5.
  final int windings;

  /// Length of the hair, from 0 to 100 percent.
  final double furLength;

  /// How many hairs cover the ribbon, from 0 to 100 percent. Lower
  /// qualities draw fewer.
  final double furDensity;

  /// Turning speed, from 0 to 100. 50 is one turn every 3 seconds, and 0
  /// stops it.
  final double speed;

  /// How much touch speeds it up, from 0 to 100. 0 turns it off.
  final double hover;

  /// Progress from 0 to 1. Null shows the finished ball. A number winds the
  /// ribbon up from the bottom to that point, with the core glowing through
  /// the rest.
  final double? progress;

  /// Anything to show in the middle, such as a percentage, an icon or a
  /// logo. It sits on top of the ball.
  final Widget? child;

  /// How much of the box's shorter side the ball fills, fur included, from
  /// 20 to 100 percent.
  final double scale;

  /// Moves the ball across the box, as a percentage of its width, from -50
  /// to 50. Positive is right.
  final double offsetX;

  /// Moves the ball down the box, as a percentage of its height, from -50
  /// to 50. Positive is down.
  final double offsetY;

  /// Turns the ball in the picture, in degrees. Positive is clockwise.
  final double angle;

  /// Leans the ball about the horizontal axis, in degrees. Positive tips its
  /// top away from the viewer.
  final double tilt;

  /// Changes the layout of the hairs.
  final int seed;

  /// Fill behind the ball. Null means transparent. The original is black.
  final Color? background;

  /// Whether dragging and touching do anything. Turn it off inside lists
  /// that scroll.
  final bool interactive;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings use fewer hairs and a coarser ribbon.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] puts the ball back to its
  /// starting pose.
  final EffectController? controller;

  /// Screen-reader description. Null marks the ball as decorative. For a
  /// loader, use something like 'Loading'.
  final String? semanticLabel;

  @override
  State<Plush> createState() => _PlushState();
}

class _PlushState extends State<Plush> {
  final Paint _plain = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _textured = Paint()..color = const Color(0xFFFFFFFF);
  ui.ImageShader? _shader;

  // Motion.
  double _yaw = _restYaw;
  double _spinVel = 0;
  double _over = 0;
  double _press = 0;
  bool _hovered = false;
  bool _dragging = false;
  bool _reduced = false;
  double _lastTime = 0;
  int _seenResets = 0;

  // A still picture is drawn once and kept.
  ui.Picture? _cache;
  Plush? _cacheFor;
  Size _cacheSize = Size.zero;

  // The ribbon model and the layout for this frame.
  _Geo? _geo;
  double _geoTurns = -1;
  double _pEff = 1;
  double _cx = 0;
  double _cy = 0;
  double _rad = 1;
  double _rc = 1;
  double _rs = 0;
  double _cyw = 1;
  double _syw = 0;
  double _ct = 1;
  double _s1 = 0;
  double _px = 0;
  double _py = 0;
  double _lx = 0;
  double _ly = 1;
  double _lz = 0;
  double _lox = 0;
  double _loy = 1;
  double _loz = 0;

  // Colours as 0 to 1 channels.
  double _furR = 0;
  double _furG = 0;
  double _furB = 0;
  double _hiR = 0;
  double _hiG = 0;
  double _hiB = 0;
  double _rootR = 0;
  double _rootG = 0;
  double _rootB = 0;
  double _inR = 0;
  double _inG = 0;
  double _inB = 0;
  double _skinR = 0;
  double _skinG = 0;
  double _skinB = 0;
  double _glowK = 0;
  double _widthPx = 3;

  // The coat.
  _Fur? _fur;
  String _furKey = '';
  final Int32List _cand = Int32List(_maxStrands);
  final Int32List _candB = Int32List(_maxStrands);
  final Int32List _order = Int32List(_maxStrands);
  final Int32List _bucket = Int32List(_sortBuckets + 1);
  final Float64List _candZ = Float64List(_maxStrands);
  final Float32List _fPos = Float32List(_maxStrands * 10);
  final Int32List _fCol = Int32List(_maxStrands * 5);
  final Uint16List _fIdx = Uint16List(_maxStrands * 9);

  // The ribbon and the core, in the ball's own space.
  String _shellKey = '';
  int _segs = 0;
  int _rows = 0;
  int _cuN = 0;
  int _cvN = 0;
  Float64List _ux = Float64List(0);
  Float64List _uy = Float64List(0);
  Float64List _uz = Float64List(0);
  Float64List _cux = Float64List(0);
  Float64List _cuy = Float64List(0);
  Float64List _cuz = Float64List(0);
  final Float32List _iTex = Float32List((_maxRibV + _maxCoreV) * 2);
  final Float32List _iPos = Float32List((_maxRibV + _maxCoreV) * 2);
  final Int32List _iCol = Int32List(_maxRibV + _maxCoreV);
  final Uint16List _iIdx = Uint16List(6 * 5200);
  final Float32List _oPos = Float32List(_maxRibV * 2);
  final Int32List _oCol = Int32List(_maxRibV);
  final Uint16List _oIdx = Uint16List(6 * 2600);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
    _pebbleFuture ??= _makePebble();
    unawaited(
      _pebbleFuture!.then((image) {
        if (!mounted) return;
        _shader = ui.ImageShader(
          image,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Float64List.fromList(<double>[
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
          filterQuality: FilterQuality.medium,
        );
        _textured.shader = _shader;
        _cache?.dispose();
        _cache = null;
      }),
    );
  }

  @override
  void didUpdateWidget(Plush oldWidget) {
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
    _cache?.dispose();
    _cache = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _yaw = _restYaw;
      _spinVel = 0;
      _cache?.dispose();
      _cache = null;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
    _spinVel = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _yaw += details.delta.dx * 0.012;
  }

  void _onPanEnd(DragEndDetails details) {
    _dragging = false;
    _spinVel = _clamp(details.velocity.pixelsPerSecond.dx * 0.012, -14, 14);
  }

  void _onPanCancel() {
    _dragging = false;
  }

  void _step(double dt) {
    final w = widget;
    final hoverK = _clamp(w.hover, 0, 100) / 50;
    final overT = (_hovered || _dragging) && w.interactive ? 1.0 : 0.0;
    final pressT = _dragging && w.interactive ? 1.0 : 0.0;
    if (dt > 0) {
      _over += (overT - _over) * (1 - math.exp(-dt / 0.4));
      _press += (pressT - _press) * (1 - math.exp(-dt / 0.3));
    }
    final auto = _reduced ? 0.0 : _clamp(w.speed, 0, 100) / 50;
    final rate =
        (_tau / 3.0) * (auto + (_press + _over) * hoverK * math.max(auto, 0.5));
    if (dt > 0) {
      _yaw += rate * dt;
      if (!_dragging) {
        _yaw += _spinVel * dt;
        _spinVel *= math.exp(-dt * 2.2);
      }
    }
    _yaw = _yaw % _tau;
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 4 || size.height < 4) return;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    if (widget.paused) dt = 0;
    if (_reduced) {
      _yaw = _restYaw;
      _spinVel = 0;
    }
    _step(dt);

    final auto = _reduced ? 0.0 : _clamp(widget.speed, 0, 100) / 50;
    final isStatic =
        auto <= 0 &&
        _over < 1e-3 &&
        _press < 1e-3 &&
        _spinVel.abs() < 1e-3 &&
        !_dragging;
    if (!isStatic) {
      _cache?.dispose();
      _cache = null;
      _draw(canvas, size);
      return;
    }
    final cached = _cache;
    if (cached != null && identical(_cacheFor, widget) && _cacheSize == size) {
      canvas.drawPicture(cached);
      return;
    }
    final recorder = ui.PictureRecorder();
    _draw(Canvas(recorder), size);
    final picture = recorder.endRecording();
    _cache?.dispose();
    _cache = picture;
    _cacheFor = widget;
    _cacheSize = size;
    canvas.drawPicture(picture);
  }

  /// Projects a point in the camera's space to layout pixels.
  void _scr(double x, double y, double z) {
    final wd = math.max((_camD - z) / _camD, 0.05);
    final qx = x * _rad;
    final qy = y * _rad;
    _px = _cx + (_rc * qx + _rs * qy) / wd;
    _py = _cy - (-_rs * qx + _rc * qy) / wd;
  }

  void _draw(Canvas canvas, Size size) {
    final w = widget;

    // Layout: the ball, fur included, fills a share of the shorter side.
    final furLen = _clamp(w.furLength, 0, 100) / 100 * _furMax;
    final sizePx =
        math.min(size.width, size.height) * _clamp(w.scale, 20, 100) / 100;
    final radius = sizePx / 2 / (1 + furLen * _furReach);
    _rad = radius;
    _cx = size.width / 2 + _clamp(w.offsetX, -50, 50) / 100 * size.width;
    _cy = size.height / 2 + _clamp(w.offsetY, -50, 50) / 100 * size.height;
    final roll = w.angle * _deg + _axisLean;
    _rc = math.cos(roll);
    _rs = math.sin(roll);

    // Camera: the reference tilt, less Placement's tilt, and the spin.
    final tilt = _camTilt - _clamp(w.tilt, -60, 60) * _deg;
    _ct = math.cos(tilt);
    _s1 = math.sin(tilt);
    _cyw = math.cos(_yaw);
    _syw = math.sin(_yaw);

    // The light, in the camera's space and in the ball's own.
    _lx = math.sin(_lightAngle) * math.cos(_lightElev);
    _ly = math.cos(_lightAngle) * math.cos(_lightElev);
    _lz = math.sin(_lightElev);
    _lox = _cyw * _lx + _s1 * _syw * _ly - _ct * _syw * _lz;
    _loy = _ct * _ly + _s1 * _lz;
    _loz = _syw * _lx - _s1 * _cyw * _ly + _ct * _cyw * _lz;

    // Colours.
    _furR = w.fur.r;
    _furG = w.fur.g;
    _furB = w.fur.b;
    _hiR = w.highlight.r;
    _hiG = w.highlight.g;
    _hiB = w.highlight.b;
    _rootR = w.root?.r ?? w.fur.r * 0.3;
    _rootG = w.root?.g ?? w.fur.g * 0.3;
    _rootB = w.root?.b ?? w.fur.b * 0.3;
    _inR = w.core.r;
    _inG = w.core.g;
    _inB = w.core.b;
    _skinR = w.skin?.r ?? w.fur.r * 0.4;
    _skinG = w.skin?.g ?? w.fur.g * 0.4;
    _skinB = w.skin?.b ?? w.fur.b * 0.4;
    _glowK = w.showCore ? _clamp(w.glow, 0, 100) / 100 : 0.0;

    // The ribbon, and how far it has wound up.
    final turns = _clamp(w.windings.toDouble(), 2, 5);
    if (_geo == null || _geoTurns != turns) {
      _geo = _geometry(turns);
      _geoTurns = turns;
    }
    final g = _geo!;
    final given = w.progress;
    _pEff = given == null ? 1.0 : _clamp(given, 0, 1);
    final ribbon = _pEff > 0.004;

    final (segs, rows, cuN, cvN, furK) = switch (w.quality) {
      EffectQuality.low => (72, 5, 24, 12, 0.18),
      EffectQuality.medium => (110, 6, 36, 18, 0.35),
      EffectQuality.high => (160, 8, 48, 24, 0.6),

    };
    _ensureShell(g, segs, rows, cuN, cvN);

    // The coat: fewer, chunkier hairs than the original, widened to cover.
    final density = _clamp(w.furDensity, 0, 100);
    final count = ((1200 + density * 90) * furK).round().clamp(0, _maxStrands);
    final furKey = '$count|${w.seed}|$turns|${w.furLength}';
    if (furKey != _furKey) {
      _fur = _buildFur(count, w.seed, g, furLen);
      _furKey = furKey;
    }
    final sizeK = _clamp(radius / _refRadiusPx, 0.45, 1.6);
    final cover = _clamp(
      math.sqrt((1000 + density * 220) / math.max(count, 1)),
      1,
      2.4,
    );
    _widthPx = 3.8 * sizeK * cover;
    final fur = ribbon && furLen > 0.002 && count > 0;

    // Back to front: far hair, the inside of the ribbon and the core, the
    // ribbon's outer skin, then the near hair.
    if (fur) _furPass(canvas, true);
    _shellPass(canvas, g, ribbon, w.showCore);
    if (fur) _furPass(canvas, false);
  }

  void _shellPass(Canvas canvas, _Geo g, bool ribbon, bool showCore) {
    final cols = _segs + 1;
    final nRib = cols * (_rows + 1);
    final cols2 = _cuN + 1;
    final nCore = cols2 * (_cvN + 1);
    const thin = 1 - _shellThick;
    final rc =
        _coreR *
        _camD /
        math.sqrt(math.max(_camD * _camD - _coreR * _coreR, 1e-3));

    // Inside of the ribbon first, then the core.
    var nIn = 0;
    if (ribbon) {
      for (var k = 0; k < nRib; k++) {
        final x = _ux[k];
        final y = _uy[k];
        final z = _uz[k];
        final vx = _cyw * x + _syw * z;
        final vy = _s1 * _syw * x + _ct * y - _s1 * _cyw * z;
        final vz = -_ct * _syw * x + _s1 * y + _ct * _cyw * z;
        _scr(vx * thin, vy * thin, vz * thin);
        _iPos[k * 2] = _px;
        _iPos[k * 2 + 1] = _py;
        // The inside shows only on the far half.
        final ex = -vx;
        final ey = -vy;
        final ez = _camD - vz;
        final facing =
            (vx * ex + vy * ey + vz * ez) /
            math.sqrt(ex * ex + ey * ey + ez * ez);
        if (facing > 0.25) {
          _iCol[k] = 0xFF000000;
          continue;
        }
        final lit = _litAt(g, x * thin, y * thin, z * thin);
        final dif = math.max(-(x * _lox + y * _loy + z * _loz), 0.0);
        final bounce = 0.3 + 0.3 * _smooth(-1, 0.6, vz);
        final base = (bounce * (0.6 + 0.6 * dif) + 1.1 * dif * lit) * 1.2;
        final qx = vx * _camD / math.max(_camD - vz, 0.05);
        final qy = vy * _camD / math.max(_camD - vz, 0.05);
        final dd = math.max(math.sqrt(qx * qx + qy * qy) - rc, 0.0);
        final halo = _glowK * (0.25 + 1.2 * math.exp(-dd * dd / 0.03));
        _iCol[k] = _pack(
          _inR * (base + halo),
          _inG * (base + halo),
          _inB * (base + halo),
          255,
        );
      }
      nIn = nRib;
    }

    var nTot = nIn;
    if (showCore) {
      for (var k = 0; k < nCore; k++) {
        final x = _cux[k];
        final y = _cuy[k];
        final z = _cuz[k];
        final vx = _cyw * x + _syw * z;
        final vy = _s1 * _syw * x + _ct * y - _s1 * _cyw * z;
        final vz = -_ct * _syw * x + _s1 * y + _ct * _cyw * z;
        final o = nIn + k;
        _scr(vx * _coreR, vy * _coreR, vz * _coreR);
        _iPos[o * 2] = _px;
        _iPos[o * 2 + 1] = _py;
        final ex = -vx;
        final ey = -vy;
        final ez = _camD - vz;
        final facing =
            (vx * ex + vy * ey + vz * ez) /
            math.sqrt(ex * ex + ey * ey + ez * ez);
        if (facing < -0.2) {
          _iCol[o] = 0xFF000000;
          continue;
        }
        final lit = ribbon
            ? _litAt(g, x * _coreR, y * _coreR, z * _coreR)
            : 1.0;
        final dif = math.max(x * _lox + y * _loy + z * _loz, 0.0);
        final bounce = 0.3 + 0.3 * _smooth(-1, 0.6, vz * _coreR);
        final base = (bounce * (0.6 + 0.6 * dif) + 1.1 * dif * lit) * 1.2;
        final rim = 1 - math.max(vz, 0.0);
        final glow = _glowK * (0.35 + 1.4 * rim * rim);
        _iCol[o] = _pack(
          _inR * (base + glow),
          _inG * (base + glow),
          _inB * (base + glow),
          255,
        );
      }
      nTot += nCore;
    }

    // The faces turned toward the viewer.
    var used = 0;
    if (ribbon) {
      for (var j = 0; j < _rows; j++) {
        for (var i = 0; i < _segs; i++) {
          final a = j * cols + i;
          final b = a + 1;
          final c = a + cols;
          final d = c + 1;
          if (_cross(_iPos, a, b, c) <= 0) continue;
          _iIdx[used] = a;
          _iIdx[used + 1] = b;
          _iIdx[used + 2] = c;
          _iIdx[used + 3] = b;
          _iIdx[used + 4] = d;
          _iIdx[used + 5] = c;
          used += 6;
        }
      }
    }
    if (showCore) {
      for (var j = 0; j < _cvN; j++) {
        for (var i = 0; i < _cuN; i++) {
          final a = nIn + j * cols2 + i;
          final b = a + 1;
          final c = a + cols2;
          final d = c + 1;
          if (_cross(_iPos, a, b, c) >= 0) continue;
          _iIdx[used] = a;
          _iIdx[used + 1] = b;
          _iIdx[used + 2] = c;
          _iIdx[used + 3] = b;
          _iIdx[used + 4] = d;
          _iIdx[used + 5] = c;
          used += 6;
        }
      }
    }
    if (used > 0 && nTot > 0) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_iPos, 0, nTot * 2),
        textureCoordinates: Float32List.sublistView(_iTex, 0, nTot * 2),
        colors: Int32List.sublistView(_iCol, 0, nTot),
        indices: Uint16List.sublistView(_iIdx, 0, used),
      );
      canvas.drawVertices(
        vertices,
        ui.BlendMode.modulate,
        _shader != null ? _textured : _plain,
      );
      vertices.dispose();
    }

    // The outer skin, over all of that.
    if (!ribbon) return;
    for (var k = 0; k < nRib; k++) {
      final x = _ux[k];
      final y = _uy[k];
      final z = _uz[k];
      final vx = _cyw * x + _syw * z;
      final vy = _s1 * _syw * x + _ct * y - _s1 * _cyw * z;
      final vz = -_ct * _syw * x + _s1 * y + _ct * _cyw * z;
      _scr(vx, vy, vz);
      _oPos[k * 2] = _px;
      _oPos[k * 2 + 1] = _py;
      final f =
          _ambient +
          (1 - _ambient) * math.max(vx * _lx + vy * _ly + vz * _lz, 0.0);
      _oCol[k] = _pack(_skinR * f, _skinG * f, _skinB * f, 255);
    }
    var ou = 0;
    for (var j = 0; j < _rows; j++) {
      for (var i = 0; i < _segs; i++) {
        final a = j * cols + i;
        final b = a + 1;
        final c = a + cols;
        final d = c + 1;
        if (_cross(_oPos, a, b, c) >= 0) continue;
        _oIdx[ou] = a;
        _oIdx[ou + 1] = b;
        _oIdx[ou + 2] = c;
        _oIdx[ou + 3] = b;
        _oIdx[ou + 4] = d;
        _oIdx[ou + 5] = c;
        ou += 6;
      }
    }
    if (ou == 0) return;
    final skin = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_oPos, 0, nRib * 2),
      colors: Int32List.sublistView(_oCol, 0, nRib),
      indices: Uint16List.sublistView(_oIdx, 0, ou),
    );
    canvas.drawVertices(skin, ui.BlendMode.modulate, _plain);
    skin.dispose();
  }

  /// How lit a point inside the shell is: one ray to the light, which only
  /// gets out where it leaves through a gap in the ribbon.
  double _litAt(_Geo g, double x, double y, double z) {
    final pl = x * _lox + y * _loy + z * _loz;
    final pp = x * x + y * y + z * z;
    final tx = -pl + math.sqrt(math.max(pl * pl - pp + 1, 0.0));
    final sd = _bandSD(g, _pEff, x + _lox * tx, y + _loy * tx, z + _loz * tx);
    return 1 - _smooth(-0.12, 0.12, sd);
  }

  /// One side of the coat: strands rooted on the far half (drawn before the
  /// ribbon, seen only through its gaps) or on the near half (drawn after it).
  void _furPass(Canvas canvas, bool far) {
    final fur = _fur;
    if (fur == null) return;
    final d = fur.data;
    var n = 0;
    for (var i = 0; i < fur.count; i++) {
      final o = i * _furStride;
      if (d[o + 12] > _pEff) continue;
      final x = d[o];
      final y = d[o + 1];
      final z = d[o + 2];
      final vx = _cyw * x + _syw * z;
      final vy = _s1 * _syw * x + _ct * y - _s1 * _cyw * z;
      final vz = -_ct * _syw * x + _s1 * y + _ct * _cyw * z;
      final ex = -vx;
      final ey = -vy;
      final ez = _camD - vz;
      final facing =
          (vx * ex + vy * ey + vz * ez) /
          (0.995 * math.sqrt(ex * ex + ey * ey + ez * ez));
      final edge = d[o + 9];
      // Far hair is hidden by the ribbon unless it is fringe at a gap.
      if (facing < -0.45 && edge < 0.15) continue;
      if (far != (facing < 0)) continue;
      _cand[n] = i;
      _candZ[n] = vz;
      n++;
    }
    if (n == 0) return;
    // Back to front by depth, using a counting sort: no allocation.
    final bucket = _bucket;
    bucket.fillRange(0, _sortBuckets + 1, 0);
    for (var q = 0; q < n; q++) {
      var bk = ((_candZ[q] + 1.6) * (_sortBuckets / 3.2)).toInt();
      if (bk < 0) {
        bk = 0;
      } else if (bk > _sortBuckets - 1) {
        bk = _sortBuckets - 1;
      }
      _candB[q] = bk;
      bucket[bk + 1]++;
    }
    for (var b = 0; b < _sortBuckets; b++) {
      bucket[b + 1] += bucket[b];
    }
    for (var q = 0; q < n; q++) {
      _order[bucket[_candB[q]]++] = q;
    }

    final w1 = _widthPx;
    final half0 = math.max(w1, 1.0) * 0.5;
    final half1 = math.max(w1 * 0.82, 1.0) * 0.5;
    var vb = 0;
    var ib = 0;
    for (var q = 0; q < n; q++) {
      final i = _cand[_order[q]];
      final o = i * _furStride;
      final r0x = d[o];
      final r0y = d[o + 1];
      final r0z = d[o + 2];
      final c1x = d[o + 3];
      final c1y = d[o + 4];
      final c1z = d[o + 5];
      final e1x = d[o + 6];
      final e1y = d[o + 7];
      final e1z = d[o + 8];
      final edge = d[o + 9];
      final bright = d[o + 10];
      final lipF = d[o + 11];
      final mx = 0.25 * r0x + 0.5 * c1x + 0.25 * e1x;
      final my = 0.25 * r0y + 0.5 * c1y + 0.25 * e1y;
      final mz = 0.25 * r0z + 0.5 * c1z + 0.25 * e1z;

      // Root, middle and tip in the camera's space.
      final p0x = _cyw * r0x + _syw * r0z;
      final p0y = _s1 * _syw * r0x + _ct * r0y - _s1 * _cyw * r0z;
      final p0z = -_ct * _syw * r0x + _s1 * r0y + _ct * _cyw * r0z;
      final p1x = _cyw * mx + _syw * mz;
      final p1y = _s1 * _syw * mx + _ct * my - _s1 * _cyw * mz;
      final p1z = -_ct * _syw * mx + _s1 * my + _ct * _cyw * mz;
      final p2x = _cyw * e1x + _syw * e1z;
      final p2y = _s1 * _syw * e1x + _ct * e1y - _s1 * _cyw * e1z;
      final p2z = -_ct * _syw * e1x + _s1 * e1y + _ct * _cyw * e1z;

      // Shading: diffuse and sheen along the hair, brighter where the coat
      // is seen edge-on.
      final nx = p0x / 0.995;
      final ny = p0y / 0.995;
      final nz = p0z / 0.995;
      var tx = p2x - p0x;
      var ty = p2y - p0y;
      var tz = p2z - p0z;
      final tl0 = math.max(math.sqrt(tx * tx + ty * ty + tz * tz), 1e-6);
      tx /= tl0;
      ty /= tl0;
      tz /= tl0;
      var ex = -p1x;
      var ey = -p1y;
      var ez = _camD - p1z;
      final el = math.max(math.sqrt(ex * ex + ey * ey + ez * ez), 1e-6);
      ex /= el;
      ey /= el;
      ez /= el;
      final shade = _smooth(-0.35, 0.85, nx * _lx + ny * _ly + nz * _lz);
      final tl = tx * _lx + ty * _ly + tz * _lz;
      final kd = math.sqrt(math.max(1 - tl * tl, 0.0));
      var hx = _lx + ex;
      var hy = _ly + ey;
      var hz = _lz + ez;
      final hl = math.max(math.sqrt(hx * hx + hy * hy + hz * hz), 1e-6);
      hx /= hl;
      hy /= hl;
      hz /= hl;
      final th2 = tx * hx + ty * hy + tz * hz;
      final kq = math.max(1 - th2 * th2, 0.0);
      final kq2 = kq * kq;
      final kq4 = kq2 * kq2;
      final kq8 = kq4 * kq4;
      final ks = kq8 * kq4 * kq2 * kq; // kq^15, same as sqrt(kq)^30
      final graze = 1 - (nx * ex + ny * ey + nz * ez).abs();
      final semK = 1 + _semEdge * graze * graze;
      final lit = _ambient + (1 - _ambient) * kd * shade;

      // Three rows up the hair: root, middle, tip.
      for (var r = 0; r < 3; r++) {
        final s = r * 0.5;
        final occl = _rowOccl[r];
        final mixB = _rowMix[r];
        final body = 0.55 + 0.9 * bright;
        var cr = (_rootR + (_furR - _rootR) * mixB) * body * lit * occl;
        var cg = (_rootG + (_furG - _rootG) * mixB) * body * lit * occl;
        var cb = (_rootB + (_furB - _rootB) * mixB) * body * lit * occl;
        final sp = ks * _specular * shade * _smooth(0.1, 0.9, s);
        cr += _hiR * sp;
        cg += _hiG * sp;
        cb += _hiB * sp;
        cr *= semK;
        cg *= semK;
        cb *= semK;
        // The upper lip of every gap is the brightest thing: a white rim.
        final lip = lipF * _fringeK * _smooth(0, 0.45, s);
        cr += (_hiR * (0.7 + 0.3 * shade) - cr) * lip;
        cg += (_hiG * (0.7 + 0.3 * shade) - cg) * lip;
        cb += (_hiB * (0.7 + 0.3 * shade) - cb) * lip;
        // Fur at the gap lips is lit from below by the core's glow.
        final gl = _glowK * edge * (1 - s) * 0.7;
        cr += _inR * gl;
        cg += _inG * gl;
        cb += _inB * gl;
        final a8 = r == 0 ? 0 : (r == 1 ? 255 : 217);
        final col = _pack(cr, cg, cb, a8);
        if (r == 0) {
          _fCol[vb] = col;
          _fCol[vb + 1] = col;
        } else if (r == 1) {
          _fCol[vb + 2] = col;
          _fCol[vb + 3] = col;
        } else {
          _fCol[vb + 4] = col;
        }
      }

      // Screen positions, with the width taken across the hair.
      _scr(p0x, p0y, p0z);
      final x0 = _px;
      final y0 = _py;
      _scr(p1x, p1y, p1z);
      final x1 = _px;
      final y1 = _py;
      _scr(p2x, p2y, p2z);
      final x2 = _px;
      final y2 = _py;

      var dx = x1 - x0;
      var dy = y1 - y0;
      var dl = math.sqrt(dx * dx + dy * dy);
      if (dl < 1e-6) {
        dx = 0;
        dy = 1;
      } else {
        dx /= dl;
        dy /= dl;
      }
      final a0x = -dy * half0;
      final a0y = dx * half0;
      dx = x2 - x0;
      dy = y2 - y0;
      dl = math.sqrt(dx * dx + dy * dy);
      if (dl < 1e-6) {
        dx = 0;
        dy = 1;
      } else {
        dx /= dl;
        dy /= dl;
      }
      final a1x = -dy * half1;
      final a1y = dx * half1;

      _fPos[vb * 2] = x0 + a0x;
      _fPos[vb * 2 + 1] = y0 + a0y;
      _fPos[vb * 2 + 2] = x0 - a0x;
      _fPos[vb * 2 + 3] = y0 - a0y;
      _fPos[vb * 2 + 4] = x1 + a1x;
      _fPos[vb * 2 + 5] = y1 + a1y;
      _fPos[vb * 2 + 6] = x1 - a1x;
      _fPos[vb * 2 + 7] = y1 - a1y;
      _fPos[vb * 2 + 8] = x2;
      _fPos[vb * 2 + 9] = y2;

      _fIdx[ib] = vb;
      _fIdx[ib + 1] = vb + 1;
      _fIdx[ib + 2] = vb + 2;
      _fIdx[ib + 3] = vb + 1;
      _fIdx[ib + 4] = vb + 3;
      _fIdx[ib + 5] = vb + 2;
      _fIdx[ib + 6] = vb + 2;
      _fIdx[ib + 7] = vb + 3;
      _fIdx[ib + 8] = vb + 4;
      vb += 5;
      ib += 9;
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_fPos, 0, vb * 2),
      colors: Int32List.sublistView(_fCol, 0, vb),
      indices: Uint16List.sublistView(_fIdx, 0, ib),
    );
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _plain);
    vertices.dispose();
  }

  /// Builds the ribbon and the core in the ball's own space, and their
  /// texture charts. Rebuilt only when the shape changes.
  void _ensureShell(_Geo g, int segs, int rows, int cuN, int cvN) {
    final key = '$segs|$rows|$cuN|$cvN|$_geoTurns|${(_pEff * 1000).round()}';
    if (key == _shellKey) return;
    _shellKey = key;
    _segs = segs;
    _rows = rows;
    _cuN = cuN;
    _cvN = cvN;
    final cols = segs + 1;
    final nRib = cols * (rows + 1);
    _ux = Float64List(nRib);
    _uy = Float64List(nRib);
    _uz = Float64List(nRib);
    const scale = _pebbleN / _cell;
    for (var j = 0; j <= rows; j++) {
      final v = j / rows * 2 - 1;
      for (var i = 0; i <= segs; i++) {
        final a = _pEff * i / segs;
        final th = a * g.thetaMax;
        final bw = _bandW(g, a);
        final ph = g.phiBot + g.rate * th + v * bw;
        final cph = math.cos(ph);
        final k = j * cols + i;
        _ux[k] = cph * math.sin(th);
        _uy[k] = math.sin(ph);
        _uz[k] = cph * math.cos(th);
        // Pebble chart: arc length along the ribbon by arc length across it.
        final phc = g.phiBot + g.rate * th;
        final along =
            (math.sin(phc) - math.sin(g.phiBot)) / math.max(g.rate, 1e-4);
        _iTex[k * 2] = along * scale;
        _iTex[k * 2 + 1] = v * bw * scale;
      }
    }
    final cols2 = cuN + 1;
    final nCore = cols2 * (cvN + 1);
    _cux = Float64List(nCore);
    _cuy = Float64List(nCore);
    _cuz = Float64List(nCore);
    for (var j = 0; j <= cvN; j++) {
      final lat = (j / cvN - 0.5) * math.pi;
      for (var i = 0; i <= cuN; i++) {
        final u = i / cuN;
        final k = j * cols2 + i;
        _cux[k] = math.cos(lat) * math.sin(u * _tau);
        _cuy[k] = math.sin(lat);
        _cuz[k] = math.cos(lat) * math.cos(u * _tau);
        final o = nRib + k;
        _iTex[o * 2] = u * _coreTiles * _pebbleN;
        _iTex[o * 2 + 1] = lat * _coreR / _cell * _pebbleN;
      }
    }
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
      children: <Widget>[
        host,
        Center(child: inside),
      ],
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

double _fract(double x) => x - x.floorToDouble();

int _byte(double v) {
  if (v <= 0) return 0;
  if (v >= 1) return 255;
  return (v * 255).round();
}

int _pack(double r, double g, double b, int a8) {
  return (a8 << 24) | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);
}

/// Which side of the first triangle a face is on, in screen space.
double _cross(Float32List pos, int a, int b, int c) {
  final ax = pos[a * 2];
  final ay = pos[a * 2 + 1];
  return (pos[b * 2] - ax) * (pos[c * 2 + 1] - ay) -
      (pos[b * 2 + 1] - ay) * (pos[c * 2] - ax);
}

// ─── The ribbon model ────────────────────────────────────────────────────────

/// Band b's centre line climbs [rate] radians of latitude per radian of
/// azimuth; across it runs from -1 to 1, and its width eases to [taper] at
/// the two ends.
class _Geo {
  const _Geo(this.thetaMax, this.rate, this.phiBot, this.hw, this.taper);

  final double thetaMax;
  final double rate;
  final double phiBot;
  final double hw;
  final double taper;
}

/// Turns counts the ribbon crossings down the front, the part-crossings at
/// the capped ends included.
_Geo _geometry(double turns) {
  const gap = 0.34;
  const pole = 84 * _deg;
  const taper = 0.8;
  final pitch = 2 * pole / math.max(turns - 0.25 - gap, 0.5);
  final hw = 0.5 * pitch * (1 - gap);
  final span = pitch * math.max(turns - 1.25, 0.25);
  final rate = pitch / _tau;
  return _Geo(span / rate, rate, -pole + hw, hw, taper);
}

double _bandW(_Geo g, double a) {
  final e = _smooth(0, 0.16, a) * _smooth(0, 0.16, 1 - a);
  return g.hw * (g.taper + (1 - g.taper) * e);
}

/// Signed latitude distance from a point on the sphere to the nearest part
/// of the ribbon: positive on it, negative in a gap.
double _bandSD(_Geo g, double pEff, double x, double y, double z) {
  final th = math.atan2(x, z + 1e-6);
  final len = math.sqrt(x * x + y * y + z * z);
  final ph = math.asin(_clamp(y / math.max(len, 1e-4), -1, 1));
  final rate = math.max(g.rate, 1e-4);
  final k0 = (((ph - g.phiBot) / rate - th) / _tau + 0.5).floorToDouble();
  var best = -1e3;
  for (var j = -1; j <= 1; j++) {
    final tp = th + _tau * (k0 + j);
    final a = tp / g.thetaMax;
    final d =
        _bandW(g, _clamp(a, 0, 1)) - (ph - (g.phiBot + g.rate * tp)).abs();
    final over =
        math.max(-a, a - pEff) * g.thetaMax * math.max(math.cos(ph), 0.05);
    best = math.max(best, math.min(d, -over));
  }
  return best;
}

// ─── The coat ────────────────────────────────────────────────────────────────

class _Fur {
  _Fur(this.count, this.data);

  final int count;

  /// Per strand, [_furStride] numbers: root, middle control and tip control
  /// (3 each), then edge, brightness, lip, position along the ribbon.
  final Float32List data;
}

/// Strands in clumps on the ribbon, each one a curved tapered hair, all
/// worked out once in the ball's own space.
_Fur _buildFur(int count, int seed, _Geo g, double furLen) {
  final rand = math.Random(seed * 9973 + 17);
  final data = Float32List(math.max(count, 1) * _furStride);
  var k = 0;
  var guard = 0;
  while (k < count && guard < count * 20) {
    guard++;
    final a = rand.nextDouble();
    // An eighth of the clumps sit on the upper lips: that dense, splayed
    // fringe is the bright rim along every gap.
    final v = rand.nextDouble() < 0.125
        ? 0.8 + 0.2 * rand.nextDouble()
        : rand.nextDouble() * 2 - 1;
    final e = _smooth(0, 0.16, a) * _smooth(0, 0.16, 1 - a);
    final width = g.taper + (1 - g.taper) * e;
    final ph = g.phiBot + g.rate * a * g.thetaMax + v * g.hw * width;
    final cph = math.cos(ph);
    if (rand.nextDouble() > cph * width) continue;
    final lx = rand.nextDouble();
    final ly = rand.nextDouble();
    final ln = rand.nextDouble();
    for (var m = 0; m < _clumpSize && k < count; m++) {
      final ang = rand.nextDouble() * _tau;
      final rr = _clumpR * math.sqrt(rand.nextDouble());
      final ox = math.cos(ang) * rr;
      final oy = math.sin(ang) * rr;
      final aa = _clamp(a + ox / (g.thetaMax * math.max(cph, 0.1)), 0, 1);
      final vv = _clamp(v + oy / (g.hw * width), -1, 1);
      final bright = rand.nextDouble() * 0.499;
      _strand(
        data,
        k * _furStride,
        g,
        furLen,
        aa,
        vv,
        bright * 2,
        -ox,
        -oy,
        _clamp(lx + (rand.nextDouble() - 0.5) * 0.3, 0, 1),
        _clamp(ly + (rand.nextDouble() - 0.5) * 0.3, 0, 1),
        _clamp(ln + (rand.nextDouble() - 0.5) * 0.4, 0, 1),
      );
      k++;
    }
  }
  return _Fur(k, data);
}

/// One strand: leaves the skin near the normal, then lies over along the
/// comb; strands in a clump share one lean and their tips gather together.
void _strand(
  Float32List data,
  int o,
  _Geo g,
  double furLen,
  double a,
  double v,
  double bright,
  double toE,
  double toN,
  double lx,
  double ly,
  double ln,
) {
  final th0 = a * g.thetaMax;
  final ph0 = g.phiBot + g.rate * th0 + v * _bandW(g, a);
  final cph0 = math.cos(ph0);
  final nx = cph0 * math.sin(th0);
  final ny = math.sin(ph0);
  final nz = cph0 * math.cos(th0);
  final edge = _smooth(0.62, 1.0, v.abs());

  // East and north on the skin.
  final th = math.atan2(nx, nz + 1e-6);
  final t1x = math.cos(th);
  final t1z = -math.sin(th);
  final t2x = ny * t1z;
  final t2y = nz * t1x - nx * t1z;
  final t2z = -ny * t1x;

  // Each clump's flow turns in the skin's plane, but never down over a
  // lower lip, or the gap closes. A few clumps bristle up.
  var ang = (ly * 2 - 1) * _strandTilt * 1.3;
  const bristle = 0.0;
  final south = 1 - _smooth(-0.9, -0.4, v);
  ang = ang + (math.max(ang, -0.12) - ang) * south;

  // The flow follows the ribbon as it climbs.
  final ca = math.cos(math.asin(_clamp(ny, -1, 1)));
  var alx = ca * t1x + g.rate * t2x;
  var aly = g.rate * t2y;
  var alz = ca * t1z + g.rate * t2z;
  final all = math.max(math.sqrt(alx * alx + aly * aly + alz * alz), 1e-6);
  alx /= all;
  aly /= all;
  alz /= all;
  final acx = ny * alz - nz * aly;
  final acy = nz * alx - nx * alz;
  final acz = nx * aly - ny * alx;
  final flx = math.cos(ang) * alx + math.sin(ang) * acx;
  final fly = math.cos(ang) * aly + math.sin(ang) * acy;
  final flz = math.cos(ang) * alz + math.sin(ang) * acz;

  final jit = (lx * 2 - 1) * _strandTilt;
  var len =
      furLen * (1 - 0.5 * _lenJitter + _lenJitter * ln) * (1 - 0.3 * edge);
  final splay = v > 0 ? _splay : -0.25 * _splay;
  final k0 = 0.75 + 0.3 * jit + bristle;
  var d0x = nx * k0 + 0.9 * _comb * flx;
  var d0y = ny * k0 + 0.9 * _comb * fly;
  var d0z = nz * k0 + 0.9 * _comb * flz;
  final d0l = math.max(math.sqrt(d0x * d0x + d0y * d0y + d0z * d0z), 1e-6);
  d0x /= d0l;
  d0y /= d0l;
  d0z /= d0l;
  final k1 = _hairLift + 0.25 * jit + 0.6 * bristle;
  var d1x = nx * k1 + _comb * flx + edge * splay * t2x;
  var d1y = ny * k1 + _comb * fly + edge * splay * t2y;
  var d1z = nz * k1 + _comb * flz + edge * splay * t2z;
  len *= 1 - 0.35 * bristle;

  // Curl: the tip half bends on round to one side.
  final curl = (_fract(lx * 5.31 + ly * 2.17) * 2 - 1) * 0.35;
  d1x += curl * acx;
  d1y += curl * acy;
  d1z += curl * acz;
  final d1l = math.max(math.sqrt(d1x * d1x + d1y * d1y + d1z * d1z), 1e-6);
  d1x /= d1l;
  d1y /= d1l;
  d1z /= d1l;

  final r0x = nx * 0.995;
  final r0y = ny * 0.995;
  final r0z = nz * 0.995;
  final c1x = r0x + d0x * len * 0.4;
  final c1y = r0y + d0y * len * 0.4;
  final c1z = r0z + d0z * len * 0.4;
  final tcx = t1x * toE + t2x * toN;
  final tcy = t2y * toN;
  final tcz = t1z * toE + t2z * toN;
  final e1x = c1x + d1x * len * 0.7 + tcx * _clumpPull;
  final e1y = c1y + d1y * len * 0.7 + tcy * _clumpPull;
  final e1z = c1z + d1z * len * 0.7 + tcz * _clumpPull;

  data[o] = r0x;
  data[o + 1] = r0y;
  data[o + 2] = r0z;
  data[o + 3] = c1x;
  data[o + 4] = c1y;
  data[o + 5] = c1z;
  data[o + 6] = e1x;
  data[o + 7] = e1y;
  data[o + 8] = e1z;
  data[o + 9] = edge;
  data[o + 10] = bright;
  data[o + 11] = v > 0 ? edge : 0.0;
  data[o + 12] = a;
}

// ─── The pebbles ─────────────────────────────────────────────────────────────

Future<ui.Image>? _pebbleFuture;

/// Tileable pebbles: rounded domes with a crease where neighbours meet,
/// as a brightness map. Light and dark together read as a pebbled surface.
Future<ui.Image> _makePebble() {
  const n = _pebbleN;
  const c = 16;
  const cell = n / c;
  final rand = math.Random(911);
  final px = Float64List(c * c);
  final py = Float64List(c * c);
  for (var j = 0; j < c; j++) {
    for (var i = 0; i < c; i++) {
      px[j * c + i] = (i + 0.15 + 0.7 * rand.nextDouble()) * cell;
      py[j * c + i] = (j + 0.15 + 0.7 * rand.nextDouble()) * cell;
    }
  }
  const speckle = 0.6;
  const low = 1 - speckle * 0.85;
  const high = 1 + speckle * 0.35;
  final pixels = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final ci = x ~/ cell;
      final cj = y ~/ cell;
      var f1 = 1e9;
      var f2 = 1e9;
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          final ii = (ci + di + c) % c;
          final jj = (cj + dj + c) % c;
          final qx = px[jj * c + ii] + (ci + di - ii) * cell;
          final qy = py[jj * c + ii] + (cj + dj - jj) * cell;
          final dx = x + 0.5 - qx;
          final dy = y + 0.5 - qy;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < f1) {
            f2 = f1;
            f1 = d;
          } else if (d < f2) {
            f2 = d;
          }
        }
      }
      final t = f1 / (cell * 0.75);
      final dome = math.sqrt(_clamp(1 - t * t, 0, 1));
      final h = dome * _smooth(0, cell * 0.22, f2 - f1);
      final g = _byte((low + (high - low) * h) / high);
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
