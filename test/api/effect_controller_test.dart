import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pause, resume and reset notify listeners once per real change', () {
    final controller = EffectController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.pause();
    controller.pause();
    expect(controller.isPaused, isTrue);
    expect(notifications, 1);

    controller.resume();
    controller.resume();
    expect(controller.isPaused, isFalse);
    expect(notifications, 2);

    controller.reset();
    expect(controller.resetCount, 1);
    expect(notifications, 3);

    controller.dispose();
  });
}