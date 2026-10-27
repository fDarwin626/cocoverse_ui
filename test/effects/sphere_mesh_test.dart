import 'dart:math' as math;

import 'package:cocoverse_ui/src/effects/water_ball/sphere_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vertex counts follow the subdivision level', () {
    expect(SphereMesh(subdivisions: 0).vertexCount, 12);
    expect(SphereMesh(subdivisions: 1).vertexCount, 42);
    expect(SphereMesh(subdivisions: 2).vertexCount, 162);
    expect(SphereMesh(subdivisions: 3).vertexCount, 642);
    expect(SphereMesh(subdivisions: 4).vertexCount, 2562);
  });

  test('vertices minus edges plus triangles equals 2', () {
    for (var level = 0; level <= 3; level++) {
      final m = SphereMesh(subdivisions: level);
      expect(m.vertexCount - m.edgeCount + m.triangleCount, 2);
    }
  });

  test('every vertex sits on the unit sphere', () {
    final m = SphereMesh(subdivisions: 3);
    for (var i = 0; i < m.vertexCount; i++) {
      final length = math.sqrt(
        math.pow(m.position[i * 3], 2) +
            math.pow(m.position[i * 3 + 1], 2) +
            math.pow(m.position[i * 3 + 2], 2),
      );
      expect(length, closeTo(1, 1e-9));
    }
  });

  test('edge directions are unit length and lie along the surface', () {
    final m = SphereMesh(subdivisions: 2);
    for (var e = 0; e < m.edgeCount; e++) {
      final a = m.edgeA[e];
      final b = m.edgeB[e];
      double dot(List<double> t, int vertex) =>
          t[0] * m.position[vertex * 3] +
          t[1] * m.position[vertex * 3 + 1] +
          t[2] * m.position[vertex * 3 + 2];
      final ta = <double>[
        m.tangentA[e * 3],
        m.tangentA[e * 3 + 1],
        m.tangentA[e * 3 + 2],
      ];
      final tb = <double>[
        m.tangentB[e * 3],
        m.tangentB[e * 3 + 1],
        m.tangentB[e * 3 + 2],
      ];
      expect(math.sqrt(ta[0] * ta[0] + ta[1] * ta[1] + ta[2] * ta[2]),
          closeTo(1, 1e-9));
      expect(math.sqrt(tb[0] * tb[0] + tb[1] * tb[1] + tb[2] * tb[2]),
          closeTo(1, 1e-9));
      expect(dot(ta, a), closeTo(0, 1e-9));
      expect(dot(tb, b), closeTo(0, 1e-9));
    }
  });

  test('the 12 original corners have 5 edges and the rest have 6', () {
    final m = SphereMesh(subdivisions: 3);
    var five = 0;
    for (var i = 0; i < m.vertexCount; i++) {
      if (m.valence[i] == 5) {
        five++;
      } else {
        expect(m.valence[i], 6);
      }
    }
    expect(five, 12);
  });

  test('vertex areas add up to nearly the whole sphere', () {
    final m = SphereMesh(subdivisions: 3);
    var total = 0.0;
    for (var i = 0; i < m.vertexCount; i++) {
      total += m.area[i];
    }
    expect(total, lessThan(4 * math.pi + 1e-9));
    expect(total, greaterThan(0.97 * 4 * math.pi));
    expect(m.minEdge, greaterThan(0));
  });
}