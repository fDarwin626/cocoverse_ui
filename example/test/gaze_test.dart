import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GazeController locks, releases and counts startles', () {
    final c = GazeController();
    expect(c.target, isNull);
    expect(c.isLocked, isFalse);
    c.lookAt(const Offset(5, 6));
    expect(c.target, const Offset(5, 6));
    expect(c.isLocked, isTrue);
    c.release();
    expect(c.target, isNull);
    expect(c.isLocked, isFalse);
    c.startle();
    expect(c.startleCount, 1);
  });

  testWidgets('Gaze builds and follows a mouse across the screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, height: 200, child: Gaze()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(10, 10));
    await gesture.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gaze paints at every quality and obeys its controller',
      (tester) async {
    final controller = GazeController();
    for (final q in EffectQuality.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: Gaze(
                quality: q,
                controller: controller,
                pupilSize: 6,
                follow: GazeFollow.off,
              ),
            ),
          ),
        ),
      );
      controller.lookAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 200));
      controller.startle();
      await tester.pump(const Duration(milliseconds: 200));
      controller.release();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    }
  });
}