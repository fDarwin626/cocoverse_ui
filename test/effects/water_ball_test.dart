import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fills, handles a drag, and exposes its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: WaterBall(semanticLabel: 'Test water'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.drag(find.byType(WaterBall), const Offset(60, 20));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.bySemanticsLabel('Test water'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}