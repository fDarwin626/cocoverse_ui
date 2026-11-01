import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double size = 300}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size, height: size, child: child),
      ),
    );

Future<void> _pumpFor(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('builds, cycles on its own and exposes its semantic label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const GeoMorph(semanticLabel: 'Test solid')),
    );
    await _pumpFor(tester, 40);

    expect(find.bySemanticsLabel('Test solid'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('reports each shape it shows while cycling', (tester) async {
    final seen = <GeoShape>[];
    await tester.pumpWidget(
      _host(GeoMorph(onShapeChanged: seen.add)),
    );
    await _pumpFor(tester, 60);

    expect(seen.length, greaterThanOrEqualTo(2));
    expect(seen.first, GeoShape.sphere);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holds the shape it is given and morphs when it changes',
      (tester) async {
    final seen = <GeoShape>[];
    await tester.pumpWidget(
      _host(GeoMorph(shape: GeoShape.box, onShapeChanged: seen.add)),
    );
    await _pumpFor(tester, 30);
    expect(seen, isEmpty);

    await tester.pumpWidget(
      _host(GeoMorph(shape: GeoShape.torus, onShapeChanged: seen.add)),
    );
    await _pumpFor(tester, 12);

    expect(seen, <GeoShape>[GeoShape.torus]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('follows the first rule that matches', (tester) async {
    final seen = <GeoShape>[];
    var evening = false;
    await tester.pumpWidget(
      _host(
        GeoMorph(
          ruleInterval: const Duration(milliseconds: 100),
          rules: [
            GeoMorphRule(shape: GeoShape.torus, when: () => evening),
            GeoMorphRule(shape: GeoShape.box, when: () => true),
          ],
          onShapeChanged: seen.add,
        ),
      ),
    );
    await _pumpFor(tester, 20);
    expect(seen, isEmpty);

    evening = true;
    await _pumpFor(tester, 20);

    expect(seen, <GeoShape>[GeoShape.torus]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rule that throws counts as false', (tester) async {
    await tester.pumpWidget(
      _host(
        GeoMorph(
          rules: [
            GeoMorphRule(shape: GeoShape.torus, when: () => throw StateError('no')),
            GeoMorphRule(shape: GeoShape.sphere, when: () => true),
          ],
        ),
      ),
    );
    await _pumpFor(tester, 10);

    expect(tester.takeException(), isNull);
  });

  testWidgets('checks the rules straight away when the notifier fires',
      (tester) async {
    final seen = <GeoShape>[];
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    var evening = false;
    await tester.pumpWidget(
      _host(
        GeoMorph(
          ruleInterval: const Duration(hours: 1),
          refresh: refresh,
          rules: [GeoMorphRule(shape: GeoShape.octahedron, when: () => evening)],
          onShapeChanged: seen.add,
        ),
      ),
    );
    await _pumpFor(tester, 4);

    evening = true;
    refresh.value++;
    await _pumpFor(tester, 12);

    expect(seen, contains(GeoShape.octahedron));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the controller picks, steps through and releases shapes',
      (tester) async {
    final controller = GeoMorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        GeoMorph(
          shapes: const [GeoShape.box, GeoShape.sphere, GeoShape.torus],
          shape: GeoShape.box,
          controller: controller,
        ),
      ),
    );
    await _pumpFor(tester, 4);
    expect(controller.shape, GeoShape.box);

    controller.show(GeoShape.torus);
    await _pumpFor(tester, 12);
    expect(controller.shape, GeoShape.torus);
    expect(controller.pinned, GeoShape.torus);

    controller.next();
    await _pumpFor(tester, 12);
    expect(controller.shape, GeoShape.box);

    controller.previous();
    await _pumpFor(tester, 12);
    expect(controller.shape, GeoShape.torus);

    controller.release();
    expect(controller.pinned, isNull);
    await _pumpFor(tester, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset lets go of a picked shape', (tester) async {
    final controller = GeoMorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(GeoMorph(controller: controller)));
    await _pumpFor(tester, 4);

    controller.show(GeoShape.octahedron);
    await _pumpFor(tester, 12);
    controller.reset();
    await _pumpFor(tester, 4);

    expect(controller.pinned, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pauses, resumes and resets like any other effect',
      (tester) async {
    final controller = GeoMorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(GeoMorph(controller: controller)));
    await _pumpFor(tester, 2);

    controller.pause();
    await _pumpFor(tester, 2);
    controller.resume();
    await _pumpFor(tester, 2);
    controller.reset();
    await _pumpFor(tester, 2);

    expect(tester.takeException(), isNull);
  });

  testWidgets('works with shape colours, at every quality, with orbit off',
      (tester) async {
    for (final quality in EffectQuality.values) {
      await tester.pumpWidget(
        _host(
          GeoMorph(
            orbit: false,
            quality: quality,
            maxDiameter: 120,
            shapeColors: const {
              GeoShape.box: Color(0xFFFF8800),
              GeoShape.torus: Color(0xFF00CCFF),
            },
          ),
        ),
      );
      await _pumpFor(tester, 6);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('turns when dragged and ignores touch when not interactive',
      (tester) async {
    await tester.pumpWidget(_host(const GeoMorph()));
    await _pumpFor(tester, 2);
    await tester.drag(find.byType(GeoMorph), const Offset(60, 30));
    await _pumpFor(tester, 4);

    await tester.pumpWidget(_host(const GeoMorph(interactive: false)));
    await _pumpFor(tester, 2);
    await tester.drag(find.byType(GeoMorph), const Offset(60, 30));
    await _pumpFor(tester, 2);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps out-of-range numbers instead of throwing',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const GeoMorph(
          speed: -3,
          hold: 1000,
          size: 50,
          rimLight: 1000,
          metalness: -4,
          dragSensitivity: 1000,
          maxDiameter: 0.5,
          morphDuration: Duration.zero,
          ruleInterval: Duration.zero,
          shapes: <GeoShape>[],
        ),
      ),
    );
    await _pumpFor(tester, 6);

    expect(tester.takeException(), isNull);
  });
}