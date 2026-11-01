import 'dart:math' as math;

import 'geo_morph_types.dart';

/// Decides what [GeoMorph] draws each frame: two shapes and how far the first
/// has become the second.
///
/// It has two modes. In auto mode it walks through a list of shapes, holding
/// each one and then morphing to the next, like the original design. In target
/// mode it holds one shape and morphs to a new one whenever it is asked to.
/// Both modes only change shape when no morph is half done, so the picture
/// never jumps.
class GeoMorphTimeline {
  /// Creates a timeline.
  ///
  /// [stagesPerSecond] is how many shapes pass per second in auto mode,
  /// [holdFactor] is how long each shape holds before it morphs (higher holds
  /// longer and morphs faster), and [morphSeconds] is how long a morph takes in
  /// target mode. With a [start] shape it begins in target mode on that shape.
  GeoMorphTimeline({
    List<GeoShape>? shapes,
    this.stagesPerSecond = 1.0,
    this.holdFactor = 5.4,
    this.morphSeconds = 0.26,
    GeoShape? start,
  }) : _shapes = _cleanShapes(shapes) {
    reset(start);
  }

  /// How many shapes pass per second in auto mode.
  double stagesPerSecond;

  /// How long each shape holds before it morphs. Higher holds longer.
  double holdFactor;

  /// How long a morph takes in target mode, in seconds.
  double morphSeconds;

  List<GeoShape> _shapes;

  bool _auto = true;
  double _autoTime = 0;

  bool _morphing = false;
  double _morphProgress = 0;
  GeoShape _from = GeoShape.box;
  GeoShape _to = GeoShape.box;

  GeoShape? _pending;
  bool _wantAuto = false;

  GeoShape _a = GeoShape.box;
  GeoShape _b = GeoShape.box;
  double _blend = 0;

  /// The first of the two shapes to draw.
  GeoShape get a => _a;

  /// The second of the two shapes to draw.
  GeoShape get b => _b;

  /// How far [a] has become [b], from 0 to 1.
  double get blend => _blend;

  /// The shape that counts as showing right now: [b] once the morph is half
  /// done, otherwise [a].
  GeoShape get shown => _blend >= 0.5 ? _b : _a;

  /// Whether the timeline is walking through its shape list on its own.
  bool get isAuto => _auto;

  /// The shapes auto mode walks through.
  List<GeoShape> get shapes => List<GeoShape>.unmodifiable(_shapes);

  static List<GeoShape> _cleanShapes(List<GeoShape>? shapes) =>
      (shapes == null || shapes.isEmpty)
          ? List<GeoShape>.of(GeoShape.values)
          : List<GeoShape>.of(shapes);

  /// Goes back to the start. With a [start] shape it holds that shape,
  /// otherwise it begins auto mode at the first shape.
  void reset([GeoShape? start]) {
    _pending = null;
    _wantAuto = false;
    _morphing = false;
    _morphProgress = 0;
    _autoTime = 0;
    if (start == null) {
      _auto = true;
      _refreshAuto();
    } else {
      _auto = false;
      _a = start;
      _b = start;
      _blend = 0;
    }
  }

  /// Changes the settings without a visible jump.
  ///
  /// In auto mode the timeline carries on from the shape it is showing, or
  /// morphs to the first shape of the new list if that shape is not in it.
  void configure({
    List<GeoShape>? shapes,
    double? stagesPerSecond,
    double? holdFactor,
    double? morphSeconds,
  }) {
    if (stagesPerSecond != null) this.stagesPerSecond = stagesPerSecond;
    if (holdFactor != null) this.holdFactor = holdFactor;
    if (morphSeconds != null) this.morphSeconds = morphSeconds;
    if (shapes == null) return;
    final cleaned = _cleanShapes(shapes);
    if (_sameShapes(cleaned, _shapes)) return;
    _shapes = cleaned;
    if (_auto) {
      final now = shown;
      _auto = false;
      _a = now;
      _b = now;
      _blend = 0;
      _wantAuto = true;
      _applyRequests();
    }
  }

  static bool _sameShapes(List<GeoShape> x, List<GeoShape> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// Asks for [target] to be shown, or for auto mode again when it is null.
  ///
  /// If a morph is half done it finishes first, and only the latest request is
  /// kept.
  void setTarget(GeoShape? target) {
    if (target == null) {
      _pending = null;
      if (!_auto) _wantAuto = true;
    } else {
      _wantAuto = false;
      _pending = target;
    }
    _applyRequests();
  }

  /// Moves time forward by [seconds].
  void advance(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return;
    if (_auto) {
      _autoTime += seconds * stagesPerSecond;
      _refreshAuto();
    } else if (_morphing) {
      _morphProgress += seconds / math.max(morphSeconds, 0.001);
      if (_morphProgress >= 1) {
        _morphing = false;
        _a = _to;
        _b = _to;
        _blend = 0;
      } else {
        _a = _from;
        _b = _to;
        _blend = _smooth(_morphProgress);
      }
    }
    _applyRequests();
  }

  void _applyRequests() {
    if (_auto) {
      final settled = _blend <= 0 || _blend >= 1;
      final pending = _pending;
      if (pending != null && settled) {
        _pending = null;
        _begin(pending);
      }
    } else if (!_morphing) {
      final pending = _pending;
      if (pending != null) {
        _pending = null;
        _begin(pending);
      } else if (_wantAuto) {
        _wantAuto = false;
        _resumeAuto();
      }
    }
  }

  void _begin(GeoShape target) {
    final from = shown;
    _auto = false;
    if (target == from) {
      _morphing = false;
      _a = from;
      _b = from;
      _blend = 0;
      return;
    }
    _from = from;
    _to = target;
    _morphProgress = 0;
    _morphing = true;
    _a = from;
    _b = target;
    _blend = 0;
  }

  void _resumeAuto() {
    final index = _shapes.indexOf(shown);
    if (index >= 0) {
      _autoTime = index.toDouble();
      _auto = true;
      _refreshAuto();
    } else {
      // The shape on screen is not in the list, so go to the first one and
      // pick auto mode up from there.
      _pending = _shapes.first;
      _wantAuto = true;
      _applyRequests();
    }
  }

  void _refreshAuto() {
    final count = _shapes.length;
    final stage = _autoTime.floor();
    final fraction = _autoTime - stage;
    final index = stage % count;
    _a = _shapes[index];
    if (count == 1) {
      _b = _a;
      _blend = 0;
      return;
    }
    _b = _shapes[(index + 1) % count];
    _blend = _smooth((fraction - 0.5) * holdFactor + 0.5);
  }

  static double _smooth(double x) {
    final c = math.min(1.0, math.max(0.0, x));
    return c * c * (3 - 2 * c);
  }
}