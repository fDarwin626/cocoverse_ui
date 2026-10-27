import 'dart:math' as math;
import 'dart:typed_data';

import 'sphere_mesh.dart';

/// Shallow water flowing over the surface of a sphere.
///
/// Every vertex holds a water thickness and a velocity along the surface.
/// Differences in thickness push the water (like gravity pulling it flat),
/// and water moves between neighbours as flux, so the total volume is
/// conserved. A jet at one spot fills the sphere over [fillSeconds].
class WaterSim {
  /// Creates an empty sphere of water.
  WaterSim(
    this.mesh, {
    this.targetThickness = 0.12,
    this.fillSeconds = 5.0,
    this.gravity = 28.0,
    this.damping = 0.7,
  })  : height = Float64List(mesh.vertexCount),
        velocity = Float64List(mesh.vertexCount * 3),
        _gradient = Float64List(mesh.vertexCount * 3),
        _delta = Float64List(mesh.vertexCount) {
    _buildNozzle();
  }

  // Where the jet enters, as a point on the sphere, and how wide it is.
  static const double _nozzleX = -0.45;
  static const double _nozzleY = 0.40;
  static const double _nozzleZ = 0.80;
  static const double _nozzleAngle = 0.28;

  /// The sphere the water lives on.
  final SphereMesh mesh;

  /// Thickness the water ends up at once the sphere is full.
  final double targetThickness;

  /// How long the jet runs.
  final double fillSeconds;

  /// How strongly thickness differences push the water.
  final double gravity;

  /// How quickly motion dies out, per second.
  final double damping;

  /// Water thickness at each vertex.
  final Float64List height;

  /// Water velocity along the surface, 3 values per vertex.
  final Float64List velocity;

  final Float64List _gradient;
  final Float64List _delta;
  late final Int32List _nozzleIndex;
  late final Float64List _nozzleWeight;
  double _added = 0;

  /// Volume of water once the sphere is full.
  double get targetVolume => 4 * math.pi * targetThickness;

  /// Volume of water in the sphere right now.
  double get totalVolume {
    var total = 0.0;
    for (var i = 0; i < height.length; i++) {
      total += height[i] * mesh.area[i];
    }
    return total;
  }

  /// Whether the jet is still running.
  bool get isFilling => _added < targetVolume;

  /// Slope of the water surface at each vertex, from [computeGradient].
  Float64List get surfaceGradient => _gradient;

  void _buildNozzle() {
    final cosLimit = math.cos(_nozzleAngle);
    final indices = <int>[];
    final weights = <double>[];
    var total = 0.0;
    var nearest = 0;
    var nearestDot = -2.0;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final d = mesh.position[i * 3] * _nozzleX +
          mesh.position[i * 3 + 1] * _nozzleY +
          mesh.position[i * 3 + 2] * _nozzleZ;
      if (d > nearestDot) {
        nearestDot = d;
        nearest = i;
      }
      if (d <= cosLimit) continue;
      final w = (d - cosLimit) / (1 - cosLimit);
      final smooth = w * w * (3 - 2 * w);
      indices.add(i);
      weights.add(smooth);
      total += smooth * mesh.area[i];
    }

    if (indices.isEmpty || total <= 0) {
      // A very coarse sphere: use the closest vertex.
      indices
        ..clear()
        ..add(nearest);
      weights
        ..clear()
        ..add(1 / mesh.area[nearest]);
    } else {
      for (var k = 0; k < weights.length; k++) {
        weights[k] /= total;
      }
    }
    _nozzleIndex = Int32List.fromList(indices);
    _nozzleWeight = Float64List.fromList(weights);
  }

  /// Empties the sphere and starts the jet again.
  void reset() {
    height.fillRange(0, height.length, 0);
    velocity.fillRange(0, velocity.length, 0);
    _added = 0;
  }

  /// Moves the simulation forward by [seconds], in as many small steps as the
  /// current water speed needs to stay stable.
  void advance(double seconds) {
    if (seconds <= 0) return;
    var peak = 0.05;
    for (var i = 0; i < height.length; i++) {
      if (height[i] > peak) peak = height[i];
    }
    final waveSpeed = math.sqrt(gravity * peak);
    final limit = 0.5 * mesh.minEdge / waveSpeed;
    final steps = math.min(12, math.max(1, (seconds / limit).ceil()));
    final dt = seconds / steps;
    for (var s = 0; s < steps; s++) {
      _step(dt);
    }
  }

  /// Fills [surfaceGradient] with the slope of the water surface at every
  /// vertex, as a vector along the sphere's surface.
  void computeGradient() {
    _gradient.fillRange(0, _gradient.length, 0);
    for (var e = 0; e < mesh.edgeCount; e++) {
      final a = mesh.edgeA[e];
      final b = mesh.edgeB[e];
      final slope = (height[b] - height[a]) / mesh.edgeLength[e];
      final t = e * 3;
      _gradient[a * 3] += slope * mesh.tangentA[t];
      _gradient[a * 3 + 1] += slope * mesh.tangentA[t + 1];
      _gradient[a * 3 + 2] += slope * mesh.tangentA[t + 2];
      _gradient[b * 3] -= slope * mesh.tangentB[t];
      _gradient[b * 3 + 1] -= slope * mesh.tangentB[t + 1];
      _gradient[b * 3 + 2] -= slope * mesh.tangentB[t + 2];
    }
    for (var i = 0; i < mesh.vertexCount; i++) {
      final scale = 2 / mesh.valence[i];
      _gradient[i * 3] *= scale;
      _gradient[i * 3 + 1] *= scale;
      _gradient[i * 3 + 2] *= scale;
    }
  }

  /// Drags the water near a point toward a velocity, like a finger sweeping
  /// over it.
  ///
  /// ([px], [py], [pz]) is a point on the unit sphere, ([vx], [vy], [vz]) the
  /// velocity to match, [radius] the angle around the point that is affected,
  /// and [blend] how much of the way the water moves toward that velocity
  /// (0 to 1) at the centre.
  void push({
    required double px,
    required double py,
    required double pz,
    required double vx,
    required double vy,
    required double vz,
    required double radius,
    required double blend,
  }) {
    final cosRadius = math.cos(radius);
    for (var i = 0; i < mesh.vertexCount; i++) {
      final d = mesh.position[i * 3] * px +
          mesh.position[i * 3 + 1] * py +
          mesh.position[i * 3 + 2] * pz;
      if (d <= cosRadius) continue;
      final w = (d - cosRadius) / (1 - cosRadius);
      final b = math.min(1.0, blend * w * w * (3 - 2 * w));
      velocity[i * 3] += (vx - velocity[i * 3]) * b;
      velocity[i * 3 + 1] += (vy - velocity[i * 3 + 1]) * b;
      velocity[i * 3 + 2] += (vz - velocity[i * 3 + 2]) * b;
    }
  }

  void _step(double dt) {
    final m = mesh;
    computeGradient();

    // Thickness differences push the water; motion slowly dies out.
    final decay = math.exp(-damping * dt);
    for (var i = 0; i < m.vertexCount; i++) {
      final k = i * 3;
      final vx = (velocity[k] - gravity * _gradient[k] * dt) * decay;
      final vy = (velocity[k + 1] - gravity * _gradient[k + 1] * dt) * decay;
      final vz = (velocity[k + 2] - gravity * _gradient[k + 2] * dt) * decay;
      // Keep the velocity along the surface.
      final nx = m.position[k];
      final ny = m.position[k + 1];
      final nz = m.position[k + 2];
      final along = vx * nx + vy * ny + vz * nz;
      velocity[k] = vx - along * nx;
      velocity[k + 1] = vy - along * ny;
      velocity[k + 2] = vz - along * nz;
    }

    // Water flows between neighbours. What leaves one vertex arrives at the
    // other, so the volume is conserved.
    _delta.fillRange(0, _delta.length, 0);
    for (var e = 0; e < m.edgeCount; e++) {
      final a = m.edgeA[e];
      final b = m.edgeB[e];
      final t = e * 3;
      final ua = velocity[a * 3] * m.tangentA[t] +
          velocity[a * 3 + 1] * m.tangentA[t + 1] +
          velocity[a * 3 + 2] * m.tangentA[t + 2];
      final ub = velocity[b * 3] * m.tangentB[t] +
          velocity[b * 3 + 1] * m.tangentB[t + 1] +
          velocity[b * 3 + 2] * m.tangentB[t + 2];
      final flow = 0.5 * (ua - ub);

      final source = flow > 0 ? a : b;
      final available = height[source] * m.area[source] * 0.9 / m.valence[source];
      var volume = height[source] * flow * m.edgeWidth[e] * dt;
      if (volume > available) {
        volume = available;
      } else if (volume < -available) {
        volume = -available;
      }
      _delta[a] -= volume / m.area[a];
      _delta[b] += volume / m.area[b];
    }

    // The jet.
    final remaining = targetVolume - _added;
    if (remaining > 0) {
      final volume = math.min(remaining, targetVolume / fillSeconds * dt);
      _added += volume;
      for (var n = 0; n < _nozzleIndex.length; n++) {
        _delta[_nozzleIndex[n]] += volume * _nozzleWeight[n];
      }
    }

    for (var i = 0; i < m.vertexCount; i++) {
      height[i] = math.max(0.0, height[i] + _delta[i]);
    }
  }
}