import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/color_ramp.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/palette.dart';
import 'cluster_geometry.dart';
import 'cluster_renderer.dart';

// Tangent of half the 50 degree field of view.
const double _tanHalfFov = 0.46630766;
const double _extrusionUnit = 0.45;

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

/// A sphere of small prism-shaped shards that grow and shrink like a living
/// crystal.
///
/// Shards near your finger or mouse grow and light up in the accent colour,
/// and dragging spins the sphere. It fills the space its parent gives it.
class ShardSphere extends StatefulWidget {
  /// Creates a shard sphere.
  const ShardSphere({
    super.key,
    this.colors,
    this.background,
    this.density = 3,
    this.shardSize = 1.0,
    this.extrusion = 1.0,
    this.distance = 4.0,
    this.lift = 1.0,
    this.reach = 1.0,
    this.speed = 1.0,
    this.spin = 1.0,
    this.paused = false,
    this.interactive = true,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.high,
    this.controller,
    this.semanticLabel,
  });

  /// Three colours: the shadow side, the lit side, and the highlight near a
  /// finger. If null, they come from the app's theme.
  final List<Color>? colors;

  /// Fill behind the sphere. Null means transparent.
  final Color? background;

  /// Detail, from 1 to 5. Density 3 gives 180 shards and 5 gives 500.
  final int density;

  /// Size of the shards, where 1.0 is the default.
  final double shardSize;

  /// How tall the shards are, where 1.0 is the default and 0 is flat.
  final double extrusion;

  /// Camera distance. Larger makes the sphere look smaller.
  final double distance;

  /// How much shards grow near a finger or mouse. 0 turns it off.
  final double lift;

  /// How far the finger's influence reaches, where 1.0 is the default.
  final double reach;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// How fast the sphere turns on its own. 0 stops the turning.
  final double spin;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch, hover and drag affect the sphere.
  final bool interactive;

  /// How strongly a drag turns the sphere.
  final double dragSensitivity;

  /// Level of detail. Low limits density to 2, medium to 3.
  final EffectQuality quality;

  /// Optional control over pausing, resuming and resetting.
  final EffectController? controller;

  /// Screen-reader description. Null marks the sphere as decorative.
  final String? semanticLabel;

  @override
  State<ShardSphere> createState() => _ShardSphereState();
}

class _ShardSphereState extends State<ShardSphere> {
  final Paint _paint = Paint();

  ClusterRenderer? _renderer;
  int _builtDensity = 0;
  double _lastTime = 0;
  double _hoverX = 0;
  double _hoverY = 0;
  double _hoverZ = 1;
  double _hoverStrength = 0;

  ClusterRenderer _rendererFor(int density) {
    final existing = _renderer;
    if (existing != null && density == _builtDensity) return existing;
    final renderer = ClusterRenderer(ClusterGeometry(density: density));
    _renderer = renderer;
    _builtDensity = density;
    return renderer;
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    EffectFrame frame,
    ColorRamp ramp,
  ) {
    if (size.isEmpty) return;

    final limit = switch (frame.quality) {
      EffectQuality.low => 2,
      EffectQuality.medium => 3,
      EffectQuality.high => 5,
    };
    final density = math.min(limit, math.max(1, widget.density));
    final renderer = _rendererFor(density);

    var elapsed = frame.time - _lastTime;
    if (elapsed < 0) {
      _hoverStrength = 0;
      elapsed = 0;
    }
    _lastTime = frame.time;
    elapsed = math.min(elapsed, 0.1);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final focal = (math.min(size.width, size.height) / 2) / _tanHalfFov;
    final extrusion = _clamp(widget.extrusion, 0, 2) * _extrusionUnit;
    final distance = math.max(widget.distance, 1 + extrusion + 0.25);

    // Where a ray from the camera through the pointer meets the sphere.
    var hit = false;
    var targetX = 0.0;
    var targetY = 0.0;
    var targetZ = 1.0;
    final pointer = frame.pointer;
    if (pointer != null && frame.pointerStrength > 0.01) {
      var rx = (pointer.dx - centerX) / focal;
      var ry = -(pointer.dy - centerY) / focal;
      var rz = -1.0;
      final length = math.sqrt(rx * rx + ry * ry + rz * rz);
      rx /= length;
      ry /= length;
      rz /= length;
      final b = distance * rz;
      final c = distance * distance - 1;
      final discriminant = b * b - c;
      if (discriminant >= 0) {
        final t = -b - math.sqrt(discriminant);
        if (t > 0) {
          hit = true;
          targetX = t * rx;
          targetY = t * ry;
          targetZ = distance + t * rz;
        }
      }
    }

    if (hit) {
      if (_hoverStrength < 0.05) {
        _hoverX = targetX;
        _hoverY = targetY;
        _hoverZ = targetZ;
      } else {
        final k = 1 - math.exp(-elapsed * 6);
        _hoverX += (targetX - _hoverX) * k;
        _hoverY += (targetY - _hoverY) * k;
        _hoverZ += (targetZ - _hoverZ) * k;
      }
    }
    final strengthTarget = hit ? frame.pointerStrength : 0.0;
    _hoverStrength +=
        (strengthTarget - _hoverStrength) * (1 - math.exp(-elapsed * 10));

    final reachOut = _clamp(widget.reach, 0.05, 2.0);
    final size01 = _clamp(widget.shardSize, 0.1, 2.0);

    final vertices = renderer.build(
      centerX: centerX,
      centerY: centerY,
      focal: focal,
      distance: distance,
      yaw: frame.yaw,
      pitch: frame.pitch + 0.2,
      noiseTime: frame.time * 0.5,
      scaleMin: 0.15 * size01,
      scaleMax: 0.75 * size01,
      extrusion: extrusion,
      lift: 0.63 * _clamp(widget.lift, 0, 3),
      hoverX: _hoverX,
      hoverY: _hoverY,
      hoverZ: _hoverZ,
      hoverStrength: _hoverStrength,
      reachIn: reachOut * 0.25,
      reachOut: reachOut,
      shadow: ramp.at(0),
      base: ramp.at(0.5),
      accent: ramp.at(1),
    );
    if (vertices == null) return;
    canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
    vertices.dispose();
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
      autoRotate: 0.5 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}