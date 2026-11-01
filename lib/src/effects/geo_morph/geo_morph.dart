import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../api/effect_controller.dart';
import '../../api/effect_quality.dart';
import '../../core/effect_frame.dart';
import '../../core/effect_host.dart';
import '../../core/shader_library.dart';
import 'geo_morph_timeline.dart';
import 'geo_morph_types.dart';

export 'geo_morph_types.dart';

const String _shaderAsset = 'packages/cocoverse_ui/shaders/geo_morph.frag';

/// The web original passes its colours to the GPU as linear light and shows
/// them without converting back, which gives deeper, more saturated colours.
/// Keep this true to look the same as the original. Set it to false to use
/// the colours exactly as they are written.
const bool _matchWebColors = true;

// The original's default speed (13) as shapes per second, and as radians per
// second for the turning.
const double _stagesPerSecond = 13 * 0.055;
const double _orbitRate = 13 * 0.055 * 2;

// The original drags 0.007 * 7 radians per pixel and the host uses 0.008.
const double _dragFactor = 0.007 * 7 / 0.008;

// The original starts turned a little, and never tips further than this.
const double _startYaw = 0.5;
const double _startPitch = 0.3;
const double _maxPitch = 1.1;

// The original's camera.
const double _cameraZ = 2.6;
const double _focal = 1.5;

// The original's size: 0.35 + 7 * 0.022, at 100 percent of an 85 percent base.
const double _baseSize = (0.35 + 7 * 0.022) * 100 / 85;

// The sharpness of the highlight in the original.
const double _polish = 6 + 20 * 14;

/// A solid that morphs between a box, a sphere, an octahedron and a torus.
///
/// With no other settings it cycles through the four shapes on its own, which
/// suits a loading screen. You can also choose the shape yourself, either
/// directly with [shape], by condition with [rules], or from code with a
/// [GeoMorphController]. Each shape can have its own colour through
/// [shapeColors].
///
/// ```dart
/// GeoMorph(
///   shapeColors: {
///     GeoShape.box: Colors.orange,
///     GeoShape.torus: Colors.cyan,
///     GeoShape.sphere: Colors.purple,
///   },
///   rules: [
///     GeoMorphRule(shape: GeoShape.box, when: () => DateTime.now().hour < 12),
///     GeoMorphRule(shape: GeoShape.torus, when: () => DateTime.now().hour < 17),
///     GeoMorphRule(shape: GeoShape.sphere, when: () => true),
///   ],
/// )
/// ```
///
/// Drag it to turn it. It fills the space its parent gives it, but is never
/// drawn larger than [maxDiameter]. The area around it is transparent.
class GeoMorph extends StatefulWidget {
  /// Creates a morphing solid.
  const GeoMorph({
    super.key,
    this.color = const Color(0xFF8700FF),
    this.shapeColors,
    this.roomTop = const Color(0xFF4B00FF),
    this.roomBottom = const Color(0xFF000000),
    this.rimColor = const Color(0xFFFFFFFF),
    this.rimLight = 20.0,
    this.metalness = 0.0,
    this.background,
    this.speed = 1.0,
    this.hold = 11.0,
    this.size = 1.0,
    this.orbit = true,
    this.reverseOrbit = false,
    this.dragSensitivity = 1.0,
    this.maxDiameter = 300.0,
    this.shapes,
    this.shape,
    this.rules,
    this.refresh,
    this.ruleInterval = const Duration(seconds: 1),
    this.morphDuration = const Duration(milliseconds: 260),
    this.onShapeChanged,
    this.controller,
    this.paused = false,
    this.interactive = true,
    this.quality = EffectQuality.high,
    this.semanticLabel,
  }) : assert(maxDiameter > 0, 'maxDiameter must be greater than zero');

  /// Colour of the solid. [shapeColors] can override it for single shapes.
  final Color color;

  /// A colour for each shape. Shapes that are not listed use [color]. The
  /// colour blends smoothly while one shape morphs into another.
  final Map<GeoShape, Color>? shapeColors;

  /// Colour the solid reflects from above.
  final Color roomTop;

  /// Colour the solid reflects from below.
  final Color roomBottom;

  /// Colour of the glow around the edges.
  final Color rimColor;

  /// Strength of the glow around the edges, from 0 to 20. 0 turns it off.
  final double rimLight;

  /// How mirror-like the solid is, from 0 (matte) to 20 (a mirror).
  final double metalness;

  /// Fill behind the solid. Null means transparent.
  final Color? background;

  /// Animation speed multiplier. 1.0 matches the original, 0 stops it.
  final double speed;

  /// How long each shape holds before it morphs, from 0 to 20. Higher holds
  /// longer and morphs faster. Only used when it cycles on its own.
  final double hold;

  /// Size of the solid, from 0.2 to 1.4. 1.0 matches the original.
  final double size;

  /// Whether the solid turns on its own. Dragging still works when this is
  /// false, as long as [interactive] is true.
  final bool orbit;

  /// Turns the other way when [orbit] is on.
  final bool reverseOrbit;

  /// How strongly a drag turns the solid. 1.0 matches the original.
  final double dragSensitivity;

  /// The widest the solid is ever drawn, in logical pixels. In a bigger box it
  /// stays this size and sits in the centre. A lower value uses less battery.
  final double maxDiameter;

  /// The shapes it cycles through on its own, in order. Defaults to all four.
  final List<GeoShape>? shapes;

  /// Holds this shape instead of cycling. Changing it morphs to the new shape.
  /// Null cycles through [shapes].
  final GeoShape? shape;

  /// Conditions that choose the shape. The first rule that returns true wins,
  /// and they take priority over [shape]. When none match, [shape] is used, or
  /// the cycle if that is null.
  final List<GeoMorphRule>? rules;

  /// When this notifies, [rules] are checked straight away, not at the next
  /// [ruleInterval].
  final Listenable? refresh;

  /// How often [rules] are checked.
  final Duration ruleInterval;

  /// How long a morph takes when the shape is chosen by [shape], [rules] or the
  /// [controller], at speed 1.0.
  final Duration morphDuration;

  /// Called when the shape on show changes, once the morph is half done.
  final ValueChanged<GeoShape>? onShapeChanged;

  /// Optional control from code. It also pauses, resumes and resets.
  final GeoMorphController? controller;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch and drag affect the solid.
  final bool interactive;

  /// Level of detail. Lower settings take fewer steps per pixel.
  final EffectQuality quality;

  /// Screen-reader description. Null marks the solid as decorative.
  final String? semanticLabel;

  @override
  State<GeoMorph> createState() => _GeoMorphState();
}

/// Controls a [GeoMorph] from code.
///
/// Create one, pass it to [GeoMorph.controller], and dispose it when you are
/// done. Besides pausing, resuming and resetting, it can pick the shape.
/// [reset] also lets go of any shape picked with [show], [next] or [previous].
class GeoMorphController extends EffectController {
  GeoShape? _pinned;
  GeoShape? _shown;
  List<GeoShape>? _order;

  /// The shape on show, or null before the first frame.
  GeoShape? get shape => _shown;

  /// The shape picked with [show], [next] or [previous], or null if none.
  GeoShape? get pinned => _pinned;

  /// Morphs to [shape] and holds it until [release] is called.
  void show(GeoShape shape) {
    _pinned = shape;
    notifyListeners();
  }

  /// Morphs to the shape after the current one in the widget's `shapes` list
  /// and holds it until [release] is called.
  void next() => _step(1);

  /// Morphs to the shape before the current one in the widget's `shapes` list
  /// and holds it until [release] is called.
  void previous() => _step(-1);

  /// Lets go of a shape picked with [show], [next] or [previous], so the
  /// widget's rules, shape or cycle take over again.
  void release() {
    if (_pinned == null) return;
    _pinned = null;
    notifyListeners();
  }

  @override
  void reset() {
    _pinned = null;
    super.reset();
  }

  void _step(int delta) {
    final order = _order;
    final base = _pinned ?? _shown;
    if (order == null || order.isEmpty || base == null) return;
    final index = order.indexOf(base);
    _pinned = index < 0 ? order.first : order[(index + delta) % order.length];
    notifyListeners();
  }
}

class _GeoMorphState extends State<GeoMorph> {
  ui.FragmentShader? _shader;
  Paint? _paint;

  // The settings last written to the shader. They only change when the widget
  // is rebuilt, so they are written once and not on every frame.
  _Settings? _applied;

  late GeoMorphTimeline _timeline;
  GeoShape? _reported;
  double _lastTime = 0;
  int? _lastRuleCheck;
  int _seenResets = 0;

  @override
  void initState() {
    super.initState();
    _timeline = GeoMorphTimeline(
      shapes: widget.shapes,
      stagesPerSecond: _stagesPerSecond,
      holdFactor: _holdFactor(widget.hold),
      morphSeconds: _morphSeconds(widget.morphDuration),
      start: _desiredShape(),
    );
    _reported = _timeline.shown;
    _attachController(widget.controller);
    widget.refresh?.addListener(_retarget);
    _loadShader();
  }

  @override
  void didUpdateWidget(GeoMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_retarget);
      widget.refresh?.addListener(_retarget);
    }
    _timeline.configure(
      shapes: widget.shapes ?? GeoShape.values,
      holdFactor: _holdFactor(widget.hold),
      morphSeconds: _morphSeconds(widget.morphDuration),
    );
    widget.controller?._order = _timeline.shapes;
    _retarget();
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    widget.refresh?.removeListener(_retarget);
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ShaderLibrary.load(_shaderAsset);
      if (!mounted) return;
      final shader = program.fragmentShader();
      setState(() {
        _shader = shader;
        _paint = Paint()..shader = shader;
        _applied = null;
      });
    } catch (error) {
      debugPrint('GeoMorph: could not load its shader: $error');
    }
  }

  void _attachController(GeoMorphController? controller) {
    if (controller == null) return;
    controller.addListener(_onControllerChanged);
    controller._order = _timeline.shapes;
    controller._shown = _timeline.shown;
    _seenResets = controller.resetCount;
  }

  void _detachController(GeoMorphController? controller) {
    if (controller == null) return;
    controller.removeListener(_onControllerChanged);
    controller._order = null;
    controller._shown = null;
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResets) {
      _seenResets = controller.resetCount;
      _timeline.reset(_desiredShape());
      _lastTime = 0;
      _lastRuleCheck = null;
      _reported = _timeline.shown;
      controller._shown = _timeline.shown;
      return;
    }
    _retarget();
  }

  /// Which shape is wanted right now, or null to cycle on its own. A shape
  /// picked from the controller wins, then the first matching rule, then
  /// [GeoMorph.shape].
  GeoShape? _desiredShape() {
    final pinned = widget.controller?._pinned;
    if (pinned != null) return pinned;
    final rules = widget.rules;
    if (rules != null) {
      for (final rule in rules) {
        try {
          if (rule.when()) return rule.shape;
        } catch (error) {
          debugPrint('GeoMorph: a rule threw and counts as false: $error');
        }
      }
    }
    return widget.shape;
  }

  void _retarget() => _timeline.setTarget(_desiredShape());

  void _checkRules() {
    final rules = widget.rules;
    if (rules == null || rules.isEmpty) return;
    final binding = SchedulerBinding.instance;
    // Painting happens in this phase, and only here is the frame time valid.
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) return;
    final now = binding.currentFrameTimeStamp.inMilliseconds;
    final last = _lastRuleCheck;
    if (last == null) {
      _lastRuleCheck = now;
    } else if (now - last >= widget.ruleInterval.inMilliseconds) {
      _lastRuleCheck = now;
      _retarget();
    }
  }

  void _advance(EffectFrame frame) {
    _checkRules();
    // A controller reset sends the host's clock back to zero.
    if (frame.time < _lastTime) _lastTime = 0;
    final dt = frame.time - _lastTime;
    _lastTime = frame.time;
    _timeline.advance(dt);

    final shown = _timeline.shown;
    if (shown != _reported) {
      _reported = shown;
      widget.controller?._shown = shown;
      final callback = widget.onShapeChanged;
      if (callback != null) {
        // Not during painting, so the callback is free to call setState.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) callback(shown);
        });
      }
    }
  }

  double _stepsFor(EffectQuality quality) => switch (quality) {
        EffectQuality.low => 32.0,
        EffectQuality.medium => 56.0,
        EffectQuality.high => 90.0,
      };

  void _paintFrame(Canvas canvas, Size size, EffectFrame frame, _Settings s) {
    _advance(frame);

    final shader = _shader;
    final paint = _paint;
    if (shader == null || paint == null || size.isEmpty) return;
    if (!identical(_applied, s)) {
      _applyStatic(shader, s);
      _applied = s;
    }

    // One height of the original's picture, in pixels. The square drawn is
    // never wider than maxDiameter.
    final square = 2 * (s.reach + 0.01);
    final unit = math.min(size.shortestSide, s.maxDiameter / square);
    final origin = size.center(Offset.zero);

    final colorA = s.colorOf(_timeline.a);
    final colorB = s.colorOf(_timeline.b);
    final blend = _timeline.blend;
    final body = blend <= 0 ? colorA : Color.lerp(colorA, colorB, blend)!;

    final yaw = _startYaw + frame.yaw;
    final pitch = _clamp(_startPitch + frame.pitch, -_maxPitch, _maxPitch);

    shader
      ..setFloat(0, origin.dx)
      ..setFloat(1, origin.dy)
      ..setFloat(2, unit)
      ..setFloat(16, _timeline.a.index.toDouble())
      ..setFloat(17, _timeline.b.index.toDouble())
      ..setFloat(18, blend)
      ..setFloat(23, math.cos(yaw))
      ..setFloat(24, math.sin(yaw))
      ..setFloat(25, math.cos(pitch))
      ..setFloat(26, math.sin(pitch))
      ..setFloat(27, _stepsFor(frame.quality));
    _setColor(shader, 4, body);

    // Only the square around the solid is drawn.
    canvas.drawRect(
      Rect.fromCenter(
        center: origin,
        width: square * unit,
        height: square * unit,
      ),
      paint,
    );
  }

  /// Writes everything that only changes when the widget is rebuilt.
  void _applyStatic(ui.FragmentShader shader, _Settings s) {
    shader
      ..setFloat(3, s.pixel)
      ..setFloat(19, s.size)
      ..setFloat(20, _polish)
      ..setFloat(21, s.metalness)
      ..setFloat(22, s.rim);
    _setColor(shader, 7, s.roomTop);
    _setColor(shader, 10, s.roomBottom);
    _setColor(shader, 13, s.rimColor);
  }

  void _setColor(ui.FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, _channel(color.r))
      ..setFloat(index + 1, _channel(color.g))
      ..setFloat(index + 2, _channel(color.b));
  }

  @override
  Widget build(BuildContext context) {
    final settings = _Settings(
      widget,
      1 / MediaQuery.devicePixelRatioOf(context),
    );
    final direction = widget.reverseOrbit ? -1.0 : 1.0;

    return EffectHost(
      onPaint: (canvas, size, frame) =>
          _paintFrame(canvas, size, frame, settings),
      speed: _clamp(widget.speed, 0, 20),
      paused: widget.paused,
      interactive: widget.interactive,
      dragSensitivity: _dragFactor * widget.dragSensitivity,
      autoRotate: widget.orbit ? _orbitRate * direction : 0.0,
      quality: widget.quality,
      controller: widget.controller,
      background: widget.background,
      semanticLabel: widget.semanticLabel,
    );
  }
}

double _holdFactor(double hold) => 1.0 + _clamp(hold, 0, 20) * 0.4;

double _morphSeconds(Duration duration) =>
    math.max(0.02, duration.inMicroseconds / 1e6);

double _clamp(double value, double low, double high) {
  final safe = value.isFinite ? value : low;
  return math.min(high, math.max(low, safe));
}

double _channel(double value) => _matchWebColors ? _toLinear(value) : value;

double _toLinear(double value) => value <= 0.04045
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

/// The widget's numbers, clamped to sensible ranges and turned into the units
/// the shader uses.
class _Settings {
  _Settings(GeoMorph w, this.pixel)
      : size = _baseSize * _clamp(w.size, 0.2, 1.4),
        metalness = _clamp(w.metalness, 0, 20) / 20,
        rim = _clamp(w.rimLight, 0, 20) * 0.07,
        maxDiameter = math.max(1.0, w.maxDiameter),
        roomTop = w.roomTop,
        roomBottom = w.roomBottom,
        rimColor = w.rimColor,
        _fallback = w.color,
        _byShape = w.shapeColors;

  /// Size of one device pixel in logical pixels.
  final double pixel;

  final double size;
  final double metalness;
  final double rim;
  final double maxDiameter;
  final Color roomTop;
  final Color roomBottom;
  final Color rimColor;
  final Color _fallback;
  final Map<GeoShape, Color>? _byShape;

  /// Colour of the solid while it shows [shape].
  Color colorOf(GeoShape shape) => _byShape?[shape] ?? _fallback;

  /// How far the largest shape reaches on screen, in heights of the picture.
  /// No shape goes past the corner of the box.
  double get reach {
    final radius = 1.36 * size + 0.002;
    return _focal * radius / math.sqrt(_cameraZ * _cameraZ - radius * radius);
  }
}