import 'package:cocoverse_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app shows its title', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Cocoverse UI example'), findsOneWidget);
  });
}