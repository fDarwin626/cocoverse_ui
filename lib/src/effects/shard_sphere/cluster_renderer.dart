import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/noise.dart';
import 'cluster_geometry.dart';

// A fixed light, in view space: from the upper left, toward the viewer.
const double _lightX = -0.3522;
const double _lightY = 0.5535;
const double _lightZ = 0.7547;

double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 == edge0) return x < edge0 ? 0 : 1;
  final t = math.min(1.0, math.max(0.0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

int _byte(double v) => (math.min(1.0, math.max(0.0, v)) * 255).round();

int _pack(double r, double g, double b) =>
    0xFF000000 | (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);

/// Turns the shard geometry into a single triangle mesh for one frame.
///
/// Shards are sorted back to front, triangles that face away are skipped, and
/// every remaining triangle gets one flat colour.
class ClusterRenderer {
  /// Creates a renderer with buffers sized for [geometry].
  ClusterRenderer(this.geometry)
      : _depth = Float64List(geometry.count),
        _scale = Float64List(geometry.count),
        _hover = Float64List(geometry.count),
        _order = List<int>.generate(geometry.count, (i) => i),
        _positions = Float32List(geometry.count * trianglesPerShard * 6),
        _colors = Int32List(geometry.count * trianglesPerShard * 3);

  /// The shards being drawn.
  final ClusterGeometry geometry;

  final Float64List _depth;
  final Float64List _scale;
  final Float64List _hover;
  final List<int> _order;
  final Float32List _positions;
  final Int32List _colors;

  final Float64List _wx = Float64List(6);
  final Float64List _wy = Float64List(6);
  final Float64List _wz = Float64List(6);
  final Float64List _sx = Float64List(6);
  final Float64List _sy = Float64List(6);

  int _triangleCount = 0;

  /// Triangles in the mesh from the last [build].
  int get triangleCount => _triangleCount;

  /// Builds the mesh for one frame, or null if nothing is visible.
  ui.Vertices? build({
    required double centerX,
    required double centerY,
    required double focal,
    required double distance,
    required double yaw,
    required double pitch,
    required double noiseTime,
    required double scaleMin,
    required double scaleMax,
    required double extrusion,
    required double lift,
    required double hoverX,
    required double hoverY,
    required double hoverZ,
    required double hoverStrength,
    required double reachIn,
    required double reachOut,
    required ui.Color shadow,
    required ui.Color base,
    required ui.Color accent,
  }) {
    final g = geometry;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    // Per shard: depth, noise-driven size, and how close the pointer is.
    for (var i = 0; i < g.count; i++) {
      final cx = g.centroid[i * 3];
      final cy = g.centroid[i * 3 + 1];
      final cz = g.centroid[i * 3 + 2];

      final x1 = cx * cosYaw + cz * sinYaw;
      final z1 = -cx * sinYaw + cz * cosYaw;
      final wy = cy * cosPitch - z1 * sinPitch;
      final wz = cy * sinPitch + z1 * cosPitch;
      _depth[i] = wz;

      final hx = x1 - hoverX;
      final hy = wy - hoverY;
      final hz = wz - hoverZ;
      final near =
          1 - _smoothstep(reachIn, reachOut, math.sqrt(hx * hx + hy * hy + hz * hz));
      final hov = near * hoverStrength;
      _hover[i] = hov;

      final n = math.min(
        1.0,
        math.max(
          0.0,
          gradientNoise2(cy * 1.4 + noiseTime, cz * 1.4 + noiseTime * 0.8) * 0.5 +
              0.5,
        ),
      );
      _scale[i] = scaleMin + (scaleMax - scaleMin) * n + hov * lift;
    }

    // Far shards first, so near ones are painted over them.
    _order.sort((a, b) => _depth[a].compareTo(_depth[b]));

    final shadowR = shadow.r, shadowG = shadow.g, shadowB = shadow.b;
    final baseR = base.r, baseG = base.g, baseB = base.b;
    final accentR = accent.r, accentG = accent.g, accentB = accent.b;

    var vertex = 0;
    for (final shard in _order) {
      final s = _scale[shard];
      final hov = _hover[shard];
      final cx = g.centroid[shard * 3];
      final cy = g.centroid[shard * 3 + 1];
      final cz = g.centroid[shard * 3 + 2];
      final dx = g.direction[shard * 3];
      final dy = g.direction[shard * 3 + 1];
      final dz = g.direction[shard * 3 + 2];

      for (var k = 0; k < 6; k++) {
        final source = k < 3 ? k : k - 3;
        var ox = g.baseOffsets[shard * 9 + source * 3];
        var oy = g.baseOffsets[shard * 9 + source * 3 + 1];
        var oz = g.baseOffsets[shard * 9 + source * 3 + 2];
        if (k >= 3) {
          ox += dx * extrusion;
          oy += dy * extrusion;
          oz += dz * extrusion;
        }
        final px = cx + ox * s;
        final py = cy + oy * s;
        final pz = cz + oz * s;

        final x1 = px * cosYaw + pz * sinYaw;
        final z1 = -px * sinYaw + pz * cosYaw;
        final y2 = py * cosPitch - z1 * sinPitch;
        final z2 = py * sinPitch + z1 * cosPitch;
        _wx[k] = x1;
        _wy[k] = y2;
        _wz[k] = z2;

        final denominator = math.max(0.05, distance - z2);
        _sx[k] = centerX + focal * x1 / denominator;
        _sy[k] = centerY - focal * y2 / denominator;
      }

      for (var t = 0; t < trianglesPerShard; t++) {
        final i0 = shardTriangles[t * 3];
        final i1 = shardTriangles[t * 3 + 1];
        final i2 = shardTriangles[t * 3 + 2];

        final at = (shard * trianglesPerShard + t) * 3;
        final nx0 = g.normals[at];
        final ny0 = g.normals[at + 1];
        final nz0 = g.normals[at + 2];
        final nx = nx0 * cosYaw + nz0 * sinYaw;
        final nz1 = -nx0 * sinYaw + nz0 * cosYaw;
        final ny = ny0 * cosPitch - nz1 * sinPitch;
        final nz = ny0 * sinPitch + nz1 * cosPitch;

        // Skip triangles that face away from the camera at (0, 0, distance).
        final facing =
            nx * -_wx[i0] + ny * -_wy[i0] + nz * (distance - _wz[i0]);
        if (facing <= 0) continue;

        final lam = math.max(0.0, nx * _lightX + ny * _lightY + nz * _lightZ);
        final lit = _smoothstep(0.12, 0.85, lam);
        var r = shadowR + (baseR - shadowR) * lit;
        var gr = shadowG + (baseG - shadowG) * lit;
        var b = shadowB + (baseB - shadowB) * lit;

        if (hov > 0.001) {
          final glow = 0.2 + 0.95 * math.pow(lam, 0.85).toDouble();
          final spec = math.pow(lam, 48).toDouble() * 0.8;
          final mix = math.min(1.0, hov);
          r += (math.min(1.0, accentR * glow + spec) - r) * mix;
          gr += (math.min(1.0, accentG * glow + spec) - gr) * mix;
          b += (math.min(1.0, accentB * glow + spec) - b) * mix;
        }

        final packed = _pack(r, gr, b);
        _positions[vertex * 2] = _sx[i0];
        _positions[vertex * 2 + 1] = _sy[i0];
        _colors[vertex] = packed;
        vertex++;
        _positions[vertex * 2] = _sx[i1];
        _positions[vertex * 2 + 1] = _sy[i1];
        _colors[vertex] = packed;
        vertex++;
        _positions[vertex * 2] = _sx[i2];
        _positions[vertex * 2 + 1] = _sy[i2];
        _colors[vertex] = packed;
        vertex++;
      }
    }

    _triangleCount = vertex ~/ 3;
    if (vertex == 0) return null;
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_positions, 0, vertex * 2),
      colors: Int32List.sublistView(_colors, 0, vertex),
    );
  }
}