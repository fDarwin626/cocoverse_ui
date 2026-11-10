import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';

const int _minTiles = 4;
const int _maxTiles = 120;

// Tiles overlap their neighbours by this many logical pixels, so no hairline
// shows between them.
const double _seamOverlap = 0.75;

// The most a single frame can move the clock, so a stall never skips ahead.
const double _maxStep = 0.1;

const List<List<Color>> _placeholderColors = <List<Color>>[
  <Color>[Color(0xFFF5D589), Color(0xFFE8B64A)],
  <Color>[Color(0xFF8EE6DA), Color(0xFF34D1BF)],
  <Color>[Color(0xFFFFB199), Color(0xFFFF7A59)],
  <Color>[Color(0xFFB9A8FF), Color(0xFF7B5CFF)],
];

/// A stack of photos that flip over one after another, tile by tile, like a
/// split-flap board.
///
/// It fills the space it is given, so you choose how big it shows by sizing
/// its parent: full screen, half a screen or a small card.
///
/// ```dart
/// SizedBox(
///   height: 240,
///   child: Timeline(
///     images: [AssetImage('assets/a.jpg'), AssetImage('assets/b.jpg')],
///   ),
/// )
/// ```
///
/// With no [images] it shows "Your photo here" placeholders, so you can see
/// how it behaves before any photo is added.
class Timeline extends StatefulWidget {
  /// Creates a photo timeline.
  const Timeline({
    super.key,
    this.images = const <ImageProvider>[],
    this.placeholderCount = 3,
    this.placeholderLabel = 'Your photo here',
    this.focusY = 50.0,
    this.tiles = 50,
    this.angle = 77.0,
    this.flip = 50.0,
    this.duration = const Duration(milliseconds: 1200),
    this.hold = const Duration(seconds: 1),
    this.curve = Curves.linear,
    this.loop = true,
    this.maxImageSize = 2048,
    this.paused = false,
    this.quality = EffectQuality.high,
    this.background,
    this.controller,
    this.semanticLabel,
  });

  /// The photos, in the order they show. Any number. Empty shows placeholders.
  final List<ImageProvider> images;

  /// How many placeholder slides show when [images] is empty.
  final int placeholderCount;

  /// The words on each placeholder slide.
  final String placeholderLabel;

  /// Where a photo that is taller than the box is anchored, from 0 (top)
  /// to 100 (bottom). 50 centres it.
  final double focusY;

  /// Tiles across the box, 4 to 120. The tiles are square, so the number
  /// down follows from the shape of the box. Lower quality settings use fewer.
  final int tiles;

  /// Direction of the sweep in degrees. 0 sweeps left to right, 90 top to
  /// bottom.
  final double angle;

  /// How much of the transition each tile spends flipping, from 5 to 100
  /// percent. The rest is the delay between the first tile and the last.
  final double flip;

  /// How long one photo takes to flip in.
  final Duration duration;

  /// How long a photo stays once it has landed.
  final Duration hold;

  /// Shapes the sweep. Linear is an even wave.
  final Curve curve;

  /// Whether it goes back to the first photo after the last. False stops on
  /// the last one.
  final bool loop;

  /// The longest side, in pixels, a photo is decoded at. Larger photos are
  /// shrunk as they load, which saves a lot of memory.
  final int maxImageSize;

  /// Freezes the animation when true.
  final bool paused;

  /// Level of detail. Lower settings draw fewer tiles.
  final EffectQuality quality;

  /// Fill behind the photos. Null means transparent.
  final Color? background;

  /// Optional control. [EffectController.reset] starts again from the first
  /// photo.
  final EffectController? controller;

  /// Screen-reader description. Null marks it as decorative.
  final String? semanticLabel;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  final Paint _paint = Paint()..isAntiAlias = false;

  List<ui.Image?> _loaded = <ui.Image?>[];
  final List<VoidCallback> _cancels = <VoidCallback>[];
  int _generation = 0;
  bool _started = false;
  bool _reduced = false;

  int _index = 0;
  ui.Image? _previous;
  int _reveal = 0;
  double _clock = 0;
  double _lastTime = 0;
  double _start = -1;
  bool _done = false;
  int _seenResets = 0;

  _Grid? _grid;
  Object? _gridKey;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _seenResets = widget.controller?.resetCount ?? 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(Timeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _seenResets = widget.controller?.resetCount ?? 0;
    }
    if (!listEquals(oldWidget.images, widget.images) ||
        oldWidget.maxImageSize != widget.maxImageSize ||
        oldWidget.placeholderCount != widget.placeholderCount ||
        oldWidget.placeholderLabel != widget.placeholderLabel) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _generation++;
    for (final cancel in _cancels) {
      cancel();
    }
    _cancels.clear();
    for (final image in _loaded) {
      image?.dispose();
    }
    _loaded = <ui.Image?>[];
    _previous = null;
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
    _index = 0;
    _previous = null;
    _reveal = 0;
    _start = -1;
    _done = false;
  }

  /// Loads every photo, or makes the placeholders, and starts again from
  /// the first.
  void _load() {
    final generation = ++_generation;
    for (final cancel in _cancels) {
      cancel();
    }
    _cancels.clear();
    _previous = null;
    for (final image in _loaded) {
      image?.dispose();
    }

    final providers = widget.images;
    final count = providers.isEmpty
        ? math.max(1, widget.placeholderCount)
        : providers.length;
    _loaded = List<ui.Image?>.filled(count, null);
    _restart();

    if (providers.isEmpty) {
      for (var i = 0; i < count; i++) {
        unawaited(
          _makePlaceholder(i, count).then((image) => _store(generation, i, image)),
        );
      }
      return;
    }

    final configuration = createLocalImageConfiguration(context);
    for (var i = 0; i < providers.length; i++) {
      final provider = ResizeImage(
        providers[i],
        width: widget.maxImageSize,
        height: widget.maxImageSize,
        policy: ResizeImagePolicy.fit,
      );
      final stream = provider.resolve(configuration);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          stream.removeListener(listener);
          _store(generation, i, info.image.clone());
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          debugPrint('Timeline: could not load photo $i: $error');
        },
      );
      stream.addListener(listener);
      _cancels.add(() => stream.removeListener(listener));
    }
  }

  void _store(int generation, int slot, ui.Image image) {
    if (!mounted || generation != _generation || slot >= _loaded.length) {
      image.dispose();
      return;
    }
    _loaded[slot] = image;
  }

  Future<ui.Image> _makePlaceholder(int i, int count) async {
    const double side = 1000;
    final label = widget.placeholderLabel;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final colors = _placeholderColors[i % _placeholderColors.length];
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, side, side),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(side, side),
          colors,
        ),
    );

    void write(String text, double y, double size, Color color, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            color: color,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 700);
      painter.paint(canvas, Offset((side - painter.width) / 2, y));
      painter.dispose();
    }

    write('${i + 1}', 250, 400, const Color(0x55FFFFFF), FontWeight.w800);
    write(label, 690, 76, const Color(0xFF1C1405), FontWeight.w700);
    write('${i + 1} of $count', 790, 44, const Color(0xAA1C1405), FontWeight.w500);

    final picture = recorder.endRecording();
    final image = await picture.toImage(side.toInt(), side.toInt());
    picture.dispose();
    return image;
  }

  /// The tile layout for this box. Rebuilt only when the box or the settings
  /// change.
  _Grid _gridFor(Size size) {
    final key = (size, widget.tiles, widget.angle, widget.curve, widget.quality);
    final cached = _grid;
    if (cached != null && _gridKey == key) return cached;

    final cap = switch (widget.quality) {
      EffectQuality.low => 1200,
      EffectQuality.medium => 2200,
      EffectQuality.high => 3600,
    };
    var cols = math.max(_minTiles, math.min(_maxTiles, widget.tiles));
    final fits = math.sqrt(cap * size.width / size.height).floor();
    cols = math.max(_minTiles, math.min(cols, fits));
    final cellW = size.width / cols;
    final rows = math.max(1, (size.height / cellW).round());
    final cellH = size.height / rows;

    final rad = widget.angle * math.pi / 180;
    final ux = math.cos(rad);
    final uy = math.sin(rad);
    final count = cols * rows;
    final raw = Float64List(count);
    var lo = double.infinity;
    var hi = -double.infinity;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p = ((c + 0.5) / cols) * ux + ((r + 0.5) / rows) * uy;
        raw[r * cols + c] = p;
        if (p < lo) lo = p;
        if (p > hi) hi = p;
      }
    }
    final range = hi - lo == 0 ? 1.0 : hi - lo;
    final forward = Float64List(count);
    final reverse = Float64List(count);
    for (var i = 0; i < count; i++) {
      final u = _clamp((raw[i] - lo) / range, 0, 1);
      forward[i] = widget.curve.transform(u);
      reverse[i] = widget.curve.transform(1 - u);
    }

    final grid = _Grid(
      cols: cols,
      rows: rows,
      cellW: cellW,
      cellH: cellH,
      forward: forward,
      reverse: reverse,
    );
    _grid = grid;
    _gridKey = key;
    return grid;
  }

  _Cover _cover(ui.Image image, Size size) {
    final scale = math.max(size.width / image.width, size.height / image.height);
    final dx = (size.width - image.width * scale) / 2;
    final slack = size.height - image.height * scale;
    final f = _clamp(widget.focusY, 0, 100) / 100;
    return _Cover(scale, dx, slack * f);
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;

    final dt = frame.time - _lastTime;
    _lastTime = frame.time;
    if (dt > 0) _clock += math.min(dt, _maxStep);

    if (_index >= _loaded.length) return;
    final current = _loaded[_index];
    if (current == null) return;

    _paint.filterQuality =
        widget.quality == EffectQuality.low ? FilterQuality.low : FilterQuality.medium;

    // Someone who asked for less movement gets the first photo, still.
    if (_reduced) {
      _drawWhole(canvas, size, current);
      return;
    }

    final total = math.max(0.1, widget.duration.inMicroseconds / 1e6);
    final hold = math.max(0.0, widget.hold.inMicroseconds / 1e6);

    if (_start < 0) {
      _start = _clock;
      _done = false;
    }
    final elapsed = _clock - _start;

    if (_done) {
      _drawWhole(canvas, size, current);
    } else {
      final flipDur = math.max(0.08, total * _clamp(widget.flip, 5, 100) / 100);
      final spread = math.max(0.0, total - flipDur);
      final flaps = math.max(2, math.min(6, (flipDur / 0.11).round()));
      final grid = _gridFor(size);
      final settled = _drawTiles(
        canvas,
        size,
        grid,
        current,
        elapsed,
        spread,
        flipDur,
        flaps,
      );
      if (settled) _done = true;
    }

    if (_done && elapsed > total + hold) _advance();
  }

  void _advance() {
    var ready = 0;
    for (final image in _loaded) {
      if (image != null) ready++;
    }
    if (ready < 2) return;
    final next = _nextReady(_index, widget.loop);
    if (next == _index) return;
    _previous = _loaded[_index];
    _index = next;
    _reveal++;
    _start = -1;
    _done = false;
  }

  int _nextReady(int from, bool wrap) {
    final count = _loaded.length;
    for (var step = 1; step < count; step++) {
      var candidate = from + step;
      if (candidate >= count) {
        if (!wrap) return from;
        candidate %= count;
      }
      if (_loaded[candidate] != null) return candidate;
    }
    return from;
  }

  /// The whole photo in one draw, for when nothing is flipping.
  void _drawWhole(Canvas canvas, Size size, ui.Image image) {
    final cov = _cover(image, size);
    final src = Rect.fromLTWH(
      -cov.dx / cov.scale,
      -cov.dy / cov.scale,
      size.width / cov.scale,
      size.height / cov.scale,
    );
    canvas.drawImageRect(image, src, Offset.zero & size, _paint);
  }

  /// Draws every tile for this moment. Returns true once every tile has
  /// landed.
  bool _drawTiles(
    Canvas canvas,
    Size size,
    _Grid grid,
    ui.Image image,
    double elapsed,
    double spread,
    double flipDur,
    int flaps,
  ) {
    final cov = _cover(image, size);
    final behind = _previous;
    final behindCov = behind == null ? null : _cover(behind, size);
    final order = _reveal.isOdd ? grid.reverse : grid.forward;
    final cols = grid.cols;
    final rows = grid.rows;
    final cw = grid.cellW;
    final ch = grid.cellH;
    var settled = true;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final start = order[idx] * spread;
        final x = c * cw;
        final y = r * ch;

        // Not its turn yet: the photo that is being replaced still shows.
        if (elapsed < start) {
          settled = false;
          if (behind != null && behindCov != null) {
            _drawTile(
              canvas,
              behind,
              behindCov,
              grid,
              x,
              y,
              (x - behindCov.dx) / behindCov.scale,
              (y - behindCov.dy) / behindCov.scale,
              1,
            );
          }
          continue;
        }

        // Mid flip: a squashed flap showing a shuffling piece of the new photo.
        if (elapsed < start + flipDur) {
          settled = false;
          final local = (elapsed - start) / flipDur;
          final tick = (local * flaps).floor();
          final hash = (idx * 73 + tick * 131 + 17) % (cols * rows);
          final hashCol = hash % cols;
          final hashRow = (hash ~/ cols) % rows;
          final scaleY = 0.12 + math.cos(local * flaps * math.pi).abs() * 0.88;
          _drawTile(
            canvas,
            image,
            cov,
            grid,
            x,
            y,
            (hashCol * cw - cov.dx) / cov.scale,
            (hashRow * ch - cov.dy) / cov.scale,
            scaleY,
          );
          continue;
        }

        // Landed: its own piece of the new photo.
        _drawTile(
          canvas,
          image,
          cov,
          grid,
          x,
          y,
          (x - cov.dx) / cov.scale,
          (y - cov.dy) / cov.scale,
          1,
        );
      }
    }
    return settled;
  }

  void _drawTile(
    Canvas canvas,
    ui.Image image,
    _Cover cov,
    _Grid grid,
    double cellX,
    double cellY,
    double srcX,
    double srcY,
    double scaleY,
  ) {
    final srcW = grid.cellW / cov.scale;
    final srcH = grid.cellH / cov.scale;
    final sx = math.max(0.0, math.min(image.width - srcW, srcX));
    final sy = math.max(0.0, math.min(image.height - srcH, srcY));
    final centerY = cellY + grid.cellH / 2;
    final dst = Rect.fromLTRB(
      cellX,
      centerY - (grid.cellH / 2) * scaleY,
      cellX + grid.cellW + _seamOverlap,
      centerY + (grid.cellH / 2 + _seamOverlap) * scaleY,
    );
    canvas.drawImageRect(image, Rect.fromLTWH(sx, sy, srcW, srcH), dst, _paint);
  }

  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return EffectHost(
      onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame),
      paused: widget.paused,
      interactive: false,
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

/// How a photo is scaled to cover the box, and where it sits in it.
class _Cover {
  const _Cover(this.scale, this.dx, this.dy);

  final double scale;
  final double dx;
  final double dy;
}

/// The tile layout: how many, how big, and when each one's turn comes, for
/// the sweep in both directions.
class _Grid {
  _Grid({
    required this.cols,
    required this.rows,
    required this.cellW,
    required this.cellH,
    required this.forward,
    required this.reverse,
  });

  final int cols;
  final int rows;
  final double cellW;
  final double cellH;

  /// Each tile's place in the sweep, 0 to 1, already run through the curve.
  final Float64List forward;
  final Float64List reverse;
}