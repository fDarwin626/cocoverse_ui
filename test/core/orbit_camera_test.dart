import 'dart:math' as math;
import 'dart:ui';

import 'package:cocoverse_ui/src/core/orbit_camera.dart';
import 'package:cocoverse_ui/src/core/vec3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(400, 800);

  test('the origin lands in the centre of the viewport', () {
    final p = OrbitCamera().project(Vec3.zero, size);
    expect(p.x, closeTo(200, 1e-9));
    expect(p.y, closeTo(400, 1e-9));
    expect(p.visible, isTrue);
  });

  test('right is right and up is up on screen', () {
    final camera = OrbitCamera();
    expect(camera.project(const Vec3(1, 0, 0), size).x, greaterThan(200));
    expect(camera.project(const Vec3(0, 1, 0), size).y, lessThan(400));
  });

  test('points nearer the camera appear larger', () {
    final camera = OrbitCamera();
    final near = camera.project(const Vec3(0, 0, 1), size);
    final far = camera.project(const Vec3(0, 0, -1), size);
    expect(near.scale, greaterThan(far.scale));
    expect(near.depth, lessThan(far.depth));
  });

  test('a quarter-turn of yaw sends the x axis away from the viewer', () {
    final r = OrbitCamera(yaw: math.pi / 2).rotate(const Vec3(1, 0, 0));
    expect(r.x, closeTo(0, 1e-9));
    expect(r.z, closeTo(-1, 1e-9));
  });

  test('a point behind the camera is not visible', () {
    final p = OrbitCamera(distance: 4).project(const Vec3(0, 0, 5), size);
    expect(p.visible, isFalse);
  });
}