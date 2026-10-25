import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:cocoverse_ui/src/core/effect_frame.dart';
import 'package:cocoverse_ui/src/core/effect_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  List<EffectFrame> frames, {
  EffectController? controller,
  bool paused = false,
}) {
  return Center(
    child: SizedBox(
      width: 200,
      height: 200,
      child: EffectHost(
        controller: controller,
        paused: paused,
        onPaint: (canvas, size, frame) => frames.add(frame),
      ),
    ),
  );
}

Future<void> _run(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('time advances while running', (tester) async {
    final frames = <EffectFrame>[];
    await tester.pumpWidget(_host(frames));
    await _run(tester, 10);
    expect(frames.last.time, greaterThan(0.1));
  });

  testWidgets('time stops when paused through the controller', (tester) async {
    final frames = <EffectFrame>[];
    final controller = EffectController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(frames, controller: controller));
    await _run(tester, 5);

    controller.pause();
    await tester.pump();
    final frozen = frames.last.time;
    await _run(tester, 5);
    expect(frames.last.time, frozen);
  });

  testWidgets('reset returns time to zero', (tester) async {
    final frames = <EffectFrame>[];
    final controller = EffectController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(frames, controller: controller));
    await _run(tester, 5);
    expect(frames.last.time, greaterThan(0));

    controller.reset();
    await tester.pump();
    expect(frames.last.time, closeTo(0, 1e-9));
  });

  testWidgets('reduced motion keeps the effect still', (tester) async {
    final frames = <EffectFrame>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(frames),
      ),
    );
    await _run(tester, 5);
    expect(frames, isNotEmpty);
    expect(frames.last.time, 0);
  });

  testWidgets('dragging right turns the effect', (tester) async {
    final frames = <EffectFrame>[];
    await tester.pumpWidget(_host(frames));
    await tester.drag(find.byType(EffectHost), const Offset(100, 0));
    await tester.pump();
    expect(frames.last.yaw, greaterThan(0.3));
  });
}