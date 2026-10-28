import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import 'sphere_mesh.dart';
import 'water_sim.dart';

// Tangent of half the 50 degree field of view.
const double _tanHalfFov = 0.46630766;

// Direction of the sun, as a unit vector.
const double _lightX = -0.4148;
const double _lightY = 0.8297;
const double _lightZ = 0.3734;

double _clamp(double value, double low, double high) =>
    math.min(high, math.max(low, value));

double _smoothstep(double edge0, double edge1, double x) {
  final t = _clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

int _byte(double v) => (_clamp(v, 0, 1) * 255).round();

int _pack(double a, double r, double g, double b) =>
    (_byte(a) << 24) | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);

/// A ball of water that fills from a jet, sloshes, and ripples when touched.
///
/// Drag your finger over it to push the water along. Reset the controller to
/// play the filling animation again. It fills the space its parent gives it.
class WaterBall extends StatefulWidget {
  /// Creates a water ball.
  const WaterBall({
    super.key,
    this.waterColor = const ui.Color.fromARGB(255, 30, 138, 240),
    this.tint = 0.55,
    this.reflection = 0.12,
    this.level = 0.12,
    this.fillSeconds = 5.0,
    this.push = 1.0,
    this.dent = 1.0,
    this.opacity = 1.0,
    this.size = 1.0,
    this.background,
    this.speed = 1.0,
    this.spin = 0.0,
    this.paused = false,
    this.interactive = true,
    this.dragRotates = false,
    this.dragSensitivity = 1.0,
    this.quality = EffectQuality.medium,
    this.controller,
    this.semanticLabel,
  });

  /// Colour of the water.
  final Color waterColor;

  /// How strongly the water absorbs light as it gets thicker, from 0 to 1.
  final double tint;

  /// How reflective the surface is, from 0 to 1.
  final double reflection;

  /// How full the ball ends up, as the thickness of the water layer.
  final double level;

  /// How long the filling animation takes.
  final double fillSeconds;

  /// How strongly a finger drags the water along. 0 turns it off.
  final double push;

  /// How far the water parts when you press it, like stepping into shallow
  /// water. 0 turns it off.
  final double dent;

  /// How see-through the water is. 1.0 is the default; lower is clearer.
  final double opacity;

  /// Size of the ball, where 1.0 is the default.
  final double size;

  /// Fill behind the ball. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 is the default speed.
  final double speed;

  /// How fast the ball turns on its own. 0 keeps it still.
  final double spin;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch affects the water.
  final bool interactive;

  /// When true, dragging turns the ball instead of pushing the water.
  final bool dragRotates;

  /// How strongly a drag turns the ball, when [dragRotates] is true.
  final double dragSensitivity;

  /// Level of detail. Low uses 642 points, medium 2562 and high 10242. The
  /// default is medium, because high is heavy.
  final EffectQuality quality;

  /// Optional control. Calling reset plays the filling animation again.
  final EffectController? controller;

  /// Screen-reader description. Null marks the ball as decorative.
  final String? semanticLabel;

  @override
  State<WaterBall> createState() => _WaterBallState();
}

class _WaterBallState extends State<WaterBall> {
  final Paint _paint = Paint();

  WaterSim? _sim;
  int _builtKey = 0;
  Float32List _xy = Float32List(0);
  Float64List _rotatedZ = Float64List(0);
  Int32List _frontColor = Int32List(0);
  Int32List _backColor = Int32List(0);
  Uint16List _frontIndex = Uint16List(0);
  Uint16List _backIndex = Uint16List(0);

  double _lastTime = 0;
  double _boilTime = 0;
  bool _hasHit = false;
  double _prevHitX = 0;
  double _prevHitY = 0;
  double _prevHitZ = 0;

  double _waterR = 0;
  double _waterG = 0;
  double _waterB = 0;
  double _absorption = 0;
  double _fresnelBase = 0;
  double _envR = 0;
  double _envG = 0;
  double _envB = 0;

  WaterSim _simFor(int subdivisions) {
    final key = Object.hash(subdivisions, widget.level, widget.fillSeconds);
    final existing = _sim;
    if (existing != null && key == _builtKey) return existing;

    final mesh = SphereMesh(subdivisions: subdivisions);
    final sim = WaterSim(
      mesh,
      targetThickness: _clamp(widget.level, 0.03, 0.3),
      fillSeconds: math.max(0.5, widget.fillSeconds),
    );
    _sim = sim;
    _builtKey = key;
    _xy = Float32List(mesh.vertexCount * 2);
    _rotatedZ = Float64List(mesh.vertexCount);
    _frontColor = Int32List(mesh.vertexCount);
    _backColor = Int32List(mesh.vertexCount);
    _frontIndex = Uint16List(mesh.triangles.length);
    _backIndex = Uint16List(mesh.triangles.length);
    _hasHit = false;
    return sim;
  }

  /// Sky above the horizon, a dim ground below, and one soft sun.
  void _environment(double dx, double dy, double dz) {
    final double r;
    final double g;
    final double b;
    if (dy >= 0) {
      final t = math.pow(dy, 0.5).toDouble();
      r = 0.82 + (0.45 - 0.82) * t;
      g = 0.90 + (0.66 - 0.90) * t;
      b = 0.96 + (0.90 - 0.96) * t;
    } else {
      final t = math.pow(-dy, 0.4).toDouble();
      r = 0.82 + (0.30 - 0.82) * t;
      g = 0.90 + (0.27 - 0.90) * t;
      b = 0.96 + (0.22 - 0.96) * t;
    }
    final sun =
        math
            .pow(math.max(0.0, dx * _lightX + dy * _lightY + dz * _lightZ), 40)
            .toDouble() *
        0.9;
    _envR = r + sun;
    _envG = g + sun;
    _envB = b + sun;
  }

  int _shade(
    double nx,
    double ny,
    double nz,
    double vx,
    double vy,
    double vz,
    double thickness,
    double wet,
    double alphaScale,
  ) {
    final facing = math.max(0.0, nx * vx + ny * vy + nz * vz);
    final fresnel =
        _fresnelBase + (1 - _fresnelBase) * math.pow(1 - facing, 5).toDouble();

    // Mirror direction of the view vector around the normal.
    final rx = 2 * facing * nx - vx;
    final ry = 2 * facing * ny - vy;
    final rz = 2 * facing * nz - vz;
    _environment(rx, ry, rz);
    final spec =
        math
            .pow(math.max(0.0, rx * _lightX + ry * _lightY + rz * _lightZ), 90)
            .toDouble() *
        0.8;

    // Light that passes through the water loses everything but its colour.
    final seen = <double>[0.85, 0.90, 0.95];
    final water = <double>[_waterR, _waterG, _waterB];
    final env = <double>[
      _envR * 0.75 + _waterR * 0.25,
      _envG * 0.75 + _waterG * 0.25,
      _envB * 0.75 + _waterB * 0.25,
    ];
    final out = <double>[0, 0, 0];
    for (var c = 0; c < 3; c++) {
      final through =
          seen[c] * math.exp(-_absorption * thickness * (1 - water[c]));
      final rim = math.pow(1 - facing, 3).toDouble() * 0.22;
      out[c] = through +
          (env[c] - through) * fresnel +
          spec +
          rim * (0.4 + 0.6 * water[c]);
    }

    final alpha = wet *
        _clamp(0.30 + 0.55 * fresnel + 2.0 * thickness, 0, 0.9) *
        alphaScale *
        widget.opacity;

    return _pack(alpha, out[0], out[1], out[2]);
  }

  /// Drags the water along with the pointer.
  void _pushWater(
    WaterSim sim,
    EffectFrame frame,
    Size size,
    double focal,
    double distance,
    double cosYaw,
    double sinYaw,
    double cosPitch,
    double sinPitch,
    double elapsed,
  ) {
    sim.clearPress();
    final pointer = frame.pointer;
    if (pointer == null || frame.pointerStrength < 0.05 || widget.push <= 0) {
      _hasHit = false;
      return;
    }

    // A ray from the camera through the pointer, against the unit sphere.
    var rx = (pointer.dx - size.width / 2) / focal;
    var ry = -(pointer.dy - size.height / 2) / focal;
    var rz = -1.0;
    final length = math.sqrt(rx * rx + ry * ry + rz * rz);
    rx /= length;
    ry /= length;
    rz /= length;
    final b = distance * rz;
    final c = distance * distance - 1;
    final discriminant = b * b - c;
    if (discriminant < 0) {
      _hasHit = false;
      return;
    }
    final t = -b - math.sqrt(discriminant);
    if (t <= 0) {
      _hasHit = false;
      return;
    }
    final worldX = t * rx;
    final worldY = t * ry;
    final worldZ = distance + t * rz;

    // Back into the ball's own frame: undo the pitch, then the yaw.
    final y1 = worldY * cosPitch + worldZ * sinPitch;
    final z1 = -worldY * sinPitch + worldZ * cosPitch;
    final hitX = worldX * cosYaw - z1 * sinYaw;
    final hitZ = worldX * sinYaw + z1 * cosYaw;
    final hitY = y1;

        // Stepping into the water: it parts around the pressed point.
    if (frame.pressed && widget.dent > 0) {
      sim.setPress(
        px: hitX,
        py: hitY,
        pz: hitZ,
        radius: 0.32,
        strength: widget.dent,
      );
    }

    if (_hasHit) {
      var vx = (hitX - _prevHitX) / elapsed;
      var vy = (hitY - _prevHitY) / elapsed;
      var vz = (hitZ - _prevHitZ) / elapsed;
      final speed = math.sqrt(vx * vx + vy * vy + vz * vz);
      if (speed > 0.05) {
        final limit = speed > 8 ? 8 / speed : 1.0;
        vx *= limit;
        vy *= limit;
        vz *= limit;
        sim.push(
          px: hitX,
          py: hitY,
          pz: hitZ,
          vx: vx,
          vy: vy,
          vz: vz,
          radius: 0.5,
          blend: math.min(1.0, 8 * elapsed * widget.push),
        );
      }
    }
    _hasHit = true;
    _prevHitX = hitX;
    _prevHitY = hitY;
    _prevHitZ = hitZ;
  }

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame) {
    if (size.isEmpty) return;

    final subdivisions = switch (frame.quality) {
      EffectQuality.low => 3,
      EffectQuality.medium => 4,
      EffectQuality.high => 5,
    };
    final sim = _simFor(subdivisions);
    final mesh = sim.mesh;

    var elapsed = frame.time - _lastTime;
    if (elapsed < 0) {
      sim.reset();
      _hasHit = false;
      elapsed = 0;
    }
    _lastTime = frame.time;
    _boilTime = frame.time;
    elapsed = math.min(elapsed, 0.033);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final focal = (math.min(size.width, size.height) / 2) / _tanHalfFov;
    final distance = 3.2 / _clamp(widget.size, 0.3, 2.0);

    final yaw = frame.yaw;
    final pitch = frame.pitch + 0.25;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    if (elapsed > 0) {
      _pushWater(
        sim,
        frame,
        size,
        focal,
        distance,
        cosYaw,
        sinYaw,
        cosPitch,
        sinPitch,
        elapsed,
      );
      sim.advance(elapsed);
    }
    sim.computeGradient();

    final color = widget.waterColor;
    _waterR = color.r;
    _waterG = color.g;
    _waterB = color.b;
    _absorption = 20 * _clamp(widget.tint, 0, 1);
    _fresnelBase = _clamp(widget.reflection, 0, 1);

    final gradient = sim.surfaceGradient;
    final vel = sim.velocity;
    final heights = sim.height;
    const bump = 7.0;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final k = i * 3;
      final px = mesh.position[k];
      final py = mesh.position[k + 1];
      final pz = mesh.position[k + 2];
      final h = heights[i];

      // The surface normal: the sphere's normal, tilted against the slope.
      var nx = px - bump * gradient[k];
      var ny = py - bump * gradient[k + 1];
      var nz = pz - bump * gradient[k + 2];
      
      // Thin, fast water boils: small wobbles in the surface normal. It calms
      // down by itself as the water settles.
      final speed = math.sqrt(
        vel[k] * vel[k] + vel[k + 1] * vel[k + 1] + vel[k + 2] * vel[k + 2],
      );
      final boil =
          _clamp(speed * 0.7, 0, 1) * (1 - _smoothstep(0.04, 0.12, h));
      if (boil > 0.01) {
        final t = _boilTime;
        nx += boil * 0.45 * math.sin(px * 13 + t * 3.1) * math.sin(py * 11 - t * 2.3);
        ny += boil * 0.45 * math.sin(py * 12 + t * 2.7) * math.sin(pz * 10 - t * 3.5);
        nz += boil * 0.45 * math.sin(pz * 14 - t * 2.9) * math.sin(px * 9 + t * 2.1);
      }
      final nLength = math.sqrt(nx * nx + ny * ny + nz * nz);
      nx /= nLength;
      ny /= nLength;
      nz /= nLength;

      // Turn the point and the normal: yaw, then pitch.
      final tx = px * cosYaw + pz * sinYaw;
      final tz = -px * sinYaw + pz * cosYaw;
      final ry = py * cosPitch - tz * sinPitch;
      final rz = py * sinPitch + tz * cosPitch;
      final rnx0 = nx * cosYaw + nz * sinYaw;
      final rnz0 = -nx * sinYaw + nz * cosYaw;
      final rny = ny * cosPitch - rnz0 * sinPitch;
      final rnz = ny * sinPitch + rnz0 * cosPitch;
      _rotatedZ[i] = rz;

      // Thick water bulges outward a little.
      // Fast water is thrown slightly outward. Kept small and smooth: big
      // per-vertex differences stretch the triangles and tear the surface.
      final lift = _smoothstep(1.5, 5.0, speed) *
          _smoothstep(0.01, 0.05, h) *
          0.16 *
          (0.8 + 0.2 * math.sin(px * 5 + py * 4 + pz * 6 + _boilTime * 3));
      final bulge = 1 + 0.35 * h + lift;
      final wx = tx * bulge;
      final wy = ry * bulge;
      final wz = rz * bulge;
      final denominator = math.max(0.05, distance - wz);
      _xy[i * 2] = centerX + focal * wx / denominator;
      _xy[i * 2 + 1] = centerY - focal * wy / denominator;

      final wet = _smoothstep(0.003, 0.03, h);
      if (wet <= 0) {
        _frontColor[i] = 0;
        _backColor[i] = 0;
        continue;
      }

      // From the surface toward the camera at (0, 0, distance).
      var vx = -wx;
      var vy = -wy;
      var vz = distance - wz;
      final vLength = math.sqrt(vx * vx + vy * vy + vz * vz);
      vx /= vLength;
      vy /= vLength;
      vz /= vLength;

      _frontColor[i] = _shade(rnx0, rny, rnz, vx, vy, vz, 3 * h, wet, 1.0);
      _backColor[i] = _shade(-rnx0, -rny, -rnz, vx, vy, vz, 3 * h, wet, 0.55);

    }

    // Sort the triangles into the near half and the far half of the ball.
    var frontCount = 0;
    var backCount = 0;
    final triangles = mesh.triangles;
    for (var t = 0; t < triangles.length; t += 3) {
      final a = triangles[t];
      final b = triangles[t + 1];
      final c = triangles[t + 2];
      if (heights[a] < 0.003 && heights[b] < 0.003 && heights[c] < 0.003) {
        continue;
      }
      final centre = (_rotatedZ[a] + _rotatedZ[b] + _rotatedZ[c]) / 3;
      if (centre * distance > 1) {
        _frontIndex[frontCount++] = a;
        _frontIndex[frontCount++] = b;
        _frontIndex[frontCount++] = c;
      } else {
        _backIndex[backCount++] = a;
        _backIndex[backCount++] = b;
        _backIndex[backCount++] = c;
      }
    }

    if (backCount > 0) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        _xy,
        colors: _backColor,
        indices: Uint16List.sublistView(_backIndex, 0, backCount),
      );
      canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
      vertices.dispose();
    }
    if (frontCount > 0) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        _xy,
        colors: _frontColor,
        indices: Uint16List.sublistView(_frontIndex, 0, frontCount),
      );
      canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
      vertices.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return EffectHost(
      onPaint: _paintFrame,
      speed: widget.speed,
      paused: widget.paused,
      interactive: widget.interactive,
      rotatesOnDrag: widget.dragRotates,
      dragSensitivity: widget.dragSensitivity,
      autoRotate: 0.3 * widget.spin,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}
