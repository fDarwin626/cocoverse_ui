import 'dart:ui';

import 'package:cocoverse_ui/src/effects/shard_sphere/cluster_geometry.dart';
import 'package:cocoverse_ui/src/effects/shard_sphere/cluster_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

Vertices? _build(
  ClusterRenderer renderer, {
  double yaw = 0,
  double hoverStrength = 0,
}) {
  return renderer.build(
    centerX: 150,
    centerY: 150,
    focal: 300,
    distance: 4,
    yaw: yaw,
    pitch: 0.2,
    noiseTime: 1.5,
    scaleMin: 0.15,
    scaleMax: 0.75,
    extrusion: 0.45,
    lift: 0.63,
    hoverX: 0,
    hoverY: 0,
    hoverZ: 1,
    hoverStrength: hoverStrength,
    reachIn: 0.25,
    reachOut: 1,
    shadow: const Color(0xFF5900FF),
    base: const Color(0xFFFFCB00),
    accent: const Color(0xFFFFDE65),
  );
}

void main() {
  test('builds a mesh with fewer triangles than the full set', () {
    final geometry = ClusterGeometry(density: 3);
    final renderer = ClusterRenderer(geometry);
    final vertices = _build(renderer);
    expect(vertices, isNotNull);
    expect(renderer.triangleCount, greaterThan(0));
    expect(renderer.triangleCount, lessThan(geometry.count * trianglesPerShard));
    vertices!.dispose();
  });

  test('turning and hovering still produce meshes', () {
    final renderer = ClusterRenderer(ClusterGeometry(density: 2));
    for (final yaw in <double>[0.0, 1.0, 2.5, -1.7]) {
      final vertices = _build(renderer, yaw: yaw, hoverStrength: 1);
      expect(vertices, isNotNull);
      expect(renderer.triangleCount, greaterThan(0));
      vertices!.dispose();
    }
  });
}