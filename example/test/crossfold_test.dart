import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Crossfold builds and animates in a column with text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 200, height: 200, child: Crossfold()),
              Text('Loading'),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Loading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Crossfold paints with every finish, quality and progress',
      (tester) async {
    for (final finish in CrossfoldFinish.values) {
      for (final q in EffectQuality.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 500,
                child: Crossfold(
                  finish: finish,
                  quality: q,
                  progress: 0.5,
                  reverseSpin: true,
                  sideTilt: 20,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
    }
  });
}