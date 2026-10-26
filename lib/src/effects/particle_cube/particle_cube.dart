import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/color_ramp.dart';
import '../../core/color_utils.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/palette.dart';
import '../../core/quality_scale.dart';
import 'cube_model.dart';

const int _depthBuckets = 6;
const int _nearBucket = _depthBuckets;
const int _touchBucket = _depthBuckets + 1;
const int _bucketCount = _depthBuckets + 2;
const double _halfDiagonal = 1.7320508075688772;

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

/// A cube made of glowing dots whose layers turn like a Rubik's cube.
///
/// Dots fade and shrink with distance, and colours run from the first colour
/// (far away) to the last (close). Touch or hover to make the dots near your
/// finger grow and glow, and drag to spin the whole cube. It fills the space
/// its parent gives it.
class ParticleCube extends StatefulWidget {
  /// Creates a particle cube.
  const ParticleCube({
    super.key,
    this.colors,
    this.background,
    this.grid = 4,
    this.dotsPerCell = 3,
    this.dotSize = 2.5,
    this.size = 1.0,
    this.turnDuration = const Duration(milliseconds: 750),
    this.hoverBoost = 1.0,
    this.speed = 1.0,
    this.spin = 1.0,
    this.paused = false,
    this.interactive = true,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// Colours from far to near. If null, they come from the app's theme.
  final List<Color>? colors;

  /// Fill behind the cube. Null means transparent.
  final Color? background;

  /// Cells along each edge, from 2 to 8. This is also the number of layers.
  final int grid;

  /// Dots along each cell edge, from 1 to 8. More dots look denser and cost more.
  final int dotsPerCell;

  /// Base dot radius in logical pixels.
  final double dotSize;

  /// Size of the cube, where 1.0 is the default and 2.0 is twice as big.
  final double size;

  /// How long one layer takes to turn.
  final Duration turnDuration;

  /// How much dots grow and glow near a finger or mouse. 0 turns it off.
  final double hoverBoost;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// How fast the cube turns on its own. 0 stops the turning.
  final double spin;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch, hover and drag affect the cube.
  final bool interactive;

  /// How strongly a drag turns the cube.
  final double dragSensitivity;

  /// Level of detail. Lower settings use fewer dots per cell.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the cube as decorative.
  final String? semanticLabel;

  @override
  State<ParticleCube> createState() => _ParticleCubeState();
}

class _ParticleCubeState extends State<ParticleCube> {
  final Paint _dotPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  final Int32List _counts = Int32List(_bucketCount);
  final Int32List _starts = Int32List(_bucketCount);
  final Int32List _fill = Int32List(_bucketCount);

  CubeModel? _model;
  int _builtGrid = 0;
  int _builtDots = 0;
  double _lastTime = 0;
  Float32List _sx = Float32List(0);
  Float32List _sy = Float32List(0);
  Float32List _xy = Float32List(0);
  Uint8List _bucket = Uint8List(0);

  CubeModel _modelFor(int grid, int dots) {
    final existing = _model;
    if (existing != null && grid == _builtGrid && dots == _builtDots) {
      return existing;
    }
    final model = CubeModel(grid: grid, dotsPerCell: dots);
    _model = model;
    _builtGrid = grid;
    _builtDots = dots;
    final n = model.count;
    _sx = Float32List(n);
    _sy = Float32List(n);
    _xy = Float32List(n * 2);
    _bucket = Uint8List(n);
    return model;
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    EffectFrame frame,
    ColorRamp ramp,
  ) {
    if (size.isEmpty) return;

    final dots = frame.quality.scaleCount(widget.dotsPerCell);
    final model = _modelFor(widget.grid, dots);

    // Advance by the time since the last paint. Repeated paints at the same
    // time add nothing, and a time that went backwards means a reset.
    var elapsed = frame.time - _lastTime;
    if (elapsed < 0) {
      model.reset();
      elapsed = 0;
    }
    _lastTime = frame.time;
    model.advance(
      math.min(elapsed, 0.1),
      widget.turnDuration.inMicroseconds / 1e6,
    );

    final w = size.width;
    final h = size.height;
    final centreX = w / 2;
    final centreY = h / 2;
    final scale = math.min(w, h) * 0.26 * _clamp(widget.size, 0.2, 2.0);

    final yaw = frame.yaw + 0.6;
    final pitch = frame.pitch + 0.45 + 0.25 * math.sin(frame.time * 0.3);
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    final turning = model.isTurning;
    final angle = model.turnAngle;
    final cosTurn = math.cos(angle);
    final sinTurn = math.sin(angle);
    final turnAxis = model.axis;

    final pointer = frame.pointer;
    final strength = frame.pointerStrength * _clamp(widget.hoverBoost, 0, 2);
    final reach = math.min(w, h) * 0.22;
    final reachSquared = reach * reach;
    final innerSquared = reachSquared * 0.25;
    final touching = pointer != null && strength > 0.02;

    final n = model.count;
    final inverse = 1 / (model.axisPoints - 1);
    _counts.fillRange(0, _bucketCount, 0);

    for (var i = 0; i < n; i++) {
      var px = model.x[i] * inverse;
      var py = model.y[i] * inverse;
      var pz = model.z[i] * inverse;

      if (turning && model.member[i] == 1) {
        switch (turnAxis) {
          case 0:
            final ny = py * cosTurn - pz * sinTurn;
            final nz = py * sinTurn + pz * cosTurn;
            py = ny;
            pz = nz;
          case 1:
            final nx = px * cosTurn + pz * sinTurn;
            final nz = -px * sinTurn + pz * cosTurn;
            px = nx;
            pz = nz;
          default:
            final nx = px * cosTurn - py * sinTurn;
            final ny = px * sinTurn + py * cosTurn;
            px = nx;
            py = ny;
        }
      }

      // Turn the whole cube: yaw, then pitch (same maths as OrbitCamera.rotate).
      final x1 = px * cosYaw + pz * sinYaw;
      final z1 = -px * sinYaw + pz * cosYaw;
      final y2 = py * cosPitch - z1 * sinPitch;
      final z2 = py * sinPitch + z1 * cosPitch;

      final perspective = 1 + z2 * 0.16;
      final screenX = centreX + x1 * scale * perspective;
      final screenY = centreY - y2 * scale * perspective;

      final depth = _clamp((z2 + _halfDiagonal) / (2 * _halfDiagonal), 0, 1);
      var bucket = math.min(_depthBuckets - 1, (depth * _depthBuckets).floor());
      if (touching) {
        final dx = screenX - pointer.dx;
        final dy = screenY - pointer.dy;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared < reachSquared) {
          bucket = distanceSquared < innerSquared ? _touchBucket : _nearBucket;
        }
      }

      _sx[i] = screenX;
      _sy[i] = screenY;
      _bucket[i] = bucket;
      _counts[bucket]++;
    }

    // Sort the points into their buckets so each bucket is one draw call.
    var offset = 0;
    for (var b = 0; b < _bucketCount; b++) {
      _starts[b] = offset;
      _fill[b] = offset;
      offset += _counts[b];
    }
    for (var i = 0; i < n; i++) {
      final b = _bucket[i];
      final at = _fill[b];
      _fill[b] = at + 1;
      _xy[at * 2] = _sx[i];
      _xy[at * 2 + 1] = _sy[i];
    }

    final dot = math.max(0.5, widget.dotSize);
    for (var b = 0; b < _bucketCount; b++) {
      final count = _counts[b];
      if (count == 0) continue;

      final double radius;
      final double alpha;
      final Color color;
      if (b < _depthBuckets) {
        final t = (b + 0.5) / _depthBuckets;
        radius = dot * (0.5 + 0.7 * t);
        alpha = 0.22 + 0.78 * t;
        color = ramp.at(t);
      } else if (b == _nearBucket) {
        radius = dot * (1.2 + 0.8 * strength);
        alpha = 0.6 + 0.3 * math.min(1.0, strength);
        color = ramp.at(1);
      } else {
        radius = dot * (1.6 + 1.4 * strength);
        alpha = 0.95;
        color = ramp.at(1);
      }

      _dotPaint
        ..strokeWidth = radius * 2
        ..color = scaleAlpha(color, alpha);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_xy, _starts[b] * 2, (_starts[b] + count) * 2),
        _dotPaint,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ramp = ColorRamp(resolvePalette(context, widget.colors));
    return EffectHost(
      onPaint: (canvas, size, frame) => _paintFrame(canvas, size, frame, ramp),
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      dragSensitivity: widget.dragSensitivity,
      autoRotate: 0.4 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}