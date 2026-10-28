import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double size = 400}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size, height: size, child: child),
      ),
    );

void main() {
  testWidgets('builds, draws frames and exposes its semantic label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const FoilRing(semanticLabel: 'Test foil ring')),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.bySemanticsLabel('Test foil ring'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('speeds up and tips toward a touch, then settles on release',
      (tester) async {
    await tester.pumpWidget(_host(const FoilRing()));
    await tester.pump(const Duration(milliseconds: 50));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(FoilRing)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(80, -60));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('works at every quality with custom colours and a size cap',
      (tester) async {
    for (final quality in EffectQuality.values) {
      await tester.pumpWidget(
        _host(
          FoilRing(
            colors: const <Color>[Color(0xFF7B5CFF), Color(0xFFFF6FAE)],
            baseColor: const Color(0xFF222244),
            quality: quality,
            maxDiameter: 120,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('accepts advanced settings', (tester) async {
    await tester.pumpWidget(
      _host(
        const FoilRing(
          twist: 3,
          strokeCount: 40,
          advanced: FoilRingAdvanced(
            lobes: 5,
            rows: 4,
            glint: 80,
            waves: 0,
            seed: 123,
            strokeBlack: Color(0xFF110022),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps out-of-range numbers instead of throwing',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const FoilRing(
          scale: 50,
          twist: 99,
          strokeCount: 100000,
          speed: -3,
          touchResponse: 1000,
          maxDiameter: 0.5,
          advanced: FoilRingAdvanced(
            cycleMs: 0,
            lobes: 99,
            ringRadius: -5,
            tubeRadius: 100000,
            rounding: 500,
            tilt: 1000,
            rows: 0,
            strokeLength: 0,
            strokeWidth: 0,
            exposure: 0,
            lightHeight: 1000,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('pauses, resumes and resets through a controller',
      (tester) async {
    final controller = EffectController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(FoilRing(controller: controller)));
    await tester.pump(const Duration(milliseconds: 50));

    controller.pause();
    await tester.pump(const Duration(milliseconds: 50));
    controller.resume();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    controller.reset();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores touch when it is not interactive', (tester) async {
    await tester.pumpWidget(_host(const FoilRing(interactive: false)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(FoilRing), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}