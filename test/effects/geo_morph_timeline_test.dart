import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/effects/geo_morph/geo_morph_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

// One shape per second, and a morph that takes half a second, so the numbers
// in these tests are easy to follow.
GeoMorphTimeline _timeline({List<GeoShape>? shapes, GeoShape? start}) =>
    GeoMorphTimeline(
      shapes: shapes,
      stagesPerSecond: 1,
      holdFactor: 5.4,
      morphSeconds: 0.5,
      start: start,
    );

void main() {
  group('auto mode', () {
    test('holds the first shape, then morphs to the next', () {
      final timeline = _timeline();
      expect(timeline.isAuto, isTrue);
      expect(timeline.a, GeoShape.box);
      expect(timeline.b, GeoShape.sphere);
      expect(timeline.blend, 0);

      timeline.advance(0.2);
      expect(timeline.blend, 0);
      expect(timeline.shown, GeoShape.box);

      timeline.advance(0.3);
      expect(timeline.blend, closeTo(0.5, 1e-9));
      expect(timeline.shown, GeoShape.sphere);

      timeline.advance(0.2);
      expect(timeline.blend, 1);
      expect(timeline.shown, GeoShape.sphere);
    });

    test('moves on to the next pair and wraps around the list', () {
      final timeline = _timeline();
      timeline.advance(1.2);
      expect(timeline.a, GeoShape.sphere);
      expect(timeline.b, GeoShape.octahedron);
      expect(timeline.blend, 0);

      timeline.advance(2.8);
      expect(timeline.a, GeoShape.box);
      expect(timeline.b, GeoShape.sphere);
    });

    test('a single shape never morphs', () {
      final timeline = _timeline(shapes: [GeoShape.sphere]);
      timeline.advance(3.3);
      expect(timeline.a, GeoShape.sphere);
      expect(timeline.b, GeoShape.sphere);
      expect(timeline.blend, 0);
    });

    test('an empty list falls back to all four shapes', () {
      final timeline = _timeline(shapes: <GeoShape>[]);
      expect(timeline.shapes, GeoShape.values);
    });
  });

  group('target mode', () {
    test('morphs to a requested shape and then holds it', () {
      final timeline = _timeline();
      timeline.setTarget(GeoShape.torus);
      expect(timeline.isAuto, isFalse);
      expect(timeline.a, GeoShape.box);
      expect(timeline.b, GeoShape.torus);
      expect(timeline.blend, 0);

      timeline.advance(0.25);
      expect(timeline.blend, closeTo(0.5, 1e-9));
      expect(timeline.shown, GeoShape.torus);

      timeline.advance(0.25);
      expect(timeline.a, GeoShape.torus);
      expect(timeline.b, GeoShape.torus);
      expect(timeline.blend, 0);

      timeline.advance(5);
      expect(timeline.shown, GeoShape.torus);
    });

    test('keeps only the latest request while a morph is under way', () {
      final timeline = _timeline();
      timeline.setTarget(GeoShape.torus);
      timeline.advance(0.1);
      timeline.setTarget(GeoShape.sphere);
      expect(timeline.b, GeoShape.torus);

      timeline.advance(0.4);
      expect(timeline.a, GeoShape.torus);
      expect(timeline.b, GeoShape.sphere);
      expect(timeline.blend, 0);

      timeline.advance(0.5);
      expect(timeline.shown, GeoShape.sphere);
      expect(timeline.blend, 0);
    });

    test('starts on the given shape without morphing', () {
      final timeline = _timeline(start: GeoShape.torus);
      expect(timeline.isAuto, isFalse);
      expect(timeline.a, GeoShape.torus);
      expect(timeline.b, GeoShape.torus);
      expect(timeline.blend, 0);
    });

    test('asking for the shape already shown does nothing', () {
      final timeline = _timeline(start: GeoShape.sphere);
      timeline.setTarget(GeoShape.sphere);
      timeline.advance(0.3);
      expect(timeline.a, GeoShape.sphere);
      expect(timeline.blend, 0);
    });
  });

  group('switching between the modes', () {
    test('releasing a shape carries on the cycle from that shape', () {
      final timeline = _timeline(start: GeoShape.torus);
      timeline.setTarget(null);
      expect(timeline.isAuto, isTrue);
      expect(timeline.a, GeoShape.torus);
      expect(timeline.b, GeoShape.box);
      expect(timeline.blend, 0);
    });

    test('goes to the first shape when the shown one is not in the list', () {
      final timeline = _timeline(
        shapes: [GeoShape.box, GeoShape.sphere],
        start: GeoShape.torus,
      );
      timeline.setTarget(null);
      expect(timeline.isAuto, isFalse);
      expect(timeline.b, GeoShape.box);

      timeline.advance(0.5);
      expect(timeline.isAuto, isTrue);
      expect(timeline.a, GeoShape.box);
      expect(timeline.b, GeoShape.sphere);
    });

    test('waits for a half-done auto morph before switching', () {
      final timeline = _timeline();
      timeline.advance(0.5);
      expect(timeline.blend, closeTo(0.5, 1e-9));

      timeline.setTarget(GeoShape.torus);
      expect(timeline.isAuto, isTrue);
      expect(timeline.b, GeoShape.sphere);

      timeline.advance(0.2);
      expect(timeline.isAuto, isFalse);
      expect(timeline.a, GeoShape.sphere);
      expect(timeline.b, GeoShape.torus);
      expect(timeline.blend, 0);

      timeline.advance(0.5);
      expect(timeline.shown, GeoShape.torus);
    });

    test('changing the shape list carries on from the shape on show', () {
      final timeline = _timeline();
      timeline.advance(1.2);
      expect(timeline.shown, GeoShape.sphere);

      timeline.configure(shapes: [GeoShape.torus, GeoShape.sphere]);
      expect(timeline.isAuto, isTrue);
      expect(timeline.a, GeoShape.sphere);
      expect(timeline.b, GeoShape.torus);
    });
  });

  test('reset goes back to the start', () {
    final timeline = _timeline();
    timeline.advance(1.3);
    timeline.reset();
    expect(timeline.isAuto, isTrue);
    expect(timeline.a, GeoShape.box);
    expect(timeline.blend, 0);

    timeline.reset(GeoShape.sphere);
    expect(timeline.isAuto, isFalse);
    expect(timeline.shown, GeoShape.sphere);
  });

  test('ignores time that is not a positive, finite number', () {
    final timeline = _timeline();
    timeline.advance(-1);
    timeline.advance(double.nan);
    timeline.advance(double.infinity);
    expect(timeline.a, GeoShape.box);
    expect(timeline.blend, 0);
  });
}