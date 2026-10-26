import 'dart:math' as math;

import 'package:cocoverse_ui/src/effects/shard_sphere/cluster_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shard count is 20 times density squared', () {
    expect(ClusterGeometry(density: 1).count, 20);
    expect(ClusterGeometry(density: 2).count, 80);
    expect(ClusterGeometry(density: 3).count, 180);
  });

  test('density is limited to 1 through 5', () {
    expect(ClusterGeometry(density: 0).count, 20);
    expect(ClusterGeometry(density: 99).count, 500);
  });

  test('directions and normals are unit length', () {
    final g = ClusterGeometry(density: 2);
    for (var i = 0; i < g.count; i++) {
      final d = math.sqrt(
        math.pow(g.direction[i * 3], 2) +
            math.pow(g.direction[i * 3 + 1], 2) +
            math.pow(g.direction[i * 3 + 2], 2),
      );
      expect(d, closeTo(1, 1e-4));
    }
    for (var i = 0; i < g.count * trianglesPerShard; i++) {
      final n = math.sqrt(
        math.pow(g.normals[i * 3], 2) +
            math.pow(g.normals[i * 3 + 1], 2) +
            math.pow(g.normals[i * 3 + 2], 2),
      );
      expect(n, closeTo(1, 1e-4));
    }
  });

  test('the top faces outward, the base inward, and the sides sideways', () {
    final g = ClusterGeometry(density: 2);
    for (var shard = 0; shard < g.count; shard++) {
      final dx = g.direction[shard * 3];
      final dy = g.direction[shard * 3 + 1];
      final dz = g.direction[shard * 3 + 2];
      double along(int tri) {
        final at = (shard * trianglesPerShard + tri) * 3;
        return g.normals[at] * dx + g.normals[at + 1] * dy + g.normals[at + 2] * dz;
      }

      expect(along(0), lessThan(-0.9));
      expect(along(1), greaterThan(0.9));
      for (var tri = 2; tri < trianglesPerShard; tri++) {
        expect(along(tri).abs(), lessThan(1e-3));
      }
    }
  });
}