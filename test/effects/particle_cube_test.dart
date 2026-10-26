import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('draws frames, handles a drag, and exposes its label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ParticleCube(semanticLabel: 'Test cube'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.drag(find.byType(ParticleCube), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.bySemanticsLabel('Test cube'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}