import 'package:cocoverse_ui/src/effects/particle_cube/cube_model.dart';
import 'package:flutter_test/flutter_test.dart';

Set<int> _keys(CubeModel m) => <int>{
      for (var i = 0; i < m.count; i++)
        (m.x[i] + 100) * 40000 + (m.y[i] + 100) * 200 + (m.z[i] + 100),
    };

void main() {
  test('3 cells with 1 dot per cell gives 26 surface points', () {
    expect(CubeModel(grid: 3, dotsPerCell: 1).count, 26);
  });

  test('the point count follows the shell formula', () {
    final m = CubeModel(grid: 4, dotsPerCell: 3);
    expect(m.axisPoints, 10);
    expect(m.count, 10 * 10 * 10 - 8 * 8 * 8);
  });

  test('a turn moves exactly one layer', () {
    final m = CubeModel(grid: 3, dotsPerCell: 1);
    m.advance(0, 1);
    var moving = 0;
    for (var i = 0; i < m.count; i++) {
      moving += m.member[i];
    }
    expect(moving, anyOf(8, 9));
    expect(m.isTurning, isTrue);
  });

  test('many turns keep every point on the lattice and the surface', () {
    final m = CubeModel(grid: 3, dotsPerCell: 2);
    final before = _keys(m);
    for (var i = 0; i < 400; i++) {
      m.advance(0.05, 0.5);
    }
    expect(m.completedTurns, greaterThan(5));
    expect(_keys(m), before);
  });

  test('reset cancels the turn in progress', () {
    final m = CubeModel(grid: 3, dotsPerCell: 1);
    m.advance(0.1, 1);
    expect(m.isTurning, isTrue);
    m.reset();
    expect(m.isTurning, isFalse);
    expect(m.member.every((v) => v == 0), isTrue);
  });
}