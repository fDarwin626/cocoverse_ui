import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Tells every [LinkChain] which way is down, from the phone's accelerometer.
///
/// An accelerometer reads the push of the world on the phone: at rest that is
/// the opposite of gravity, and when the phone is shaken or swung it also
/// contains that movement. Turned around, the reading is exactly the pull a
/// hanging chain feels in the phone's own frame. One reading therefore covers
/// both tilting the phone and shaking it.
///
/// The sensor is only open while at least one chain is using it, and every
/// chain shares the one subscription.
class LinkChainMotion {
  LinkChainMotion._();

  /// The one shared source.
  static final LinkChainMotion instance = LinkChainMotion._();

  static const double _standardGravity = 9.80665;

  /// How much of each new reading is taken, from 0 to 1. Lower is smoother.
  static const double _smoothing = 0.2;

  /// Weakest the pull is allowed to get, so a phone lying flat still lets the
  /// chain hang a little instead of floating.
  static const double _weakest = 0.25;

  /// Strongest the pull is allowed to get, so a hard shake cannot fling the
  /// chain further than it can follow.
  static const double _strongest = 1.5;

  /// The direction of down in screen axes, x to the right and y up. Its length
  /// is how hard the pull is, where 1 is the normal pull of a phone held
  /// upright.
  final ValueNotifier<Offset> gravity = ValueNotifier<Offset>(
    const Offset(0, -1),
  );

  int _users = 0;
  StreamSubscription<AccelerometerEvent>? _subscription;

  /// Starts listening if nothing else is. Call [detach] when done.
  void attach() {
    _users++;
    if (_users == 1) _start();
  }

  /// Stops listening once nobody is using the sensor.
  void detach() {
    if (_users == 0) return;
    _users--;
    if (_users == 0) _stop();
  }

  void _start() {
    try {
      _subscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (event) => _onReading(event.x, event.y),
        // No sensor, no permission, or a browser that will not say: the chain
        // simply keeps hanging straight down.
        onError: (Object _) {},
        cancelOnError: false,
      );
    } catch (_) {
      _subscription = null;
    }
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    gravity.value = const Offset(0, -1);
  }

  void _onReading(double ax, double ay) {
    final target = gravityFromReading(ax, ay);
    if (target == null) return;
    gravity.value = Offset.lerp(gravity.value, target, _smoothing)!;
  }

  /// Turns one accelerometer reading, in metres per second squared, into a
  /// pull in screen axes, or null when the reading has no sideways part at
  /// all and so says nothing about which way is down.
  @visibleForTesting
  static Offset? gravityFromReading(double ax, double ay) {
    if (!ax.isFinite || !ay.isFinite) return null;
    final gx = -ax / _standardGravity;
    final gy = -ay / _standardGravity;
    final length = math.sqrt(gx * gx + gy * gy);
    if (length < 0.02) return null;
    final scaled = math.min(_strongest, math.max(_weakest, length));
    return Offset(gx / length * scaled, gy / length * scaled);
  }

  /// Feeds a reading in by hand, for tests.
  @visibleForTesting
  void debugFeed(double ax, double ay) => _onReading(ax, ay);

  /// Puts the shared state back the way it starts, for tests.
  @visibleForTesting
  void debugReset() {
    gravity.value = const Offset(0, -1);
  }
}

/// Turns a pull in screen axes by whole quarter turns, for apps that rotate
/// their screen. One turn is a quarter turn anticlockwise.
Offset rotateGravity(Offset pull, int quarterTurns) {
  switch (quarterTurns % 4) {
    case 1:
      return Offset(-pull.dy, pull.dx);
    case 2:
      return Offset(-pull.dx, -pull.dy);
    case 3:
      return Offset(pull.dy, -pull.dx);
    default:
      return pull;
  }
}