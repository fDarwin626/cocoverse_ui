import 'package:cocoverse_ui/src/effects/water_ball/sphere_mesh.dart';
import 'package:cocoverse_ui/src/effects/water_ball/water_sim.dart';
import 'package:flutter_test/flutter_test.dart';

WaterSim _newSim() => WaterSim(SphereMesh(subdivisions: 3));

void _run(WaterSim sim, double seconds) {
  final frames = (seconds / 0.016).round();
  for (var i = 0; i < frames; i++) {
    sim.advance(0.016);
  }
}

double _spread(WaterSim sim) {
  var lowest = double.infinity;
  var highest = 0.0;
  for (final h in sim.height) {
    if (h < lowest) lowest = h;
    if (h > highest) highest = h;
  }
  return highest - lowest;
}

void main() {
  test('the jet adds exactly the target volume and then stops', () {
    final sim = _newSim();
    expect(sim.totalVolume, 0);
    _run(sim, 7);
    expect(sim.isFilling, isFalse);
    expect(sim.totalVolume, closeTo(sim.targetVolume, 1e-6));
  });

  test('water thickness never goes negative', () {
    final sim = _newSim();
    for (var i = 0; i < 300; i++) {
      sim.advance(0.016);
      for (final h in sim.height) {
        expect(h, greaterThanOrEqualTo(0));
      }
    }
  });

  test('the water spreads out evenly once it has settled', () {
    final sim = _newSim();
    _run(sim, 30);
    expect(_spread(sim), lessThan(0.01));
  });

  test('pushing the water moves it and keeps the volume', () {
    final sim = _newSim();
    _run(sim, 12);
    final before = sim.totalVolume;

    sim.push(
      px: 0,
      py: 0,
      pz: 1,
      vx: 1,
      vy: 0,
      vz: 0,
      radius: 0.5,
      blend: 1,
    );
    var fastest = 0.0;
    for (final v in sim.velocity) {
      if (v.abs() > fastest) fastest = v.abs();
    }
    expect(fastest, greaterThan(0.5));

    _run(sim, 2);
    expect(sim.totalVolume, closeTo(before, 1e-6));
  });

  test('reset empties the water and restarts the jet', () {
    final sim = _newSim();
    _run(sim, 7);
    sim.reset();
    expect(sim.totalVolume, 0);
    expect(sim.isFilling, isTrue);
  });

  test('two runs give identical results', () {
    final a = _newSim();
    final b = _newSim();
    _run(a, 3);
    _run(b, 3);
    for (var i = 0; i < a.height.length; i++) {
      expect(a.height[i], b.height[i]);
    }
  });
}