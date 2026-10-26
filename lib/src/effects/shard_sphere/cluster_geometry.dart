import 'dart:math' as math;
import 'dart:typed_data';

/// Triangles of one shard, a triangular prism. Corners 0 to 2 are the base,
/// corners 3 to 5 are the top.
const List<int> shardTriangles = <int>[
  0, 2, 1, // base, faces the centre
  3, 4, 5, // top, faces outward
  0, 1, 4, 0, 4, 3,
  1, 2, 5, 1, 5, 4,
  2, 0, 3, 2, 3, 5,
];

/// Triangles in one shard.
const int trianglesPerShard = 8;

const double _nominalExtrusion = 0.45;

/// Shards laid over an icosphere: 20 faces, each split into `density` squared
/// triangles, each triangle becoming one outward-pointing prism.
class ClusterGeometry {
  ClusterGeometry._({
    required this.count,
    required this.centroid,
    required this.baseOffsets,
    required this.direction,
    required this.normals,
  });

  /// Builds the geometry. [density] is limited to 1 through 5.
  factory ClusterGeometry({required int density}) {
    final cols = math.min(5, math.max(1, density));
    final t = (1 + math.sqrt(5)) / 2;
    final corners = <List<double>>[
      <double>[-1, t, 0],
      <double>[1, t, 0],
      <double>[-1, -t, 0],
      <double>[1, -t, 0],
      <double>[0, -1, t],
      <double>[0, 1, t],
      <double>[0, -1, -t],
      <double>[0, 1, -t],
      <double>[t, 0, -1],
      <double>[t, 0, 1],
      <double>[-t, 0, -1],
      <double>[-t, 0, 1],
    ];
    const faces = <int>[
      0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
      1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
      3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
      4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
    ];

    final shardCount = 20 * cols * cols;
    final centroid = Float32List(shardCount * 3);
    final baseOffsets = Float32List(shardCount * 9);
    final direction = Float32List(shardCount * 3);
    final normals = Float32List(shardCount * trianglesPerShard * 3);
    var shard = 0;

    void addShard(List<double> p0, List<double> p1, List<double> p2) {
      final base = <List<double>>[_unit(p0), _unit(p1), _unit(p2)];
      final cx = (base[0][0] + base[1][0] + base[2][0]) / 3;
      final cy = (base[0][1] + base[1][1] + base[2][1]) / 3;
      final cz = (base[0][2] + base[1][2] + base[2][2]) / 3;
      final dir = _unit(<double>[cx, cy, cz]);

      centroid[shard * 3] = cx;
      centroid[shard * 3 + 1] = cy;
      centroid[shard * 3 + 2] = cz;
      direction[shard * 3] = dir[0];
      direction[shard * 3 + 1] = dir[1];
      direction[shard * 3 + 2] = dir[2];

      // Corner positions relative to the centroid: base first, then the top.
      final corner = <List<double>>[];
      for (var k = 0; k < 3; k++) {
        final o = <double>[base[k][0] - cx, base[k][1] - cy, base[k][2] - cz];
        corner.add(o);
        baseOffsets[shard * 9 + k * 3] = o[0];
        baseOffsets[shard * 9 + k * 3 + 1] = o[1];
        baseOffsets[shard * 9 + k * 3 + 2] = o[2];
      }
      for (var k = 0; k < 3; k++) {
        corner.add(<double>[
          corner[k][0] + dir[0] * _nominalExtrusion,
          corner[k][1] + dir[1] * _nominalExtrusion,
          corner[k][2] + dir[2] * _nominalExtrusion,
        ]);
      }

      final centre = <double>[0, 0, 0];
      for (final c in corner) {
        centre[0] += c[0] / 6;
        centre[1] += c[1] / 6;
        centre[2] += c[2] / 6;
      }

      for (var tri = 0; tri < trianglesPerShard; tri++) {
        final a = corner[shardTriangles[tri * 3]];
        final b = corner[shardTriangles[tri * 3 + 1]];
        final c = corner[shardTriangles[tri * 3 + 2]];
        var n = _unit(_cross(_sub(b, a), _sub(c, a)));
        final mid = <double>[
          (a[0] + b[0] + c[0]) / 3 - centre[0],
          (a[1] + b[1] + c[1]) / 3 - centre[1],
          (a[2] + b[2] + c[2]) / 3 - centre[2],
        ];
        if (n[0] * mid[0] + n[1] * mid[1] + n[2] * mid[2] < 0) {
          n = <double>[-n[0], -n[1], -n[2]];
        }
        final at = (shard * trianglesPerShard + tri) * 3;
        normals[at] = n[0];
        normals[at + 1] = n[1];
        normals[at + 2] = n[2];
      }
      shard++;
    }

    for (var f = 0; f < faces.length; f += 3) {
      final a = corners[faces[f]];
      final b = corners[faces[f + 1]];
      final c = corners[faces[f + 2]];
      List<double> point(int u, int v) => <double>[
            a[0] + ((b[0] - a[0]) * u + (c[0] - a[0]) * v) / cols,
            a[1] + ((b[1] - a[1]) * u + (c[1] - a[1]) * v) / cols,
            a[2] + ((b[2] - a[2]) * u + (c[2] - a[2]) * v) / cols,
          ];
      for (var u = 0; u < cols; u++) {
        for (var v = 0; v + u < cols; v++) {
          addShard(point(u, v), point(u + 1, v), point(u, v + 1));
          if (u + v < cols - 1) {
            addShard(point(u + 1, v), point(u + 1, v + 1), point(u, v + 1));
          }
        }
      }
    }

    return ClusterGeometry._(
      count: shardCount,
      centroid: centroid,
      baseOffsets: baseOffsets,
      direction: direction,
      normals: normals,
    );
  }

  /// Number of shards.
  final int count;

  /// Centre of each shard's base, 3 values per shard.
  final Float32List centroid;

  /// Base corners relative to the centroid, 9 values per shard.
  final Float32List baseOffsets;

  /// Unit vector pointing outward from the centre, 3 values per shard.
  final Float32List direction;

  /// Outward unit normal of each triangle, 3 values per triangle.
  final Float32List normals;
}

List<double> _sub(List<double> a, List<double> b) =>
    <double>[a[0] - b[0], a[1] - b[1], a[2] - b[2]];

List<double> _cross(List<double> a, List<double> b) => <double>[
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

List<double> _unit(List<double> v) {
  final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (length == 0) return <double>[0, 0, 0];
  return <double>[v[0] / length, v[1] / length, v[2] / length];
}