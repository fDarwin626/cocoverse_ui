import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/effects/glass_ring/glass_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds with backdrop text and exposes its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
       MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: GlassRing(
              backdropText: 'TEST',
              semanticLabel: 'Test ring',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.bySemanticsLabel('Test ring'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}