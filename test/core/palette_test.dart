import 'package:cocoverse_ui/src/core/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<Color>> _resolve(WidgetTester tester, List<Color>? colors) async {
  late List<Color> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF111111),
          secondary: Color(0xFF222222),
          tertiary: Color(0xFF333333),
        ),
      ),
      home: Builder(
        builder: (context) {
          result = resolvePalette(context, colors);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('uses the colours that were passed in', (tester) async {
    final result = await _resolve(tester, const [Color(0xFF123456)]);
    expect(result, const [Color(0xFF123456)]);
  });

  testWidgets('falls back to the theme when none are passed', (tester) async {
    final result = await _resolve(tester, null);
    expect(result, const [
      Color(0xFF111111),
      Color(0xFF222222),
      Color(0xFF333333),
    ]);
  });

  testWidgets('an empty list also falls back to the theme', (tester) async {
    final result = await _resolve(tester, const []);
    expect(result.first, const Color(0xFF111111));
  });
}