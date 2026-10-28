import 'dart:math' as math;
import 'dart:typed_data';

import 'sphere_mesh.dart';

List<double> _unit(List<double> v) {
  final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (length == 0) return <double>[0, 0, 0];
  return <double>[v[0] / length, v[1] / length, v[2] / length];
}

/// One jet of water: where it enters, which way it throws the water, and when.
class _Jet {
  _Jet({
    required this.index,
    required this.weight,
    required this.push,
    required this.flow,
    required this.start,
    required this.end,
    required this.volume,
    required this.speed,
  });

  /// Vertices the jet feeds.
  final Int32List index;

  /// Share of the jet's volume per vertex, so that the weights times the
  /// vertex areas add up to 1.
  final Float64List weight;

  /// How strongly each vertex is pushed, from 0 to 1.
  final Float64List push;

  /// The direction water is thrown at each vertex, 3 values per vertex.
  final Float64List flow;

  /// When the jet starts and ends, as fractions of the fill time.
  final double start;
  final double end;

  /// Total volume the jet delivers.
  final double volume;

  /// How fast the jet throws the water.
  final double speed;

  double added = 0;
}

/// Shallow water flowing over the surface of a sphere.
///
/// Every vertex holds a water thickness and a velocity along the surface.
/// Differences in thickness push the water (like gravity pulling it flat),
/// and water moves between neighbours as flux, so the total volume is
/// conserved. Two jets fill the sphere: the first throws water from the left
/// to the right, then a stronger one throws it back from the right.
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
        _delta = Float64List(mesh.vertexCount),
        _holeIndex = Int32List(mesh.vertexCount),
        _holeWeight = Float64List(mesh.vertexCount),
        _ringIndex = Int32List(mesh.vertexCount),
        _ringWeight = Float64List(mesh.vertexCount) {
    final volume = targetVolume;
    _jets = <_Jet>[
      _buildJet(
        position: <double>[-0.85, 0.05, 0.50],
        target: <double>[1.0, 0.0, 0.2],
        angle: 0.34,
        start: 0.0,
        end: 0.40,
        volume: volume * 0.30,
        speed: 2.2,
      ),
      _buildJet(
        position: <double>[0.80, 0.10, 0.55],
        target: <double>[-1.0, 0.0, 0.2],
        angle: 0.40,
        start: 0.30,
        end: 1.0,
        volume: volume * 0.70,
        speed: 2.8,
      ),
    ];
  }

  /// The sphere the water lives on.
  final SphereMesh mesh;

  /// Thickness the water ends up at once the sphere is full.
  final double targetThickness;

  /// How long the whole filling animation takes.
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
  late final List<_Jet> _jets;
  double _time = 0;

  // The pressed point and the vertices around it.
  final Int32List _holeIndex;
  final Float64List _holeWeight;
  final Int32List _ringIndex;
  final Float64List _ringWeight;
  int _holeCount = 0;
  int _ringCount = 0;
  double _ringTotal = 0;
  bool _pressActive = false;
  double _pressX = 0;
  double _pressY = 0;
  double _pressZ = 1;
  double _pressStrength = 1;

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

  /// Seconds since the filling started.
  double get time => _time;

  /// Whether a jet is still running.
  bool get isFilling => _jets.any((jet) => jet.added < jet.volume - 1e-9);

  /// Slope of the water surface at each vertex, from [computeGradient].
  Float64List get surfaceGradient => _gradient;

  _Jet _buildJet({
    required List<double> position,
    required List<double> target,
    required double angle,
    required double start,
    required double end,
    required double volume,
    required double speed,
  }) {
    final p = _unit(position);
    final t = _unit(target);
    final cosLimit = math.cos(angle);
    final indices = <int>[];
    final weights = <double>[];
    final pushes = <double>[];
    final flows = <double>[];
    var total = 0.0;
    var nearest = 0;
    var nearestDot = -2.0;

    // The direction toward the target, flattened onto the surface at vertex i.
    List<double> flowAt(int i) {
      final x = mesh.position[i * 3];
      final y = mesh.position[i * 3 + 1];
      final z = mesh.position[i * 3 + 2];
      final along = t[0] * x + t[1] * y + t[2] * z;
      final fx = t[0] - along * x;
      final fy = t[1] - along * y;
      final fz = t[2] - along * z;
      final length = math.sqrt(fx * fx + fy * fy + fz * fz);
      if (length < 1e-6) return <double>[0, 0, 0];
      return <double>[fx / length, fy / length, fz / length];
    }

    for (var i = 0; i < mesh.vertexCount; i++) {
      final d = mesh.position[i * 3] * p[0] +
          mesh.position[i * 3 + 1] * p[1] +
          mesh.position[i * 3 + 2] * p[2];
      if (d > nearestDot) {
        nearestDot = d;
        nearest = i;
      }
      if (d <= cosLimit) continue;
      final w = (d - cosLimit) / (1 - cosLimit);
      final smooth = w * w * (3 - 2 * w);
      indices.add(i);
      weights.add(smooth);
      pushes.add(smooth);
      flows.addAll(flowAt(i));
      total += smooth * mesh.area[i];
    }

    if (indices.isEmpty || total <= 0) {
      // A very coarse sphere: use the closest vertex.
      indices
        ..clear()
        ..add(nearest);
      pushes
        ..clear()
        ..add(1);
      flows
        ..clear()
        ..addAll(flowAt(nearest));
      weights
        ..clear()
        ..add(1 / mesh.area[nearest]);
    } else {
      for (var k = 0; k < weights.length; k++) {
        weights[k] /= total;
      }
    }

    return _Jet(
      index: Int32List.fromList(indices),
      weight: Float64List.fromList(weights),
      push: Float64List.fromList(pushes),
      flow: Float64List.fromList(flows),
      start: start,
      end: end,
      volume: volume,
      speed: speed,
    );
  }

  /// Empties the sphere and starts the filling again.
  void reset() {
    height.fillRange(0, height.length, 0);
    velocity.fillRange(0, velocity.length, 0);
    _time = 0;
    for (final jet in _jets) {
      jet.added = 0;
    }
    _pressActive = false;
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

  /// Presses into the water at a point, like stepping into a shallow puddle.
  ///
  /// The water slides away from ([px], [py], [pz]) and piles up in a ring
  /// around it, leaving a dry hole. The press lasts until [clearPress].
  void setPress({
    required double px,
    required double py,
    required double pz,
    required double radius,
    required double strength,
  }) {
    final c = _unit(<double>[px, py, pz]);
    _pressX = c[0];
    _pressY = c[1];
    _pressZ = c[2];
    _pressStrength = strength;

    final cosRadius = math.cos(radius);
    final cosRing = math.cos(radius * 1.8);
    _holeCount = 0;
    _ringCount = 0;
    var ringTotal = 0.0;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final d = mesh.position[i * 3] * _pressX +
          mesh.position[i * 3 + 1] * _pressY +
          mesh.position[i * 3 + 2] * _pressZ;
      if (d > cosRadius) {
        final w = (d - cosRadius) / (1 - cosRadius);
        _holeIndex[_holeCount] = i;
        _holeWeight[_holeCount] = w * w * (3 - 2 * w);
        _holeCount++;
      } else if (d > cosRing) {
        final t = (cosRadius - d) / (cosRadius - cosRing);
        final w = math.sin(math.pi * t);
        _ringIndex[_ringCount] = i;
        _ringWeight[_ringCount] = w;
        _ringCount++;
        ringTotal += w * mesh.area[i];
      }
    }
    _ringTotal = ringTotal;
    _pressActive = _holeCount > 0 && _ringCount > 0 && ringTotal > 0;
  }

  /// Lifts the press. The water flows back into the hole.
  void clearPress() {
    _pressActive = false;
  }

  void _applyPress(double dt) {
    if (!_pressActive) return;
    final m = mesh;
    var removed = 0.0;
    for (var n = 0; n < _holeCount; n++) {
      final i = _holeIndex[n];
      final w = _holeWeight[n];
      final k = i * 3;
      final px = m.position[k];
      final py = m.position[k + 1];
      final pz = m.position[k + 2];
      final d = px * _pressX + py * _pressY + pz * _pressZ;

      // Away from the pressed point, along the surface.
      final ax = d * px - _pressX;
      final ay = d * py - _pressY;
      final az = d * pz - _pressZ;
      final length = math.sqrt(ax * ax + ay * ay + az * az);
      if (length > 1e-6) {
        final blend = math.min(1.0, 10 * dt * w);
        final speed = 4.0 * _pressStrength;
        velocity[k] += (ax / length * speed - velocity[k]) * blend;
        velocity[k + 1] += (ay / length * speed - velocity[k + 1]) * blend;
        velocity[k + 2] += (az / length * speed - velocity[k + 2]) * blend;
      }

      // Move the water out of the way.
      final take = height[i] * (1 - math.exp(-16 * _pressStrength * w * dt));
      height[i] -= take;
      removed += take * m.area[i];
    }

    // It piles up in a ring around the hole.
    if (removed > 0) {
      for (var n = 0; n < _ringCount; n++) {
        height[_ringIndex[n]] += removed * _ringWeight[n] / _ringTotal;
      }
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

    _applyPress(dt);

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
      final available =
          height[source] * m.area[source] * 0.9 / m.valence[source];
      var volume = height[source] * flow * m.edgeWidth[e] * dt;
      if (volume > available) {
        volume = available;
      } else if (volume < -available) {
        volume = -available;
      }
      _delta[a] -= volume / m.area[a];
      _delta[b] += volume / m.area[b];
    }

    // The jets add water and throw it along their direction.
    for (final jet in _jets) {
      final startTime = jet.start * fillSeconds;
      final endTime = jet.end * fillSeconds;
      if (_time < startTime || jet.added >= jet.volume) continue;

      final remaining = jet.volume - jet.added;
      final window = math.max(1e-6, endTime - startTime);
      final amount = _time >= endTime
          ? remaining
          : math.min(remaining, jet.volume / window * dt);
      jet.added += amount;

      for (var n = 0; n < jet.index.length; n++) {
        final i = jet.index[n];
        _delta[i] += amount * jet.weight[n];
        final blend = math.min(1.0, 8 * dt * jet.push[n]);
        final k = i * 3;
        velocity[k] += (jet.flow[n * 3] * jet.speed - velocity[k]) * blend;
        velocity[k + 1] +=
            (jet.flow[n * 3 + 1] * jet.speed - velocity[k + 1]) * blend;
        velocity[k + 2] +=
            (jet.flow[n * 3 + 2] * jet.speed - velocity[k + 2]) * blend;
      }
    }

    for (var i = 0; i < m.vertexCount; i++) {
      height[i] = math.max(0.0, height[i] + _delta[i]);
    }
    _time += dt;
  }
}