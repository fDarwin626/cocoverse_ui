import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double size = 300}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size, height: size, child: child),
      ),
    );

void main() {
  testWidgets('builds, draws frames and exposes its semantic label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const Urchin(semanticLabel: 'Test urchin')),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.bySemanticsLabel('Test urchin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('leans toward a touch and eases back when it is released',
      (tester) async {
    await tester.pumpWidget(_host(const Urchin()));
    await tester.pump(const Duration(milliseconds: 50));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Urchin)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(60, -40));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('works at every quality with two colours and a small size cap',
      (tester) async {
    for (final quality in EffectQuality.values) {
      await tester.pumpWidget(
        _host(
          Urchin(
            colors: const <Color>[Color(0xFF7B5CFF), Color(0xFFFF6FAE)],
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

  testWidgets('clamps out-of-range numbers instead of throwing',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const Urchin(
          lobes: 99,
          petals: -4,
          rings: 99,
          bands: -4,
          sharpness: -5,
          amplitude: 1000,
          morph: 1000,
          tilt: 1000,
          shine: -1,
          glow: 1000,
          lean: 1000,
          scale: 50,
          maxDiameter: 0.5,
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

    await tester.pumpWidget(_host(Urchin(controller: controller)));
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

  testWidgets('stays put when it is not interactive', (tester) async {
    await tester.pumpWidget(_host(const Urchin(interactive: false)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(Urchin), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
