import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:cocoverse_ui/src/effects/link_chain/link_chain_motion.dart';
import 'package:cocoverse_ui/src/effects/link_chain/link_chain_rope.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1 / 90;

/// Runs the chain at rest between two fixed ends.
void _settle(
  LinkChainRope rope,
  List<double> a, {
  double gx = 0,
  double gy = -ropeGravity,
  int steps = 300,
}) {
  for (var i = 0; i < steps; i++) {
    rope.step(
      _dt,
      ax0: a[0],
      ay0: a[1],
      az0: 0,
      ax1: a[2],
      ay1: a[3],
      az1: 0,
      gx: gx,
      gy: gy,
    );
  }
}

List<double> _horizontal(LinkChainRope rope, double slack) {
  final gap = rope.ropeLength / (1 + slack);
  return <double>[-gap / 2, 0, gap / 2, 0];
}

void main() {
  group('the rope', () {
    test('keeps its ends fixed and never stretches past the limit', () {
      final rope = LinkChainRope(links: 22);
      final a = _horizontal(rope, 0.10);
      rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
      _settle(rope, a);

      expect(rope.px[0], a[0]);
      expect(rope.py[0], a[1]);
      expect(rope.px[rope.count - 1], a[2]);
      expect(rope.py[rope.count - 1], a[3]);
      expect(rope.longestSegment, lessThanOrEqualTo(rope.maxPitch + 1e-6));
    });

    test('sags about as far as a hanging rope should', () {
      for (final slack in <double>[0.05, 0.10, 0.25]) {
        final rope = LinkChainRope(links: 22);
        final a = _horizontal(rope, slack);
        rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
        _settle(rope, a);

        final gap = a[2] - a[0];
        final expected = math.sqrt(0.375 * gap * (rope.ropeLength - gap));
        expect(-rope.lowest, closeTo(expected, expected * 0.2));
      }
    });

    test('hangs toward wherever gravity points', () {
      final rope = LinkChainRope(links: 22);
      final gap = rope.ropeLength / 1.10;
      final a = <double>[0, gap / 2, 0, -gap / 2];
      rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
      _settle(rope, a, gx: -ropeGravity, gy: 0);

      var leftmost = 0.0;
      var rightmost = 0.0;
      for (var i = 0; i < rope.count; i++) {
        leftmost = math.min(leftmost, rope.px[i]);
        rightmost = math.max(rightmost, rope.px[i]);
      }
      expect(leftmost, lessThan(-2));
      expect(rightmost, lessThan(1));
    });

    test('a diagonal chain sags below its straight line', () {
      final rope = LinkChainRope(links: 14);
      final gap = rope.ropeLength / 1.12;
      final angle = -40 * math.pi / 180;
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      final a = <double>[-dx * gap / 2, -dy * gap / 2, dx * gap / 2, dy * gap / 2];
      rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
      _settle(rope, a);

      final middle = rope.count ~/ 2;
      expect(rope.py[middle], lessThan((a[1] + a[3]) / 2 - 1));
      expect(rope.longestSegment, lessThanOrEqualTo(rope.maxPitch + 1e-6));
    });

    test('lowering the chain in never stretches it past the limit', () {
      final rope = LinkChainRope(links: 22);
      final gap = rope.ropeLength / 1.10;
      final out = (rope.ropeLength - gap) / 2;
      final up = 0.5 * gap;
      rope.seedStraight(-gap / 2 - out, up, 0, gap / 2 + out, up, 0);

      var worst = 0.0;
      var time = 0.0;
      while (time < 2.5) {
        time += _dt;
        final t = math.min(1.0, time / 1.0);
        final k = 1 - t * t * (3 - 2 * t);
        rope.step(
          _dt,
          ax0: -gap / 2 - out * k,
          ay0: up * k,
          az0: 0,
          ax1: gap / 2 + out * k,
          ay1: up * k,
          az1: 0,
          gx: 0,
          gy: -ropeGravity,
        );
        worst = math.max(worst, rope.longestSegment);
      }
      expect(worst, lessThanOrEqualTo(rope.maxPitch + 1e-6));
      expect(-rope.lowest, greaterThan(5));
      expect(rope.px.every((v) => v.isFinite), isTrue);
    });

    test('a grabbed link follows the pull without stretching the chain', () {
      final rope = LinkChainRope(links: 22);
      final a = _horizontal(rope, 0.10);
      rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
      _settle(rope, a);

      final middle = rope.count ~/ 2;
      final before = rope.px[middle];
      for (var i = 0; i < 120; i++) {
        rope.step(
          _dt,
          ax0: a[0],
          ay0: a[1],
          az0: 0,
          ax1: a[2],
          ay1: a[3],
          az1: 0,
          gx: 0,
          gy: -ropeGravity,
          grab: middle,
          grabX: 8,
          grabY: rope.py[middle] + 1,
          grabZ: 0,
          grabPull: 0.35,
        );
      }
      expect(rope.px[middle], greaterThan(before + 1.5));
      expect(rope.longestSegment, lessThanOrEqualTo(rope.maxPitch + 1e-6));
    });

    test('a chain that is let go falls and keeps its spacing', () {
      final rope = LinkChainRope(links: 22);
      final a = _horizontal(rope, 0.10);
      rope.seedHanging(a[0], a[1], 0, a[2], a[3], 0);
      _settle(rope, a);
      final before = rope.lowest;

      for (var i = 0; i < 90; i++) {
        rope.stepFree(_dt, gx: 0, gy: -ropeGravity);
      }
      expect(rope.lowest, lessThan(before - 10));
      expect(rope.longestSegment, closeTo(rope.pitch, 0.25));
    });

    test('the number of links stays between 12 and 40', () {
      expect(LinkChainRope(links: 3).count, minLinkCount);
      expect(LinkChainRope(links: 22).count, 22);
      expect(LinkChainRope(links: 99).count, maxLinkCount);
    });

    test('links that are already apart when straight cannot bend at all', () {
      expect(articulationLimit(1.0, 0.3, 100), 0);
      expect(articulationLimit(1.0, 0.3, 3.2), greaterThan(0.3));
    });
  });

  group('phone motion', () {
    test('upright phone gives normal gravity', () {
      expect(
        LinkChainMotion.gravityFromReading(0, 9.80665),
        const Offset(0, -1),
      );
    });

    test('tilting the phone turns gravity with it', () {
      final right = LinkChainMotion.gravityFromReading(9.80665, 0)!;
      expect(right.dx, closeTo(-1, 1e-9));
      expect(right.dy.abs(), lessThan(1e-9));
    });

    test('a phone lying flat says nothing about which way is down', () {
      expect(LinkChainMotion.gravityFromReading(0, 0), isNull);
      expect(LinkChainMotion.gravityFromReading(double.nan, 1), isNull);
    });

    test('the pull is kept between weak and strong', () {
      final weak = LinkChainMotion.gravityFromReading(0, 1)!;
      expect(weak.distance, closeTo(0.25, 1e-9));
      final strong = LinkChainMotion.gravityFromReading(0, 80)!;
      expect(strong.distance, closeTo(1.5, 1e-9));
    });

    test('readings are smoothed and the shared state can be reset', () {
      final motion = LinkChainMotion.instance;
      motion.debugReset();
      motion.debugFeed(9.80665, 0);
      expect(motion.gravity.value.dx, lessThan(0));
      expect(motion.gravity.value.dx, greaterThan(-1));
      motion.debugReset();
      expect(motion.gravity.value, const Offset(0, -1));
    });

    test('quarter turns rotate the pull', () {
      const down = Offset(0, -1);
      expect(rotateGravity(down, 0), down);
      expect(rotateGravity(down, 1), const Offset(1, 0));
      expect(rotateGravity(down, 2), const Offset(0, 1));
      expect(rotateGravity(down, 3), const Offset(-1, 0));
      expect(rotateGravity(down, 4), down);
      expect(rotateGravity(down, -1), const Offset(-1, 0));
    });
  });
}