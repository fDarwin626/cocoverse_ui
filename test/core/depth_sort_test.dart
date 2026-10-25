import 'package:cocoverse_ui/src/core/depth_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts the farthest item first', () {
    final order = identityOrder(3);
    sortBackToFront(order, [1.0, 3.0, 2.0]);
    expect(order, [1, 2, 0]);
  });

  test('identityOrder counts from zero', () {
    expect(identityOrder(4), [0, 1, 2, 3]);
  });
}