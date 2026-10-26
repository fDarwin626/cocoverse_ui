import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/seeded_random.dart';

/// The points on the surface of a cube lattice, and the Rubik-style turns that
/// shuffle them.
///
/// Coordinates are stored as doubled, centred integers: a lattice index `i`
/// out of `axisPoints` becomes `2 * i - (axisPoints - 1)`. A quarter turn then
/// maps every point to an exact lattice position, so nothing drifts.
class CubeModel {
  CubeModel._({
    required this.grid,
    required this.axisPoints,
    required this.x,
    required this.y,
    required this.z,
  })  : member = Uint8List(x.length),
        _random = SeededRandom(7);

  /// Builds a cube with [grid] cells per edge and [dotsPerCell] dots along
  /// each cell edge. Both are limited to 2 to 8 and 1 to 8.
  factory CubeModel({required int grid, required int dotsPerCell}) {
    final g = math.min(8, math.max(2, grid));
    final d = math.min(8, math.max(1, dotsPerCell));
    final n = math.max(2, (g - 1) * d + 1);

    final xs = <int>[];
    final ys = <int>[];
    final zs = <int>[];
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        for (var k = 0; k < n; k++) {
          final onShell =
              i == 0 || i == n - 1 || j == 0 || j == n - 1 || k == 0 || k == n - 1;
          if (!onShell) continue;
          xs.add(2 * i - (n - 1));
          ys.add(2 * j - (n - 1));
          zs.add(2 * k - (n - 1));
        }
      }
    }
    return CubeModel._(
      grid: g,
      axisPoints: n,
      x: Int16List.fromList(xs),
      y: Int16List.fromList(ys),
      z: Int16List.fromList(zs),
    );
  }

  /// Cells along each edge, which is also the number of layers per axis.
  final int grid;

  /// Lattice points along each edge.
  final int axisPoints;

  /// Doubled, centred x coordinate of every point.
  final Int16List x;

  /// Doubled, centred y coordinate of every point.
  final Int16List y;

  /// Doubled, centred z coordinate of every point.
  final Int16List z;

  /// 1 for every point in the layer that is currently turning, otherwise 0.
  final Uint8List member;

  final SeededRandom _random;
  final List<int> _members = <int>[];

  bool _turning = false;
  int _axis = 0;
  int _layer = 0;
  int _direction = 1;
  int _lastAxis = -1;
  int _lastLayer = -1;
  int _lastDirection = 0;
  double _progress = 0;
  int _completedTurns = 0;

  /// Number of points on the surface.
  int get count => x.length;

  /// Whether a layer is turning right now.
  bool get isTurning => _turning;

  /// The axis of the current turn: 0 for x, 1 for y, 2 for z.
  int get axis => _axis;

  /// How many turns have finished.
  int get completedTurns => _completedTurns;

  /// Current rotation of the turning layer in radians, eased.
  double get turnAngle {
    if (!_turning) return 0;
    final t = math.min(1.0, math.max(0.0, _progress));
    final eased = t < 0.5 ? 4 * t * t * t : 1 - _cube(-2 * t + 2) / 2;
    return _direction * math.pi / 2 * eased;
  }

  double _cube(double v) => v * v * v;

  /// Moves the animation forward by [seconds]. A turn takes [turnSeconds].
  void advance(double seconds, double turnSeconds) {
    if (!_turning) _startTurn();
    _progress += seconds / math.max(0.05, turnSeconds);
    if (_progress >= 1) _commit();
  }

  /// Cancels the turn in progress.
  void reset() {
    member.fillRange(0, member.length, 0);
    _members.clear();
    _turning = false;
    _progress = 0;
  }

  int _bandOf(int doubledCoordinate) {
    final norm = (doubledCoordinate / (axisPoints - 1) + 1) / 2;
    return math.min(grid - 1, math.max(0, (norm * grid).floor()));
  }

  void _startTurn() {
    var axis = 0;
    var layer = 0;
    var direction = 1;
    for (var tries = 0; tries < 8; tries++) {
      axis = _random.nextInt(3);
      layer = _random.nextInt(grid);
      direction = _random.nextInt(2) == 0 ? 1 : -1;
      final undoesLast =
          axis == _lastAxis && layer == _lastLayer && direction == -_lastDirection;
      if (!undoesLast) break;
    }

    member.fillRange(0, member.length, 0);
    _members.clear();
    final source = axis == 0 ? x : (axis == 1 ? y : z);
    for (var i = 0; i < source.length; i++) {
      if (_bandOf(source[i]) == layer) {
        _members.add(i);
        member[i] = 1;
      }
    }

    _axis = axis;
    _layer = layer;
    _direction = direction;
    _progress = 0;
    _turning = true;
  }

  void _commit() {
    final positive = _direction > 0;
    for (final i in _members) {
      final a = x[i];
      final b = y[i];
      final c = z[i];
      switch (_axis) {
        case 0:
          y[i] = positive ? -c : c;
          z[i] = positive ? b : -b;
        case 1:
          x[i] = positive ? c : -c;
          z[i] = positive ? -a : a;
        default:
          x[i] = positive ? -b : b;
          y[i] = positive ? a : -a;
      }
      member[i] = 0;
    }
    _members.clear();
    _lastAxis = _axis;
    _lastLayer = _layer;
    _lastDirection = _direction;
    _turning = false;
    _progress = 0;
    _completedTurns++;
  }
}