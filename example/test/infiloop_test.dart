import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Infiloop builds, animates and shows its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: Infiloop(child: Text('Hi')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Infiloop paints at every quality, with progress and reverse',
      (tester) async {
    for (final q in EffectQuality.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 500,
              child: Infiloop(
                quality: q,
                progress: 0.5,
                reverse: true,
                angle: 90,
                strands: 160,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });
}