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

// The composition is the portrait poster. A wider frame shows more of the
// bowls, a taller one shows more rings.
const double _refAspect = 1080 / 1529;

// Focal length over the composition's height, and how far above the centre
// the level horizon sits.
const double _focal = 0.70866;
const double _horizonUp = 0.00418;

// Camera distance from the stack's axis, in the scene's units.
const double _camD = 10;

// Ring slots run from -3 to 13. The waist is slot 5.
const int _slot0 = -3;
const int _waist = 5;

// Rings in play at once. Flow wraps them round.
const int _lanes = 16;

// Tube angles, in degrees, of crest, body, shade, glow, halo, core, depth.
const List<double> _stops = <double>[31, -13, -45, -92, -144, 170, 115];

// A ring's gradient is mirrored about the waist, and flips over this height.
const double _waistBlend = 0.12;

// Samples round a ring's tube in its palette.
const int _palW = 256;

// Rows down an inner wall.
const int _wallRows = 14;

// Most points in one frame's mesh.
const int _maxVerts = 62000;

// Level of detail steps: pieces round a ring, and round its tube.
const List<int> _segN = <int>[24, 40, 64, 96, 128];
const List<int> _segM = <int>[10, 14, 20, 28, 40];

// Ring slots: height, ring radius, tube radius, tilt in degrees, tube height
// over width, and how far the ring's inner wall reaches inside its hole.
// Measured off the poster.
const List<List<double>> _slots = <List<double>>[
  <double>[21.5, 7.3, 3.3, 0, 1, 1],
  <double>[15.5, 5.8, 2.7, 0, 1, 1],
  <double>[10.3, 4.5, 2.1, 0, 1, 1],
  <double>[5.9856, 3.4669, 1.7012, 0, 1, 1],
  <double>[3.3708, 2.7215, 0.5747, 0, 1.02, 2.2],
  <double>[2.1866, 1.7349, 0.6697, -2.1, 0.681, 0],
  <double>[1.3757, 1.3657, 0.3881, -2.0, 1.08, 0],
  <double>[0.502, 0.7709, 0.1823, -10.83, 1.243, 0],
  <double>[-0.1386, 0.6304, 0.0968, 5.04, 1.821, 0],
  <double>[-0.769, 0.997, 0.222, 2.61, 1.297, 0],
  <double>[-1.4823, 1.3348, 0.3021, 5.5, 1.08, 0],
  <double>[-2.5049, 1.8983, 0.446, 1.0, 1.04, 0],
  <double>[-3.6785, 2.7097, 0.5751, 0, 1.02, 2.2],
  <double>[-6.344, 3.4097, 1.5248, 0.19, 1.201, 1],
  <double>[-10.6, 4.45, 2.0, 0, 1.15, 1],
  <double>[-15.8, 5.75, 2.6, 0, 1.1, 1],
  <double>[-21.8, 7.3, 3.2, 0, 1.05, 1],
];

/// How the rings move.
enum HourglassMotion {
  /// The light rolls round each ring and the rings swell, in a slow wave
  /// down the stack.
  breathe,

  /// The rings stream upward through the waist.
  flowUp,

  /// The rings stream downward through the waist.
  flowDown,

  /// Nothing moves. The picture is drawn once and kept.
  still,
}

/// One ring's gradient round its tube, as seven colours.
class HourglassRing {
  /// Creates a ring from all seven colours.
  const HourglassRing({
    required this.crest,
    required this.body,
    required this.shade,
    required this.glow,
    required this.halo,
    required this.core,
    required this.depth,
    this.turn = 0,
  });

  /// Makes a whole ring from one colour. The highlights and shades are
  /// worked out from it.
  factory HourglassRing.fromColor(Color color, {double turn = 0}) {
    final hsl = HSLColor.fromColor(color);
    Color shift(double hue, double saturation, double lightness) {
      return HSLColor.fromAHSL(
        1,
        (hsl.hue + hue) % 360,
        _clamp(saturation, 0, 1),
        _clamp(lightness, 0, 1),
      ).toColor();
    }

    final s = hsl.saturation;
    return HourglassRing(
      crest: shift(0, s * 0.7, 0.82),
      body: color,
      shade: shift(0, s, hsl.lightness * 0.22),
      glow: shift(28, s * 1.15, 0.5),
      halo: shift(28, s * 0.85, 0.86),
      core: shift(-32, s * 0.7, 0.8),
      depth: shift(10, s, hsl.lightness * 0.5),
      turn: turn,
    );
  }

  /// The pale shoulder on the side facing away from the waist.
  final Color crest;

  /// The ring's own colour, at its outer equator.
  final Color body;

  /// The deep band on the shoulder facing the waist.
  final Color shade;

  /// The second light, on the face turned toward the waist.
  final Color glow;

  /// Round the lip of the hole.
  final Color halo;

  /// The inside wall of the hole.
  final Color core;

  /// Deep in the hole.
  final Color depth;

  /// Turns this ring's gradient round its tube, in degrees.
  final double turn;
}

/// The original eleven rings, top of the stack first.
const List<HourglassRing> _poster = <HourglassRing>[
  HourglassRing(crest: Color(0xFFD7B0C8), body: Color(0xFFC991B6), shade: Color(0xFFDDBDD3), glow: Color(0xFF110103), halo: Color(0xFFEFE5E1), core: Color(0xFFEEC185), depth: Color(0xFFA84007), turn: 180),
  HourglassRing(crest: Color(0xFFF3EFE7), body: Color(0xFFF0D0B3), shade: Color(0xFFB23120), glow: Color(0xFFBE0202), halo: Color(0xFFFC4E03), core: Color(0xFFFA7216), depth: Color(0xFF940101), turn: 6),
  HourglassRing(crest: Color(0xFFFC9E02), body: Color(0xFFC12603), shade: Color(0xFF440201), glow: Color(0xFFE92604), halo: Color(0xFFF4A7B5), core: Color(0xFFDDE1DB), depth: Color(0xFFF0C3C8), turn: -180),
  HourglassRing(crest: Color(0xFFDCEEE6), body: Color(0xFFF2CCA7), shade: Color(0xFF1C74F0), glow: Color(0xFF020274), halo: Color(0xFF1E74EF), core: Color(0xFFF6CF9C), depth: Color(0xFFF4D8B0), turn: 18),
  HourglassRing(crest: Color(0xFF06B018), body: Color(0xFF021409), shade: Color(0xFF02190C), glow: Color(0xFF06740F), halo: Color(0xFF6CE390), core: Color(0xFFD7F1E9), depth: Color(0xFFB8EDD6), turn: 6),
  HourglassRing(crest: Color(0xFFEEE4E0), body: Color(0xFFA23909), shade: Color(0xFF7A2406), glow: Color(0xFFE2954A), halo: Color(0xFFEEE4D6), core: Color(0xFFEFE6E6), depth: Color(0xFFF0E2D2), turn: -12),
  HourglassRing(crest: Color(0xFFBC99C5), body: Color(0xFF4954AF), shade: Color(0xFF0A1E64), glow: Color(0xFF0B1F66), halo: Color(0xFFAA96CC), core: Color(0xFFAA96CC), depth: Color(0xFFC4A2C2), turn: 6),
  HourglassRing(crest: Color(0xFFF3EADF), body: Color(0xFFD07257), shade: Color(0xFF960101), glow: Color(0xFFFB5408), halo: Color(0xFFFB660C), core: Color(0xFF9D0202), depth: Color(0xFFC02A10), turn: 15),
  HourglassRing(crest: Color(0xFF0CD8C2), body: Color(0xFF027C3D), shade: Color(0xFF020C05), glow: Color(0xFF02421F), halo: Color(0xFF0ED8A7), core: Color(0xFFDEB4F2), depth: Color(0xFFF3EAEF), turn: 9),
  HourglassRing(crest: Color(0xFFE8DAE0), body: Color(0xFF2E1730), shade: Color(0xFF100001), glow: Color(0xFFA8709A), halo: Color(0xFFE8D2DD), core: Color(0xFFC8C0EF), depth: Color(0xFF7957F6), turn: 3),
  HourglassRing(crest: Color(0xFFC25A14), body: Color(0xFF6A1000), shade: Color(0xFF420201), glow: Color(0xFFEEBE83), halo: Color(0xFFC78EB4), core: Color(0xFF14040B), depth: Color(0xFF1A0612), turn: -9),
];

/// An hourglass of glowing rings: a stack of fat gradient rings pinched to a
/// small ring at the waist and flaring into two great bowls that run off the
/// frame. Made to sit behind your app.
///
/// With no size set it fills the space it is given, running the funnel from
/// top to bottom whatever the width, so on a phone and on a desktop it just
/// fits.
///
/// ```dart
/// Stack(
///   children: [
///     const Positioned.fill(child: Hourglass(focus: 40)),
///     SafeArea(child: YourScreen()),
///   ],
/// )
/// ```
class Hourglass extends StatefulWidget {
  /// Creates an hourglass.
  const Hourglass({
    super.key,
    this.colors,
    this.rings,
    this.background = const Color(0xFF000000),
    this.focus = 100.0,
    this.spacing = 100.0,
    this.flare = 100.0,
    this.thickness = 100.0,
    this.scale = 100.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.angle = 0.0,
    this.tilt = 0.0,
    this.motion = HourglassMotion.flowUp,
    this.speed = 5.0,
    this.entrance = true,
    this.entranceDelay = 0.0,
    this.entranceStagger = 5.0,
    this.paused = false,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// One colour per ring, from the top of the stack down. Each colour becomes
  /// a whole ring, with its highlights and shades worked out from it. Fewer
  /// colours than rings repeat down the stack. If null, the original colours
  /// are used.
  final List<Color>? colors;

  /// Full control: every ring's seven gradient colours. Wins over [colors].
  final List<HourglassRing>? rings;

  /// What is behind the rings. Black by default. Use a clear colour for none.
  final Color background;

  /// How sharp it is, from 0 to 100. 100 is perfectly sharp and is the
  /// default. Lower values blur it more, for sitting behind your content.
  final double focus;

  /// Vertical spread of the stack, from 40 to 200 percent. 100 is the
  /// original.
  final double spacing;

  /// How fast the rings grow away from the waist, from 30 to 160 percent.
  /// Low values turn the hourglass into a column.
  final double flare;

  /// Thickness of every tube, from 30 to 200 percent.
  final double thickness;

  /// Size of the stack in the frame, from 40 to 160 percent. 100 is the
  /// original framing. Below it more rings come into view.
  final double scale;

  /// Moves the stack across the frame, as a percentage of its width, from -50
  /// to 50. Positive is right.
  final double offsetX;

  /// Moves the stack down the frame, as a percentage of its height, from -50
  /// to 50. Positive is down.
  final double offsetY;

  /// Turns the stack in the picture, in degrees, from -180 to 180. Positive
  /// is clockwise.
  final double angle;

  /// Leans the stack about the horizontal axis, in degrees, from -40 to 40.
  final double tilt;

  /// How the rings move.
  final HourglassMotion motion;

  /// Pace of the breathing or the stream, from 0 to 10. 5 is a ring every
  /// 8 seconds in the flow.
  final double speed;

  /// Whether the rings bloom out from the waist when it first appears.
  final bool entrance;

  /// Seconds to wait before the bloom.
  final double entranceDelay;

  /// Gap between one ring and the next as the bloom travels outward, from 0
  /// to 10.
  final double entranceStagger;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings build the rings from fewer pieces.
  final EffectQuality quality;

  /// Optional control. [EffectController.reset] plays the bloom again.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative, which is right
  /// for a background.
  final String? semanticLabel;

  @override
  State<Hourglass> createState() => _HourglassState();
}

class _HourglassState extends State<Hourglass> {
  // The colours come with the mesh, so the paint is plain white and
  // modulate leaves them exactly as they are.
  final Paint _paint = Paint()..color = const Color(0xFFFFFFFF);

  // Clocks.
  double _t = 0;
  double _flow = 0;
  double _entT = 0;
  double _lastTime = 0;
  bool _started = false;
  bool _entOn = false;
  bool _entDone = true;
  bool _reduced = false;
  int _seenResets = 0;

  // Gradients, one row of colours round the tube for each ring.
  List<HourglassRing>? _palRings;
  List<Color>? _palColors;
  List<Uint8List> _rows = <Uint8List>[];
  Float64List _rowTurn = Float64List(0);

  // A still picture is drawn once and kept.
  ui.Picture? _cache;
  Hourglass? _cacheFor;
  Size _cacheSize = Size.zero;

  // The camera for this frame.
  double _vf = 1;
  double _vcx = 0;
  double _vcy = 0;
  double _vc = 1;
  double _vs = 0;
  double _tc = 1;
  double _ts = 0;
  double _pX = 0;
  double _pY = 0;

  // Scratch space, so a frame makes little garbage.
  final Float64List _geo = Float64List(6);
  final Float64List _rgb = Float64List(3);
  final Float64List _laneH = Float64List(_lanes);
  final Float64List _laneR = Float64List(_lanes);
  final Float64List _laneT = Float64List(_lanes);
  final Float64List _laneA = Float64List(_lanes);
  final Float64List _laneTurn = Float64List(_lanes);
  final Float64List _laneUp = Float64List(_lanes);
  final Float64List _laneTilt = Float64List(_lanes);
  final Float64List _laneK = Float64List(_lanes);
  final Float64List _laneWall = Float64List(_lanes);
  final Int32List _laneJ = Int32List(_lanes);
  final Int32List _vLane = Int32List(_lanes);
  final Int32List _vNi = Int32List(_lanes);
  final Int32List _vMi = Int32List(_lanes);
  final Int32List _vWall = Int32List(_lanes);
  final Int32List _rBase = Int32List(_lanes);
  final Int32List _rWBase = Int32List(_lanes);
  final Int32List _tubeCol = Int32List(48);
  final Int32List _wallCol = Int32List(_wallRows + 1);
  final Map<int, _Trig> _trigs = <int, _Trig>{};

  // The mesh.
  final Float32List _pos = Float32List(_maxVerts * 2);
  final Int32List _vcol = Int32List(_maxVerts);
  final Uint16List _idx = Uint16List(_maxVerts * 6);
  final Float64List _itemDepth = Float64List(_lanes * 256);
  final Int32List _itemRef = Int32List(_lanes * 256);
  List<int> _order = <int>[];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
  }

  @override
  void didUpdateWidget(Hourglass oldWidget) {
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
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _t = 0;
      _flow = 0;
      _entT = 0;
      _started = false;
      _cache?.dispose();
      _cache = null;
    }
  }

  _Trig _trigFor(int n) => _trigs.putIfAbsent(n, () => _Trig(n));

  List<HourglassRing> _effectiveRings() {
    final given = widget.rings;
    if (given != null && given.isNotEmpty) return given;
    final colors = widget.colors;
    if (colors != null && colors.isNotEmpty) {
      return <HourglassRing>[
        for (final color in colors) HourglassRing.fromColor(color),
      ];
    }
    return _poster;
  }

  void _ensurePalette() {
    final rings = widget.rings;
    final colors = widget.colors;
    if (_rows.isNotEmpty &&
        identical(rings, _palRings) &&
        identical(colors, _palColors)) {
      return;
    }
    _palRings = rings;
    _palColors = colors;
    final list = _effectiveRings();
    final n = math.min(64, list.length);
    _rows = <Uint8List>[for (var i = 0; i < n; i++) _buildRow(list[i])];
    _rowTurn = Float64List(n);
    for (var i = 0; i < n; i++) {
      _rowTurn[i] = list[i].turn * _deg;
    }
    _cache?.dispose();
    _cache = null;
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.width < 2 || size.height < 2) return;
    final w = widget;

    var dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.1) dt = 0.1;

    if (!_started) {
      _started = true;
      _entOn = w.entrance && !_reduced;
      _entDone = !_entOn;
      _entT = 0;
    }
    final animate = !w.paused && !_reduced;
    if (!animate) dt = 0;

    final speed = animate ? _clamp(w.speed, 0, 10) : 0.0;
    final rate = speed > 0 ? math.pow(2, (speed - 5) / 2.5).toDouble() : 0.0;
    _t += dt;
    if (_entOn && !_entDone) _entT += dt;
    if (w.motion == HourglassMotion.flowUp) {
      _flow += dt * 0.12 * rate;
    } else if (w.motion == HourglassMotion.flowDown) {
      _flow -= dt * 0.12 * rate;
    }
    if (_flow > 1e4 || _flow < -1e4) _flow = 0;
    final breath = w.motion == HourglassMotion.breathe ? rate : 0.0;

    final isStatic = _entDone &&
        (!animate || w.motion == HourglassMotion.still || rate <= 0);

    final focus = _clamp(w.focus, 0, 100);
    final blur01 = (100 - focus) / 100;
    final sigma = focus >= 99.5
        ? 0.0
        : math.pow(blur01, 1.4).toDouble() *
            0.07 *
            math.min(size.width, size.height);

    if (sigma > 0.3) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      _content(canvas, size, breath, blur01, isStatic);
      canvas.restore();
    } else {
      _content(canvas, size, breath, blur01, isStatic);
    }
  }

  void _content(
    Canvas canvas,
    Size size,
    double breath,
    double blur01,
    bool isStatic,
  ) {
    if (!isStatic) {
      _cache?.dispose();
      _cache = null;
      _draw(canvas, size, breath, blur01);
      return;
    }
    final cached = _cache;
    if (cached != null && identical(_cacheFor, widget) && _cacheSize == size) {
      canvas.drawPicture(cached);
      return;
    }
    final recorder = ui.PictureRecorder();
    _draw(Canvas(recorder), size, breath, blur01);
    final picture = recorder.endRecording();
    _cache?.dispose();
    _cache = picture;
    _cacheFor = widget;
    _cacheSize = size;
    canvas.drawPicture(picture);
  }

  /// Projects a point of the stack to layout pixels. False behind the camera.
  bool _proj(double x, double y, double z) {
    final wy = _tc * y - _ts * z;
    final wz = _ts * y + _tc * z;
    final d = _camD - wz;
    if (d < 0.05) return false;
    final u = _vf * x / d;
    final v = _vf * wy / d;
    _pX = _vcx + _vc * u + _vs * v;
    _pY = _vcy + _vs * u - _vc * v;
    return true;
  }

  void _draw(Canvas canvas, Size size, double breath, double blur01) {
    final w = widget;
    _ensurePalette();
    final rows = _rows;
    final nRows = rows.length;
    if (nRows == 0) return;

    // The camera: the portrait composition fitted to the frame, top to
    // bottom, then zoomed, moved and turned.
    final cssW = size.width;
    final cssH = size.height;
    final s0 = math.min(cssH, cssW / _refAspect);
    final zoom = _clamp(w.scale, 40, 160) / 100;
    final angle = _clamp(w.angle, -180, 180) * _deg;
    _vf = _focal * s0 * zoom;
    _vc = math.cos(angle);
    _vs = math.sin(angle);
    final hz = _horizonUp * s0 * zoom;
    _vcx = cssW / 2 + _clamp(w.offsetX, -50, 50) / 100 * cssW + _vs * hz;
    _vcy = cssH / 2 + _clamp(w.offsetY, -50, 50) / 100 * cssH - _vc * hz;
    final tip = -_clamp(w.tilt, -40, 40) * _deg;
    _tc = math.cos(tip);
    _ts = math.sin(tip);

    // The rings in play.
    final spacing = _clamp(w.spacing, 40, 200) / 100;
    final flare = _clamp(w.flare, 30, 160) / 100;
    final thick = _clamp(w.thickness, 30, 200) / 100;
    final base = _flow.floor();
    final rWaist = _slots[_waist - _slot0][1];
    const breathRoll = 12 * _deg;
    const breathSwell = 0.02;
    const wave = 32 * _deg;
    final om = _tau / 6 * breath;
    final stagger = _clamp(w.entranceStagger, 0, 10) * 0.025;
    const entDur = 1.1;
    final entDelay = math.max(0.0, w.entranceDelay);
    var allIn = true;

    for (var i = 0; i < _lanes; i++) {
      final j = base + _slot0 + i;
      final s = j - _flow;
      _slotGeom(s, _geo);
      final h = _geo[0] * spacing;
      var rad = _geo[1];
      var tube = _geo[2];
      final k = math.pow(rad / rWaist, flare - 1).toDouble();
      rad *= k;
      tube *= k * thick;
      var turn = 0.0;
      var alpha = _smooth(-3, -2.3, s) * (1 - _smooth(12.3, 13, s));

      // Breathing: the light rolls round each tube and the rings swell, in a
      // wave down the stack.
      final ph = om * _t - wave * s;
      var grow = 1.0;
      if (breath > 0) {
        grow += breathSwell * math.sin(ph + 1.2);
        turn += breathRoll * math.sin(ph);
      }

      // The bloom, out from the waist, with a little overshoot.
      if (_entOn && !_entDone) {
        final e = _clamp(
          (_entT - entDelay - stagger * (s - _waist).abs()) / entDur,
          0,
          1,
        );
        if (e < 1) allIn = false;
        final b = e - 1;
        final ee = e <= 0 ? 0.0 : 1 + 2.2 * b * b * b + 1.2 * b * b;
        grow *= math.max(ee, 0.001);
        if (e <= 0) alpha = 0;
        turn -= (1 - math.min(1.0, ee)) * 1.6;
      }

      rad *= grow;
      tube *= grow;
      // Keep a hole, and keep the camera outside every ring.
      tube = math.min(tube, rad * 0.92);
      if (rad + tube > _camD * 0.9) {
        final f = _camD * 0.9 / (rad + tube);
        rad *= f;
        tube *= f;
      }

      final row = ((j % nRows) + nRows) % nRows;
      _laneJ[i] = j;
      _laneH[i] = h;
      _laneR[i] = rad;
      _laneT[i] = tube;
      _laneA[i] = alpha;
      _laneTurn[i] = turn + _rowTurn[row];
      _laneUp[i] = _smooth(-_waistBlend, _waistBlend, _geo[0]);
      _laneTilt[i] = _geo[3] * _deg;
      _laneK[i] = _geo[4];
      _laneWall[i] = _geo[5];
    }
    if (_entOn && !_entDone && allIn && _entT > entDelay) _entDone = true;

    // Which rings are on screen, and how finely each needs to be built.
    final tol = switch (w.quality) {
          EffectQuality.low => 2.5,
          EffectQuality.medium => 1.2,
          EffectQuality.high => 0.6,
        } *
        (1 + 5 * blur01);
    final margin = 40 + blur01 * 0.2 * math.min(cssW, cssH);
    var nv = 0;
    for (var i = 0; i < _lanes; i++) {
      if (_laneA[i] <= 0.002) continue;
      final h = _laneH[i];
      final rad = _laneR[i];
      final tube = _laneT[i];
      final kk = _laneK[i];
      final ct = math.cos(_laneTilt[i]);
      final st = math.sin(_laneTilt[i]);
      final ro = rad + tube;
      final rr = tube * kk;
      var x0 = double.infinity;
      var y0 = double.infinity;
      var x1 = -double.infinity;
      var y1 = -double.infinity;
      var behind = false;
      for (var c = 0; c < 8 && !behind; c++) {
        final x = (c & 1) != 0 ? ro : -ro;
        final yl = (c & 2) != 0 ? rr : -rr;
        final zl = (c & 4) != 0 ? ro : -ro;
        if (!_proj(x, h + ct * yl - st * zl, st * yl + ct * zl)) {
          behind = true;
        } else {
          x0 = math.min(x0, _pX);
          x1 = math.max(x1, _pX);
          y0 = math.min(y0, _pY);
          y1 = math.max(y1, _pY);
        }
      }
      if (behind) continue;
      if (x1 < -margin || y1 < -margin || x0 > cssW + margin || y0 > cssH + margin) {
        continue;
      }
      final near = math.max(0.3, _camD - ro);
      final ringPx = _vf * ro / near;
      final tubePx = _vf * tube * math.max(1.0, kk) / near;
      _vLane[nv] = i;
      _vNi[nv] = _level(_segN, math.pi * math.sqrt(ringPx / (2 * tol)));
      _vMi[nv] = _level(_segM, math.pi * math.sqrt(tubePx / (2 * tol)));
      _vWall[nv] = (_laneWall[i] > 0 && _laneA[i] >= 0.999 && rad > tube) ? 1 : 0;
      nv++;
    }
    if (nv == 0) return;

    // Stay inside the mesh budget by building the biggest rings less finely.
    while (true) {
      var total = 0;
      var worst = -1;
      var most = 0;
      for (var q = 0; q < nv; q++) {
        final n = _segN[_vNi[q]];
        final m = _segM[_vMi[q]];
        final c = n * m + (_vWall[q] == 1 ? n * (_wallRows + 1) : 0);
        total += c;
        if (c > most && (_vNi[q] > 0 || _vMi[q] > 0)) {
          most = c;
          worst = q;
        }
      }
      if (total <= _maxVerts || worst < 0) break;
      if (_vNi[worst] > 0 && (_vNi[worst] >= _vMi[worst] || _vMi[worst] == 0)) {
        _vNi[worst]--;
      } else {
        _vMi[worst]--;
      }
    }

    // Build every ring: its points on screen and its colours.
    var cursor = 0;
    var items = 0;
    for (var q = 0; q < nv; q++) {
      final lane = _vLane[q];
      final n = _segN[_vNi[q]];
      final m = _segM[_vMi[q]];
      final tn = _trigFor(n);
      final tm = _trigFor(m);
      final h = _laneH[lane];
      final rad = _laneR[lane];
      final tube = _laneT[lane];
      final kk = _laneK[lane];
      final ct = math.cos(_laneTilt[lane]);
      final st = math.sin(_laneTilt[lane]);
      final alpha8 = (_clamp(_laneA[lane], 0, 1) * 255).round();
      final row = rows[((_laneJ[lane] % nRows) + nRows) % nRows];
      final rk = tube * kk;
      _tubeColors(row, _laneUp[lane], _laneTurn[lane], kk, tm, m, alpha8);

      _rBase[q] = cursor;
      for (var i = 0; i < n; i++) {
        final cth = tn.cos[i];
        final sth = tn.sin[i];
        for (var j = 0; j < m; j++) {
          final rho = rad + tube * tm.cos[j];
          final ly = rk * tm.sin[j];
          final lx = rho * cth;
          final lz = rho * sth;
          final sy = h + ct * ly - st * lz;
          final sz = st * ly + ct * lz;
          final wy = _tc * sy - _ts * sz;
          final wz = _ts * sy + _tc * sz;
          var d = _camD - wz;
          if (d < 0.2) d = 0.2;
          final u = _vf * lx / d;
          final v = _vf * wy / d;
          _pos[cursor * 2] = _vcx + _vc * u + _vs * v;
          _pos[cursor * 2 + 1] = _vcy + _vs * u - _vc * v;
          _vcol[cursor] = _tubeCol[j];
          cursor++;
        }
      }

      // The inner wall: a band inside the hole that fills it with the ring's
      // own colour where a round tube would let you see past it.
      if (_vWall[q] == 1) {
        _rWBase[q] = cursor;
        final ri = rad - tube;
        final hk = rk * _laneWall[lane];
        _wallColors(row, _laneUp[lane], _laneTurn[lane], kk, alpha8);
        for (var i = 0; i < n; i++) {
          final lx = ri * tn.cos[i];
          final lz = ri * tn.sin[i];
          for (var rw = 0; rw <= _wallRows; rw++) {
            final ly = hk * (-1 + 2 * rw / _wallRows);
            final sy = h + ct * ly - st * lz;
            final sz = st * ly + ct * lz;
            final wy = _tc * sy - _ts * sz;
            final wz = _ts * sy + _tc * sz;
            var d = _camD - wz;
            if (d < 0.2) d = 0.2;
            final u = _vf * lx / d;
            final v = _vf * wy / d;
            _pos[cursor * 2] = _vcx + _vc * u + _vs * v;
            _pos[cursor * 2 + 1] = _vcy + _vs * u - _vc * v;
            _vcol[cursor] = _wallCol[rw];
            cursor++;
          }
        }
      }

      // One item per piece round the ring, for ordering.
      for (var i = 0; i < n; i++) {
        final lzc = rad * tn.sin[i];
        final sy = h - st * lzc;
        final sz = ct * lzc;
        final depth = _camD - (_ts * sy + _tc * sz);
        _itemDepth[items] = depth;
        _itemRef[items] = (q << 10) | i;
        items++;
        if (_vWall[q] == 1) {
          // Just behind the tube, so the tube is drawn over its own wall.
          _itemDepth[items] = depth + 0.01;
          _itemRef[items] = (q << 10) | 512 | i;
          items++;
        }
      }
    }

    // Back to front, so nearer pieces cover farther ones.
    if (_order.length != items) {
      _order = List<int>.generate(items, (i) => i);
    }
    _order.sort((a, b) => _itemDepth[b].compareTo(_itemDepth[a]));

    // Only the faces turned toward the viewer are drawn.
    var used = 0;
    for (var o = 0; o < items; o++) {
      final ref = _itemRef[_order[o]];
      final q = ref >> 10;
      final isWall = (ref & 512) != 0;
      final i = ref & 511;
      final n = _segN[_vNi[q]];
      final i1 = i + 1 == n ? 0 : i + 1;
      if (!isWall) {
        final m = _segM[_vMi[q]];
        final b0 = _rBase[q] + i * m;
        final b1 = _rBase[q] + i1 * m;
        for (var j = 0; j < m; j++) {
          final j1 = j + 1 == m ? 0 : j + 1;
          final a = b0 + j;
          final b = b1 + j;
          final c = b0 + j1;
          final d = b1 + j1;
          final ax = _pos[a * 2];
          final ay = _pos[a * 2 + 1];
          final cross = (_pos[b * 2] - ax) * (_pos[c * 2 + 1] - ay) -
              (_pos[b * 2 + 1] - ay) * (_pos[c * 2] - ax);
          if (cross <= 0) continue;
          _idx[used] = a;
          _idx[used + 1] = b;
          _idx[used + 2] = c;
          _idx[used + 3] = b;
          _idx[used + 4] = d;
          _idx[used + 5] = c;
          used += 6;
        }
      } else {
        const per = _wallRows + 1;
        final b0 = _rWBase[q] + i * per;
        final b1 = _rWBase[q] + i1 * per;
        for (var rw = 0; rw < _wallRows; rw++) {
          final a = b0 + rw;
          final b = b1 + rw;
          final c = b0 + rw + 1;
          final d = b1 + rw + 1;
          final ax = _pos[a * 2];
          final ay = _pos[a * 2 + 1];
          final cross = (_pos[b * 2] - ax) * (_pos[c * 2 + 1] - ay) -
              (_pos[b * 2 + 1] - ay) * (_pos[c * 2] - ax);
          if (cross >= 0) continue;
          _idx[used] = a;
          _idx[used + 1] = b;
          _idx[used + 2] = c;
          _idx[used + 3] = b;
          _idx[used + 4] = d;
          _idx[used + 5] = c;
          used += 6;
        }
      }
    }
    if (used == 0) return;

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, 0, cursor * 2),
      colors: Int32List.sublistView(_vcol, 0, cursor),
      indices: Uint16List.sublistView(_idx, 0, used),
    );
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _paint);
    vertices.dispose();
  }

  /// The colour all the way round one ring's tube.
  void _tubeColors(
    Uint8List row,
    double up,
    double turn,
    double aspect,
    _Trig tm,
    int m,
    int alpha8,
  ) {
    final tu = -turn / _tau + 0.5;
    for (var j = 0; j < m; j++) {
      final phi = math.atan2(tm.sin[j] / aspect, tm.cos[j]);
      _tubeCol[j] = _mixColor(row, phi, tu, up, alpha8);
    }
  }

  /// The colour down a ring's inner wall, the same as its tube at that height.
  void _wallColors(
    Uint8List row,
    double up,
    double turn,
    double aspect,
    int alpha8,
  ) {
    final tu = -turn / _tau + 0.5;
    for (var rw = 0; rw <= _wallRows; rw++) {
      final u = -1 + 2 * rw / _wallRows;
      final phi = math.atan2(u / aspect, -math.sqrt(math.max(0.0, 1 - u * u)));
      _wallCol[rw] = _mixColor(row, phi, tu, up, alpha8);
    }
  }

  /// A ring's colour at a tube angle. The gradient is mirrored about the
  /// waist: positive angles point away from it. Near the waist the two
  /// mirrors are blended.
  int _mixColor(Uint8List row, double phi, double tu, double up, int alpha8) {
    double r;
    double g;
    double b;
    if (up >= 1) {
      _lookup(row, phi / _tau + tu, _rgb);
      r = _rgb[0];
      g = _rgb[1];
      b = _rgb[2];
    } else if (up <= 0) {
      _lookup(row, -phi / _tau + tu, _rgb);
      r = _rgb[0];
      g = _rgb[1];
      b = _rgb[2];
    } else {
      _lookup(row, -phi / _tau + tu, _rgb);
      final dr = _rgb[0];
      final dg = _rgb[1];
      final db = _rgb[2];
      _lookup(row, phi / _tau + tu, _rgb);
      r = dr + (_rgb[0] - dr) * up;
      g = dg + (_rgb[1] - dg) * up;
      b = db + (_rgb[2] - db) * up;
    }
    return (alpha8 << 24) | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RepaintBoundary(
      child: IgnorePointer(
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
      ),
    );
  }
}

class _Trig {
  _Trig(int n)
      : cos = Float64List(n),
        sin = Float64List(n) {
    for (var i = 0; i < n; i++) {
      final a = _tau * i / n;
      cos[i] = math.cos(a);
      sin[i] = math.sin(a);
    }
  }

  final Float64List cos;
  final Float64List sin;
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

/// The first level of [table] that is at least [want], or the last.
int _level(List<int> table, double want) {
  var i = table.length - 1;
  while (i > 0 && table[i - 1] >= want) {
    i--;
  }
  return i;
}

/// A ring's height, radii, tilt, tube shape and wall at a fractional slot,
/// smoothly between the measured ones.
void _slotGeom(double s, Float64List out) {
  final u = _clamp(s - _slot0, 0, _slots.length - 1.0001);
  final i = u.floor();
  final f = u - i;
  for (var c = 0; c < 6; c++) {
    final p0 = _slotAt(i - 1, c);
    final p1 = _slotAt(i, c);
    final p2 = _slotAt(i + 1, c);
    final p3 = _slotAt(i + 2, c);
    final v = 0.5 *
        (2 * p1 +
            (-p0 + p2) * f +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f +
            (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f);
    out[c] = (c == 0 || c == 3 || c == 5) ? v : math.exp(v);
  }
}

double _slotAt(int k, int c) {
  final at = k < 0 ? 0 : (k > _slots.length - 1 ? _slots.length - 1 : k);
  final v = _slots[at][c];
  return (c == 0 || c == 3 || c == 5) ? v : math.log(v);
}

// Colours are blended in OKLab, so a gradient never goes grey between hues.
double _toLin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _toSrgb(double v) {
  final l = _clamp(v, 0, 1);
  return l <= 0.0031308
      ? l * 12.92
      : 1.055 * math.pow(l, 1 / 2.4).toDouble() - 0.055;
}

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

void _toOklab(Color c, Float64List out, int k) {
  final r = _toLin(c.r);
  final g = _toLin(c.g);
  final b = _toLin(c.b);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  out[k] = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  out[k + 1] = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  out[k + 2] = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
}

void _fromOklab(double lum, double a, double b, Uint8List out, int k) {
  final lp = lum + 0.3963377774 * a + 0.2158037573 * b;
  final mp = lum - 0.1055613458 * a - 0.0638541728 * b;
  final sp = lum - 0.0894841775 * a - 1.291485548 * b;
  final l = lp * lp * lp;
  final m = mp * mp * mp;
  final s = sp * sp * sp;
  out[k] = (_toSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s) * 255).round();
  out[k + 1] = (_toSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s) * 255).round();
  out[k + 2] = (_toSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s) * 255).round();
}

/// A ring's gradient round its tube: the seven colours placed at their tube
/// angles and eased between neighbours.
Uint8List _buildRow(HourglassRing ring) {
  final colors = <Color>[
    ring.crest,
    ring.body,
    ring.shade,
    ring.glow,
    ring.halo,
    ring.core,
    ring.depth,
  ];
  const n = 7;
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) => _stops[a].compareTo(_stops[b]));
  final lab = Float64List(n * 3);
  final pos = Float64List(n);
  for (var i = 0; i < n; i++) {
    final j = order[i];
    _toOklab(colors[j], lab, i * 3);
    pos[i] = _stops[j];
  }
  final out = Uint8List(_palW * 3);
  for (var x = 0; x < _palW; x++) {
    final psi = ((x + 0.5) / _palW - 0.5) * 360;
    var i = n - 1;
    for (var q = 0; q < n; q++) {
      if (psi >= pos[q]) i = q;
    }
    final a = pos[i];
    final b = i == n - 1 ? pos[0] + 360 : pos[i + 1];
    var d = psi - a;
    if (d < 0) d += 360;
    final f = _smooth(0, 1, d / (b - a));
    final j = (i + 1) % n;
    _fromOklab(
      lab[i * 3] + (lab[j * 3] - lab[i * 3]) * f,
      lab[i * 3 + 1] + (lab[j * 3 + 1] - lab[i * 3 + 1]) * f,
      lab[i * 3 + 2] + (lab[j * 3 + 2] - lab[i * 3 + 2]) * f,
      out,
      x * 3,
    );
  }
  return out;
}

/// A colour from a gradient row at [x], wrapping round and easing between
/// neighbouring samples.
void _lookup(Uint8List row, double x, Float64List out) {
  final wrapped = x - x.floorToDouble();
  final pos = wrapped * _palW - 0.5;
  final i0 = pos.floor();
  final fr = pos - i0;
  final a = i0 % _palW;
  final b = (a + 1) % _palW;
  out[0] = row[a * 3] + (row[b * 3] - row[a * 3]) * fr;
  out[1] = row[a * 3 + 1] + (row[b * 3 + 1] - row[a * 3 + 1]) * fr;
  out[2] = row[a * 3 + 2] + (row[b * 3 + 2] - row[a * 3 + 2]) * fr;
}