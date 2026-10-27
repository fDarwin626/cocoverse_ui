import 'dart:math' as math;
import 'dart:typed_data';

/// A unit sphere made of triangles, with the neighbour data the water
/// simulation needs: edges, the direction along each edge, and the surface
/// area that belongs to each vertex.
class SphereMesh {
  SphereMesh._({
    required this.vertexCount,
    required this.position,
    required this.triangles,
    required this.edgeA,
    required this.edgeB,
    required this.edgeLength,
    required this.edgeWidth,
    required this.tangentA,
    required this.tangentB,
    required this.valence,
    required this.area,
    required this.minEdge,
  });

  /// Builds a sphere by splitting an icosahedron [subdivisions] times, from 0
  /// to 5. Level 3 has 642 vertices, level 4 has 2562 and level 5 has 10242.
  factory SphereMesh({required int subdivisions}) {
    final level = math.min(5, math.max(0, subdivisions));
    final t = (1 + math.sqrt(5)) / 2;
    final verts = <List<double>>[
      _unit(<double>[-1, t, 0]),
      _unit(<double>[1, t, 0]),
      _unit(<double>[-1, -t, 0]),
      _unit(<double>[1, -t, 0]),
      _unit(<double>[0, -1, t]),
      _unit(<double>[0, 1, t]),
      _unit(<double>[0, -1, -t]),
      _unit(<double>[0, 1, -t]),
      _unit(<double>[t, 0, -1]),
      _unit(<double>[t, 0, 1]),
      _unit(<double>[-t, 0, -1]),
      _unit(<double>[-t, 0, 1]),
    ];
    var tris = <int>[
      0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
      1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
      3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
      4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
    ];

    for (var s = 0; s < level; s++) {
      final cache = <int, int>{};
      int midpoint(int a, int b) {
        final key = a < b ? a * 65536 + b : b * 65536 + a;
        final found = cache[key];
        if (found != null) return found;
        final pa = verts[a];
        final pb = verts[b];
        verts.add(_unit(<double>[
          (pa[0] + pb[0]) / 2,
          (pa[1] + pb[1]) / 2,
          (pa[2] + pb[2]) / 2,
        ]));
        final index = verts.length - 1;
        cache[key] = index;
        return index;
      }

      final next = <int>[];
      for (var i = 0; i < tris.length; i += 3) {
        final a = tris[i];
        final b = tris[i + 1];
        final c = tris[i + 2];
        final ab = midpoint(a, b);
        final bc = midpoint(b, c);
        final ca = midpoint(c, a);
        next.addAll(<int>[a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]);
      }
      tris = next;
    }

    final vertexCount = verts.length;
    final position = Float64List(vertexCount * 3);
    for (var i = 0; i < vertexCount; i++) {
      position[i * 3] = verts[i][0];
      position[i * 3 + 1] = verts[i][1];
      position[i * 3 + 2] = verts[i][2];
    }
    final triangles = Uint16List.fromList(tris);

    // Each edge once.
    final seen = <int>{};
    final listA = <int>[];
    final listB = <int>[];
    void addEdge(int x, int y) {
      final lo = math.min(x, y);
      final hi = math.max(x, y);
      if (seen.add(lo * 65536 + hi)) {
        listA.add(lo);
        listB.add(hi);
      }
    }

    for (var i = 0; i < triangles.length; i += 3) {
      addEdge(triangles[i], triangles[i + 1]);
      addEdge(triangles[i + 1], triangles[i + 2]);
      addEdge(triangles[i + 2], triangles[i]);
    }

    final edgeCount = listA.length;
    final edgeA = Int32List.fromList(listA);
    final edgeB = Int32List.fromList(listB);
    final edgeLength = Float64List(edgeCount);
    final edgeWidth = Float64List(edgeCount);
    final tangentA = Float64List(edgeCount * 3);
    final tangentB = Float64List(edgeCount * 3);
    final valence = Int32List(vertexCount);
    var minEdge = double.infinity;

    for (var e = 0; e < edgeCount; e++) {
      final a = edgeA[e];
      final b = edgeB[e];
      valence[a]++;
      valence[b]++;

      final ax = position[a * 3];
      final ay = position[a * 3 + 1];
      final az = position[a * 3 + 2];
      final bx = position[b * 3];
      final by = position[b * 3 + 1];
      final bz = position[b * 3 + 2];
      final dx = bx - ax;
      final dy = by - ay;
      final dz = bz - az;

      final length = math.sqrt(dx * dx + dy * dy + dz * dz);
      edgeLength[e] = length;
      edgeWidth[e] = length * 0.5774;
      minEdge = math.min(minEdge, length);

      // The direction along the edge at A, flattened onto the surface there.
      final alongA = dx * ax + dy * ay + dz * az;
      _storeUnit(
        tangentA,
        e * 3,
        dx - alongA * ax,
        dy - alongA * ay,
        dz - alongA * az,
      );
      // The direction back along the edge at B.
      final alongB = -(dx * bx + dy * by + dz * bz);
      _storeUnit(
        tangentB,
        e * 3,
        -dx - alongB * bx,
        -dy - alongB * by,
        -dz - alongB * bz,
      );
    }

    // A third of every triangle's area goes to each of its corners.
    final area = Float64List(vertexCount);
    for (var i = 0; i < triangles.length; i += 3) {
      final a = triangles[i] * 3;
      final b = triangles[i + 1] * 3;
      final c = triangles[i + 2] * 3;
      final e1x = position[b] - position[a];
      final e1y = position[b + 1] - position[a + 1];
      final e1z = position[b + 2] - position[a + 2];
      final e2x = position[c] - position[a];
      final e2y = position[c + 1] - position[a + 1];
      final e2z = position[c + 2] - position[a + 2];
      final cx = e1y * e2z - e1z * e2y;
      final cy = e1z * e2x - e1x * e2z;
      final cz = e1x * e2y - e1y * e2x;
      final share = 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz) / 3;
      area[triangles[i]] += share;
      area[triangles[i + 1]] += share;
      area[triangles[i + 2]] += share;
    }

    return SphereMesh._(
      vertexCount: vertexCount,
      position: position,
      triangles: triangles,
      edgeA: edgeA,
      edgeB: edgeB,
      edgeLength: edgeLength,
      edgeWidth: edgeWidth,
      tangentA: tangentA,
      tangentB: tangentB,
      valence: valence,
      area: area,
      minEdge: minEdge,
    );
  }

  /// Number of vertices.
  final int vertexCount;

  /// Position of each vertex on the unit sphere, 3 values per vertex.
  final Float64List position;

  /// Vertex indices of the triangles, 3 per triangle.
  final Uint16List triangles;

  /// First vertex of each edge.
  final Int32List edgeA;

  /// Second vertex of each edge.
  final Int32List edgeB;

  /// Length of each edge.
  final Float64List edgeLength;

  /// Width of the boundary shared by the two vertices of each edge.
  final Float64List edgeWidth;

  /// Unit direction along each edge, as seen at its first vertex.
  final Float64List tangentA;

  /// Unit direction along each edge, as seen at its second vertex, pointing
  /// back toward the first.
  final Float64List tangentB;

  /// Number of edges at each vertex.
  final Int32List valence;

  /// Surface area that belongs to each vertex.
  final Float64List area;

  /// Length of the shortest edge.
  final double minEdge;

  /// Number of edges.
  int get edgeCount => edgeA.length;

  /// Number of triangles.
  int get triangleCount => triangles.length ~/ 3;
}

List<double> _unit(List<double> v) {
  final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (length == 0) return <double>[0, 0, 0];
  return <double>[v[0] / length, v[1] / length, v[2] / length];
}

void _storeUnit(Float64List target, int at, double x, double y, double z) {
  final length = math.sqrt(x * x + y * y + z * z);
  final inverse = length == 0 ? 0.0 : 1 / length;
  target[at] = x * inverse;
  target[at + 1] = y * inverse;
  target[at + 2] = z * inverse;
}