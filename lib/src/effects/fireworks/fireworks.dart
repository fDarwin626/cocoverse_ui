import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const double _tau = math.pi * 2;

// The world: x to the right, z into the scene, y up. Rockets climb to an
// apex between these heights and burst.
const double _fieldHalf = 1.5;
const double _apexLo = 0.7;
const double _apexHi = 1.6;
const double _camDist = 3.4;
const double _gravity = 0.55 * 2.2;
const double _rainbowSat = 0.9 * 0.9 + 0.1;

// Sparks alive at once, and rockets in the air at once.
const int _cap = 5000;
const int _maxRockets = 40;

// Share of the spark count each quality draws: low, medium, high.
const List<double> _sparkShare = <double>[0.45, 0.7, 1.0];

const List<Color> _defaultColors = <Color>[
  Color(0xFFFFD166),
  Color(0xFFFF4D6D),
  Color(0xFF4CC9F0),
  Color(0xFFB15CFF),
  Color(0xFFFF0000),
  Color(0xFF007FFF),
  Color(0xFFC1FF00),
];

const TextStyle _titleBase = TextStyle(
  color: Color(0xFFFFFFFF),
  fontSize: 40,
  fontWeight: FontWeight.w800,
  height: 1.1,
  letterSpacing: -0.5,
  decoration: TextDecoration.none,
);

const TextStyle _subtitleBase = TextStyle(
  color: Color(0xCCFFFFFF),
  fontSize: 17,
  fontWeight: FontWeight.w500,
  height: 1.3,
  decoration: TextDecoration.none,
);

/// How a line of text arrives.
enum FireworksTextAnimation {
  /// Fades in.
  fade,

  /// Rises a little while fading in.
  rise,

  /// Grows in with a small overshoot.
  pop,

  /// Starts blurred and softly comes into focus.
  blur,

  /// Types out one character at a time.
  typewriter,

  /// Each letter rises in just after the one before it.
  letters,

  /// Starts widely spaced and draws together.
  track,
}

/// A firework show that sits on top of whatever is behind it.
///
/// It has no background of its own: only the sparks are drawn, so it works
/// over a plain colour, a gradient, an image or your whole app. It fills the
/// space it is given and ignores touches, so put it in a [Stack] above the
/// screen it celebrates. It does not run on its own: give it a [duration],
/// and optionally a [title] and a [subtitle] that animate in.
///
/// ```dart
/// Stack(
///   children: [
///     const CongratsScreen(),
///     const Positioned.fill(
///       child: Fireworks(
///         duration: Duration(seconds: 5),
///         title: 'Well done!',
///         subtitle: 'Your account is ready',
///       ),
///     ),
///   ],
/// )
/// ```
class Fireworks extends StatefulWidget {
  /// Creates a firework show.
  const Fireworks({
    super.key,
    this.colors = _defaultColors,
    this.duration = const Duration(seconds: 6),
    this.delay = Duration.zero,
    this.loop = false,
    this.rate = 100.0,
    this.sparks = 290,
    this.size = 94.0,
    this.trail = 77.0,
    this.speed = 73.0,
    this.tilt = 45.0,
    this.scale = 100.0,
    this.title,
    this.subtitle,
    this.titleStyle,
    this.subtitleStyle,
    this.titleAnimation = FireworksTextAnimation.blur,
    this.subtitleAnimation = FireworksTextAnimation.rise,
    this.titleDelay = const Duration(milliseconds: 600),
    this.titleDuration = const Duration(milliseconds: 1000),
    this.subtitleDelay,
    this.subtitleDuration = const Duration(milliseconds: 800),
    this.textAlignment = Alignment.center,
    this.textPadding = const EdgeInsets.all(24),
    this.textGap = 10.0,
    this.textAlign = TextAlign.center,
    this.onFinished,
    this.paused = false,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// One colour per burst, picked at random. An empty list gives random
  /// hues.
  final List<Color> colors;

  /// How long new fireworks keep launching. The last bursts finish fading
  /// after this, so the whole show runs a couple of seconds longer.
  final Duration duration;

  /// How long to wait before the first firework launches.
  final Duration delay;

  /// Whether the show starts again when it ends.
  final bool loop;

  /// How often fireworks launch, from 1 to 100. 100 is about four a second.
  final double rate;

  /// Sparks in each burst. Lower qualities draw fewer.
  final int sparks;

  /// How big the bursts and the sparks are, as a percentage.
  final double size;

  /// The length of each spark's streak, from 0 to 100.
  final double trail;

  /// How fast time runs, as a percentage. 100 is the original pace.
  final double speed;

  /// Camera pitch in degrees, from -20 to 85. 0 shows flat rings seen from
  /// the side, about 60 looks down from above.
  final double tilt;

  /// How large the show is on screen, from 30 to 200 percent.
  final double scale;

  /// A line of big text. Null shows none.
  final String? title;

  /// A smaller line under the title. Null shows none.
  final String? subtitle;

  /// Style for the title. Merged over a bold white default, so you only set
  /// what you change. Give it any font: `TextStyle(fontFamily: 'Poppins')`
  /// or a `GoogleFonts` style.
  final TextStyle? titleStyle;

  /// Style for the subtitle, merged over a soft white default.
  final TextStyle? subtitleStyle;

  /// How the title arrives.
  final FireworksTextAnimation titleAnimation;

  /// How the subtitle arrives.
  final FireworksTextAnimation subtitleAnimation;

  /// When the title starts to appear, counted from when the widget appears.
  final Duration titleDelay;

  /// How long the title takes to arrive.
  final Duration titleDuration;

  /// When the subtitle starts to appear. Null means half a second after the
  /// title starts.
  final Duration? subtitleDelay;

  /// How long the subtitle takes to arrive.
  final Duration subtitleDuration;

  /// Where the text sits in the box.
  final Alignment textAlignment;

  /// Space round the text.
  final EdgeInsets textPadding;

  /// Space between the title and the subtitle.
  final double textGap;

  /// How lines of text align when they wrap.
  final TextAlign textAlign;

  /// Called once when the show has ended and the last spark has faded. Use it
  /// to close a sheet or move to the next screen.
  final VoidCallback? onFinished;

  /// Freezes the show and the text when true.
  final bool paused;

  /// Level of detail. Lower settings draw fewer sparks.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] plays the show and the text
  /// again from the start.
  final EffectController? controller;

  /// Screen-reader description of the show. Null marks it as decorative.
  /// The text is always read out.
  final String? semanticLabel;

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _Rocket {
  _Rocket({required this.x, required this.z, required this.vy, required this.rgb});

  final double x;
  final double z;
  double y = 0;
  double vy;
  final int rgb;
}

class _Flash {
  _Flash(this.sx, this.sy, this.rgb);

  final double sx;
  final double sy;
  final int rgb;
  double age = 0;
}

class _FireworksState extends State<Fireworks>
    with SingleTickerProviderStateMixin {
  // The colours come with the mesh, so the paint is plain white. Plus adds
  // the sparks to what is under them, so they glow.
  final Paint _paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = ui.BlendMode.plus;
  final Paint _flashPaint = Paint()..blendMode = ui.BlendMode.plus;

  late final AnimationController _textCtl;
  double _textTotal = 1;

  // The spark pool, written round and round.
  final Float32List _wx = Float32List(_cap);
  final Float32List _wy = Float32List(_cap);
  final Float32List _wz = Float32List(_cap);
  final Float32List _wvx = Float32List(_cap);
  final Float32List _wvy = Float32List(_cap);
  final Float32List _wvz = Float32List(_cap);
  final Float32List _life = Float32List(_cap);
  final Float32List _lifeMax = Float32List(_cap);
  final Int32List _rgb = Int32List(_cap);
  int _cursor = 0;

  final List<_Rocket> _rockets = <_Rocket>[];
  final List<_Flash> _flashes = <_Flash>[];
  final math.Random _rng = math.Random();

  double _clock = 0;
  double _acc = 0;
  double _lastTime = 0;
  bool _started = false;
  bool _finished = false;
  bool _reduced = false;
  int _seenResets = 0;

  // The mesh: one tapering streak (four points) for each spark and rocket.
  final Float32List _pos = Float32List((_cap + _maxRockets) * 8);
  final Int32List _vcol = Int32List((_cap + _maxRockets) * 4);
  final Uint16List _idx = Uint16List((_cap + _maxRockets) * 6);
  int _nv = 0;
  int _ni = 0;

  // The camera for this frame, and the last point projected.
  double _cosA = 1;
  double _sinA = 0;
  double _focal = 1;
  double _cx = 0;
  double _cy = 0;
  double _sx = 0;
  double _sy = 0;
  double _ds = 1;

  bool get _hasText =>
      (widget.title?.isNotEmpty ?? false) ||
      (widget.subtitle?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _textCtl = AnimationController(vsync: this);
    _computeTotals();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
    if (_hasText && !widget.paused) _textCtl.forward(from: 0);
  }

  @override
  void didUpdateWidget(Fireworks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _seenResets = widget.controller?.resetCount ?? 0;
    }
    _computeTotals();
    final hadText = (oldWidget.title?.isNotEmpty ?? false) ||
        (oldWidget.subtitle?.isNotEmpty ?? false);
    if (!hadText && _hasText && !widget.paused) {
      _textCtl.forward(from: 0);
    } else if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        _textCtl.stop();
      } else if (_hasText && _textCtl.value < 1) {
        _textCtl.forward();
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _textCtl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _restart();
    }
  }

  void _restart() {
    _clock = 0;
    _acc = 0;
    _started = false;
    _finished = false;
    _rockets.clear();
    _flashes.clear();
    _life.fillRange(0, _cap, 0.0);
    _cursor = 0;
    if (_hasText) _textCtl.forward(from: 0);
  }

  void _computeTotals() {
    final w = widget;
    var end = 0;
    if (w.title?.isNotEmpty ?? false) {
      end = w.titleDelay.inMilliseconds + w.titleDuration.inMilliseconds;
    }
    if (w.subtitle?.isNotEmpty ?? false) {
      final sd = w.subtitleDelay ??
          (w.titleDelay + const Duration(milliseconds: 500));
      end = math.max(
        end,
        sd.inMilliseconds + w.subtitleDuration.inMilliseconds,
      );
    }
    _textTotal = math.max(0.1, end / 1000);
    _textCtl.duration = Duration(milliseconds: (_textTotal * 1000).round());
  }

  void _notifyFinished() {
    final cb = widget.onFinished;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _notifyFinished();
    if (widget.loop) {
      _clock = widget.delay.inMilliseconds / 1000;
      _acc = 0;
      _started = false;
      _finished = false;
      if (_hasText && !widget.paused) _textCtl.forward(from: 0);
    }
  }

  /// Projects a point of the world to layout pixels. False behind the camera.
  bool _project(double x, double y, double z) {
    final depth = -y * _sinA + z * _cosA + _camDist;
    if (depth <= 0.05) return false;
    final vUp = y * _cosA + z * _sinA;
    final persp = _focal / depth;
    _sx = _cx + x * persp;
    _sy = _cy - vUp * persp;
    _ds = _camDist / depth;
    return true;
  }

  int _pickRgb(List<Color> list) {
    final Color c;
    if (list.isNotEmpty) {
      c = list[_rng.nextInt(list.length)];
    } else {
      c = HSLColor.fromAHSL(1, _rng.nextDouble() * 360, _rainbowSat, 0.6)
          .toColor();
    }
    return (_b(c.r * 255) << 16) | (_b(c.g * 255) << 8) | _b(c.b * 255);
  }

  void _spawnRocket() {
    final apex = _apexLo + _rng.nextDouble() * (_apexHi - _apexLo);
    _rockets.add(
      _Rocket(
        x: (_rng.nextDouble() * 2 - 1) * _fieldHalf,
        z: (_rng.nextDouble() * 2 - 1) * _fieldHalf,
        vy: math.sqrt(2 * _gravity * apex),
        rgb: _pickRgb(widget.colors),
      ),
    );
  }

  void _burst(_Rocket rk, int n, double spread) {
    for (var i = 0; i < n; i++) {
      final u = _rng.nextDouble() * 2 - 1;
      final th = _rng.nextDouble() * _tau;
      final rr = math.sqrt(1 - u * u);
      final spd = spread * (0.45 + _rng.nextDouble() * 0.55);
      final c = _cursor;
      _cursor = (_cursor + 1) % _cap;
      _wx[c] = rk.x;
      _wy[c] = rk.y;
      _wz[c] = rk.z;
      _wvx[c] = rr * math.cos(th) * spd;
      _wvy[c] = u * spd;
      _wvz[c] = rr * math.sin(th) * spd;
      final life = 1.1 + _rng.nextDouble() * 0.9;
      _life[c] = life;
      _lifeMax[c] = life;
      _rgb[c] = rk.rgb;
    }
    if (_project(rk.x, rk.y, rk.z)) _flashes.add(_Flash(_sx, _sy, rk.rgb));
  }

  /// Adds one tapering streak, from a faint tail to a bright head.
  void _streak(
    double hx,
    double hy,
    double tx,
    double ty,
    double width,
    int headCol,
    int tailCol,
  ) {
    var dx = hx - tx;
    var dy = hy - ty;
    var len = math.sqrt(dx * dx + dy * dy);
    if (len < width) {
      if (len < 1e-3) {
        dx = 0;
        dy = 1;
        len = 1;
      }
      tx = hx - dx / len * width;
      ty = hy - dy / len * width;
      dx = hx - tx;
      dy = hy - ty;
      len = width;
    }
    final nx = -dy / len;
    final ny = dx / len;
    final hw = width * 0.5;
    final tw = width * 0.2;
    final i = _nv * 2;
    _pos[i] = tx + nx * tw;
    _pos[i + 1] = ty + ny * tw;
    _pos[i + 2] = tx - nx * tw;
    _pos[i + 3] = ty - ny * tw;
    _pos[i + 4] = hx + nx * hw;
    _pos[i + 5] = hy + ny * hw;
    _pos[i + 6] = hx - nx * hw;
    _pos[i + 7] = hy - ny * hw;
    _vcol[_nv] = tailCol;
    _vcol[_nv + 1] = tailCol;
    _vcol[_nv + 2] = headCol;
    _vcol[_nv + 3] = headCol;
    _idx[_ni] = _nv;
    _idx[_ni + 1] = _nv + 1;
    _idx[_ni + 2] = _nv + 2;
    _idx[_ni + 3] = _nv + 1;
    _idx[_ni + 4] = _nv + 3;
    _idx[_ni + 5] = _nv + 2;
    _nv += 4;
    _ni += 6;
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 4 || size.height < 4) return;
    final w = widget;
    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    if (w.paused) dt = 0;

    // With reduced motion there is no show. The text still appears.
    if (_reduced) {
      if (!_finished) {
        _finished = true;
        _notifyFinished();
      }
      return;
    }

    final tier = _tier(w.quality);
    final sdt = dt * _clamp(w.speed, 0, 300) / 100;
    final startAt = w.delay.inMilliseconds / 1000;
    final endAt = startAt + w.duration.inMilliseconds / 1000;
    _clock += dt;
    final launching = _clock >= startAt && _clock < endAt;

    // The camera.
    final pitch = _clamp(w.tilt, -20, 85) * math.pi / 180;
    _cosA = math.cos(pitch);
    _sinA = math.sin(pitch);
    final shortSide = math.min(size.width, size.height);
    _focal = math.sqrt(size.width * size.height) *
        0.8 *
        _clamp(w.scale, 30, 200) /
        100;
    _cx = size.width / 2;
    _cy = size.height / 2;
    final pxK = _clamp(shortSide / 600, 0.75, 1.5);
    final sizeF = _clamp(w.size, 10, 300) / 100;
    final tau = 0.02 + _clamp(w.trail, 0, 100) / 100 * 0.3;
    final burstN = math.max(20, (w.sparks * _sparkShare[tier]).round());
    final spread = 0.9 * sizeF;

    // Launch rockets while the show is on.
    if (launching) {
      if (!_started) {
        _started = true;
        _spawnRocket();
      }
      _acc += sdt;
      final interval = 1 / (0.2 + _clamp(w.rate, 1, 100) / 100 * 3.8);
      var guard = 0;
      while (_acc >= interval && guard < 8) {
        _acc -= interval;
        if (_rockets.length < _maxRockets) _spawnRocket();
        guard++;
      }
    }

    _nv = 0;
    _ni = 0;

    // Rockets rise, then burst at the top.
    for (var i = _rockets.length - 1; i >= 0; i--) {
      final rk = _rockets[i];
      rk.vy -= _gravity * sdt;
      rk.y += rk.vy * sdt;
      if (rk.vy <= 0 || rk.y <= 0) {
        _burst(rk, burstN, spread);
        _rockets.removeAt(i);
        continue;
      }
      if (!_project(rk.x, rk.y, rk.z)) continue;
      final hx = _sx;
      final hy = _sy;
      final ds = _ds;
      var tx = hx;
      var ty = hy;
      if (_project(rk.x, rk.y - rk.vy * tau, rk.z)) {
        tx = _sx;
        ty = _sy;
      }
      final r = (rk.rgb >> 16) & 255;
      final g = (rk.rgb >> 8) & 255;
      final b = rk.rgb & 255;
      _streak(
        hx,
        hy,
        tx,
        ty,
        _clamp(2.4 * sizeF * ds * pxK, 1.5, 6),
        _pack(255, r + ((255 - r) * 0.5).round(), g + ((255 - g) * 0.5).round(),
            b + ((255 - b) * 0.5).round()),
        _pack(0, r, g, b),
      );
    }

    // Sparks fly out, slow down, fall and fade.
    var alive = 0;
    final drag = math.pow(0.5, sdt).toDouble();
    for (var c = 0; c < _cap; c++) {
      var lf = _life[c];
      if (lf <= 0) continue;
      lf -= sdt;
      if (lf <= 0) {
        _life[c] = 0;
        continue;
      }
      _life[c] = lf;
      alive++;
      _wvy[c] -= _gravity * sdt;
      _wvx[c] *= drag;
      _wvy[c] *= drag;
      _wvz[c] *= drag;
      final x = _wx[c] += _wvx[c] * sdt;
      final y = _wy[c] += _wvy[c] * sdt;
      final z = _wz[c] += _wvz[c] * sdt;
      if (!_project(x, y, z)) continue;
      final hx = _sx;
      final hy = _sy;
      final ds = _ds;
      var tx = hx;
      var ty = hy;
      if (_project(x - _wvx[c] * tau, y - _wvy[c] * tau, z - _wvz[c] * tau)) {
        tx = _sx;
        ty = _sy;
      }
      final bright = lf / _lifeMax[c];
      final a = bright * bright;
      final v = _rgb[c];
      final r = (v >> 16) & 255;
      final g = (v >> 8) & 255;
      final b = v & 255;
      final k = 0.35 * a;
      _streak(
        hx,
        hy,
        tx,
        ty,
        _clamp((0.8 + sizeF) * ds * pxK, 1.0, 5.5),
        _pack((a * 255).round(), r + ((255 - r) * k).round(),
            g + ((255 - g) * k).round(), b + ((255 - b) * k).round()),
        _pack(0, r, g, b),
      );
    }

    // The flash at each burst.
    for (var i = _flashes.length - 1; i >= 0; i--) {
      final f = _flashes[i];
      f.age += sdt;
      if (f.age > 0.5) {
        _flashes.removeAt(i);
        continue;
      }
      final k = 1 - f.age / 0.5;
      final r = shortSide * 0.12 * (0.5 + f.age * 2.5);
      final cr = (f.rgb >> 16) & 255;
      final cg = (f.rgb >> 8) & 255;
      final cb = f.rgb & 255;
      _flashPaint.shader = ui.Gradient.radial(
        Offset(f.sx, f.sy),
        r,
        <Color>[
          Color.fromARGB((0.5 * k * k * 255).round(), cr, cg, cb),
          Color.fromARGB(0, cr, cg, cb),
        ],
      );
      canvas.drawCircle(Offset(f.sx, f.sy), r, _flashPaint);
    }

    if (_ni > 0) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_pos, 0, _nv * 2),
        colors: Int32List.sublistView(_vcol, 0, _nv),
        indices: Uint16List.sublistView(_idx, 0, _ni),
      );
      canvas.drawVertices(vertices, ui.BlendMode.modulate, _paint);
      vertices.dispose();
    }

    // The show is over once nothing is left in the air.
    if (!launching &&
        _clock >= endAt &&
        _rockets.isEmpty &&
        alive == 0 &&
        _flashes.isEmpty) {
      _finish();
    }
  }

  Widget _text() {
    return AnimatedBuilder(
      animation: _textCtl,
      builder: (context, _) {
        final w = widget;
        // With reduced motion the text is simply there.
        final elapsed = _reduced ? 1e9 : _textCtl.value * _textTotal;
        final children = <Widget>[];
        final title = w.title;
        if (title != null && title.isNotEmpty) {
          children.add(
            _animatedLine(
              title,
              _titleBase.merge(w.titleStyle),
              w.titleAnimation,
              _progress(elapsed, w.titleDelay, w.titleDuration),
              w.textAlign,
            ),
          );
        }
        final sub = w.subtitle;
        if (sub != null && sub.isNotEmpty) {
          if (children.isNotEmpty) children.add(SizedBox(height: w.textGap));
          final sd = w.subtitleDelay ??
              (w.titleDelay + const Duration(milliseconds: 500));
          children.add(
            _animatedLine(
              sub,
              _subtitleBase.merge(w.subtitleStyle),
              w.subtitleAnimation,
              _progress(elapsed, sd, w.subtitleDuration),
              w.textAlign,
            ),
          );
        }
        return Align(
          alignment: w.textAlignment,
          child: Padding(
            padding: w.textPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final host = RepaintBoundary(
      child: EffectHost(
        onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
        paused: widget.paused,
        interactive: false,
        rotatesOnDrag: false,
        quality: widget.quality,
        controller: widget.controller,
        background: null,
        semanticLabel: widget.semanticLabel,
      ),
    );

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          host,
          if (_hasText) _text(),
        ],
      ),
    );
  }
}

// ─── Text animations ─────────────────────────────────────────────────────────

double _progress(double elapsed, Duration delay, Duration length) {
  final d = math.max(length.inMilliseconds / 1000, 0.001);
  return _clamp((elapsed - delay.inMilliseconds / 1000) / d, 0, 1);
}

WrapAlignment _wrapAlign(TextAlign a) => switch (a) {
      TextAlign.left || TextAlign.start => WrapAlignment.start,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.center,
    };

/// One line of text at progress [p] from 0 (hidden) to 1 (arrived). The
/// line always takes its full space, so nothing jumps while it arrives.
Widget _animatedLine(
  String text,
  TextStyle style,
  FireworksTextAnimation anim,
  double p,
  TextAlign align,
) {
  final e = Curves.easeOutCubic.transform(p);
  final fs = style.fontSize ?? 16.0;
  switch (anim) {
    case FireworksTextAnimation.fade:
      {
        return Opacity(
          opacity: e,
          child: Text(text, style: style, textAlign: align),
        );
      }
    case FireworksTextAnimation.rise:
      {
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, (1 - e) * fs * 0.8),
            child: Text(text, style: style, textAlign: align),
          ),
        );
      }
    case FireworksTextAnimation.pop:
      {
        final s = Curves.easeOutBack.transform(p);
        return Opacity(
          opacity: _clamp(p * 3, 0, 1),
          child: Transform.scale(
            scale: 0.5 + 0.5 * s,
            child: Text(text, style: style, textAlign: align),
          ),
        );
      }
    case FireworksTextAnimation.blur:
      {
        final sigma = (1 - e) * 14;
        final line = Opacity(
          opacity: e,
          child: Transform.scale(
            scale: 1.08 - 0.08 * e,
            child: Text(text, style: style, textAlign: align),
          ),
        );
        if (sigma < 0.05) return line;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.decal,
          ),
          child: line,
        );
      }
    case FireworksTextAnimation.typewriter:
      {
        final shown = math.min(text.length, math.max(0, (text.length * p).floor()));
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: text.substring(0, shown)),
                TextSpan(
                  text: text.substring(shown),
                  style: const TextStyle(
                    color: Color(0x00000000),
                    shadows: <Shadow>[],
                  ),
                ),
              ],
            ),
            style: style,
            textAlign: align,
          ),
        );
      }
    case FireworksTextAnimation.letters:
      {
        final words = text.split(' ');
        final total = text.replaceAll(' ', '').length;
        var index = 0;
        final wordWidgets = <Widget>[];
        for (final word in words) {
          final letters = <Widget>[];
          for (final ch in word.runes.map(String.fromCharCode)) {
            final local = _clamp((p * (total + 5) - index) / 5, 0, 1);
            final le = Curves.easeOutCubic.transform(local);
            letters.add(
              Opacity(
                opacity: le,
                child: Transform.translate(
                  offset: Offset(0, (1 - le) * fs * 0.6),
                  child: Text(ch, style: style),
                ),
              ),
            );
            index++;
          }
          wordWidgets.add(Row(mainAxisSize: MainAxisSize.min, children: letters));
        }
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: Wrap(
            alignment: _wrapAlign(align),
            runAlignment: _wrapAlign(align),
            spacing: fs * 0.28,
            children: wordWidgets,
          ),
        );
      }
    case FireworksTextAnimation.track:
      {
        return Opacity(
          opacity: e,
          child: Text(
            text,
            textAlign: align,
            style: style.copyWith(
              letterSpacing: (style.letterSpacing ?? 0) + (1 - e) * fs * 0.4,
            ),
          ),
        );
      }
  }
}

// ─── Small helpers ───────────────────────────────────────────────────────────

int _tier(EffectQuality q) => switch (q) {
      EffectQuality.low => 0,
      EffectQuality.medium => 1,
      EffectQuality.high => 2,
    };

double _clamp(double v, double lo, double hi) {
  final safe = v.isFinite ? v : lo;
  return math.min(hi, math.max(lo, safe));
}

int _b(double v) => v.isFinite ? math.min(255, math.max(0, v.round())) : 0;

int _pack(int a, int r, int g, int b) {
  return (math.min(255, math.max(0, a)) << 24) |
      (math.min(255, r) << 16) |
      (math.min(255, g) << 8) |
      math.min(255, b);
}