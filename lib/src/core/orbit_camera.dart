import 'dart:math' as math;
import 'dart:ui' show Size;

import 'vec3.dart';

/// Where a 3D point lands on screen, plus the data effects need for depth.
class ProjectedPoint {
  /// Creates a projected point.
  const ProjectedPoint({
    required this.x,
    required this.y,
    required this.depth,
    required this.scale,
    required this.facing,
    required this.visible,
  });

  /// Screen x in logical pixels.
  final double x;

  /// Screen y in logical pixels.
  final double y;

  /// Distance from the camera. Larger means farther away.
  final double depth;

  /// Pixels per world unit at this depth. Use it to size shapes.
  final double scale;

  /// Rotated z of the point. Positive faces the viewer, negative faces away.
  final double facing;

  /// False when the point is behind the camera and must not be drawn.
  final bool visible;
}

/// A camera that looks at the origin from [distance], rotated by [yaw] and [pitch].
class OrbitCamera {
  /// Creates a camera. [yaw] and [pitch] are in radians.
  OrbitCamera({
    this.yaw = 0,
    this.pitch = 0,
    this.distance = 4,
    this.fovDegrees = 45,
  })  : _cosYaw = math.cos(yaw),
        _sinYaw = math.sin(yaw),
        _cosPitch = math.cos(pitch),
        _sinPitch = math.sin(pitch),
        _tanHalfFov = math.tan(fovDegrees * math.pi / 360);

  /// Points closer than this to the camera plane count as behind it.
  static const double nearPlane = 0.01;

  /// Rotation around the vertical axis, in radians.
  final double yaw;

  /// Rotation around the horizontal axis, in radians.
  final double pitch;

  /// Distance from the camera to the origin, in world units.
  final double distance;

  /// Vertical field of view, in degrees.
  final double fovDegrees;

  final double _cosYaw;
  final double _sinYaw;
  final double _cosPitch;
  final double _sinPitch;
  final double _tanHalfFov;

  /// Rotates [p] by yaw, then pitch.
  Vec3 rotate(Vec3 p) {
    final x1 = p.x * _cosYaw + p.z * _sinYaw;
    final z1 = -p.x * _sinYaw + p.z * _cosYaw;
    final y2 = p.y * _cosPitch - z1 * _sinPitch;
    final z2 = p.y * _sinPitch + z1 * _cosPitch;
    return Vec3(x1, y2, z2);
  }

  /// Projects [p] onto a viewport of the given [viewport] size.
  ProjectedPoint project(Vec3 p, Size viewport) {
    final r = rotate(p);
    final depth = distance - r.z;
    final visible = depth > nearPlane;
    final focal = viewport.height / 2 / _tanHalfFov;
    final scale = visible ? focal / depth : 0.0;
    return ProjectedPoint(
      x: viewport.width / 2 + r.x * scale,
      y: viewport.height / 2 - r.y * scale,
      depth: depth,
      scale: scale,
      facing: r.z,
      visible: visible,
    );
  }
}