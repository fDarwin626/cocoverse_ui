import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../api/effect_controller.dart';
import '../api/effect_quality.dart';
import 'effect_frame.dart';

/// Shared engine behind every effect widget.
///
/// Handles the ticker, pointer input, drag-to-rotate with inertia, pausing,
/// reduced motion and disposal, so each effect only has to paint a frame.
///
/// Like `Image` or `SizedBox`, it fills the space its parent gives it, so the
/// parent must provide bounded constraints.
class EffectHost extends StatefulWidget {
  /// Creates the host.
  const EffectHost({
    super.key,
    required this.onPaint,
    this.speed = 1.0,
    this.paused = false,
    this.interactive = true,
    this.rotatesOnDrag = true,
    this.dragSensitivity = 1.0,
    this.autoRotate = 0.0,
    this.quality = EffectQuality.high,
    this.controller,
    this.background,
    this.semanticLabel,
  });

  /// Draws one frame.
  final EffectPaintCallback onPaint;

  /// Animation speed multiplier. 1.0 is normal speed.
  final double speed;

  /// Freezes the animation when true.
  final bool paused;

  /// Whether touch, drag and hover affect the effect.
  final bool interactive;

  /// Whether dragging rotates the effect.
  final bool rotatesOnDrag;

  /// How strongly a drag rotates the effect.
  final double dragSensitivity;

  /// Constant spin around the vertical axis, in radians per second at speed 1.
  final double autoRotate;

  /// Requested level of detail.
  final EffectQuality quality;

  /// Optional programmatic control.
  final EffectController? controller;

  /// Fill behind the effect. Null means transparent.
  final Color? background;

  /// Screen-reader description. Null marks the effect as decorative.
  final String? semanticLabel;

  @override
  State<EffectHost> createState() => _EffectHostState();
}

class _EffectHostState extends State<EffectHost>
    with SingleTickerProviderStateMixin {
  static const double _maxPitch = math.pi / 2 - 0.05;
  static const double _twoPi = math.pi * 2;
  static const double _pointerEaseRate = 12;
  static const double _inertiaDecay = 3;
  static const double _radiansPerPixel = 0.008;
  static const double _maxFrameSeconds = 0.05;

  late final Ticker _ticker;
  final _Repaint _repaint = _Repaint();

  Duration _lastElapsed = Duration.zero;
  Duration _lastMoveTime = Duration.zero;
  double _time = 0;
  double _delta = 0;
  double _yaw = 0;
  double _pitch = 0;
  double _yawVelocity = 0;
  double _pitchVelocity = 0;
  bool _dragging = false;
  bool _mouseInside = false;
  Offset? _pointer;
  double _pointerTarget = 0;
  double _pointerStrength = 0;
  bool _reduceMotion = false;
  int _seenResetCount = 0;

  bool get _effectivelyPaused =>
      widget.paused || (widget.controller?.isPaused ?? false) || _reduceMotion;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller?.addListener(_onControllerChanged);
    _seenResetCount = widget.controller?.resetCount ?? 0;
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _syncTicker();
    }
  }

  @override
  void didUpdateWidget(EffectHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _seenResetCount = widget.controller?.resetCount ?? 0;
    }
    if (!widget.interactive) {
      _dragging = false;
      _pointerTarget = 0;
    }
    _syncTicker();
    _repaint.ping();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _syncTicker() {
    if (_effectivelyPaused) {
      if (_ticker.isActive) {
        _ticker.stop();
        _lastElapsed = Duration.zero;
      }
    } else if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller != null && controller.resetCount != _seenResetCount) {
      _seenResetCount = controller.resetCount;
      _resetState();
    }
    _syncTicker();
    _repaint.ping();
  }

  void _resetState() {
    _time = 0;
    _delta = 0;
    _yaw = 0;
    _pitch = 0;
    _yawVelocity = 0;
    _pitchVelocity = 0;
    _dragging = false;
    _pointer = null;
    _pointerTarget = 0;
    _pointerStrength = 0;
  }

  void _onTick(Duration elapsed) {
    final rawDelta = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Clamp so a stalled frame never makes the animation jump.
    final dt = math.min(math.max(rawDelta, 0.0), _maxFrameSeconds);
    _advance(dt);
    _repaint.ping();
  }

  void _advance(double dt) {
    final scaled = dt * widget.speed;
    _delta = scaled;
    _time += scaled;

    if (!_dragging) {
      _yaw += widget.autoRotate * scaled + _yawVelocity * dt;
      _pitch = _clampPitch(_pitch + _pitchVelocity * dt);
      final decay = math.exp(-_inertiaDecay * dt);
      _yawVelocity *= decay;
      _pitchVelocity *= decay;
      if (_yaw > _twoPi || _yaw < -_twoPi) {
        _yaw = _yaw % _twoPi;
      }
    }

    final ease = 1 - math.exp(-_pointerEaseRate * dt);
    _pointerStrength += (_pointerTarget - _pointerStrength) * ease;
  }

  double _clampPitch(double value) =>
      math.min(_maxPitch, math.max(-_maxPitch, value));

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.interactive) return;
    _pointer = event.localPosition;
    _pointerTarget = 1;
    if (widget.rotatesOnDrag) {
      _dragging = true;
      _yawVelocity = 0;
      _pitchVelocity = 0;
      _lastMoveTime = event.timeStamp;
    }
    _repaint.ping();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.interactive) return;
    _pointer = event.localPosition;
    if (_dragging) {
      final k = _radiansPerPixel * widget.dragSensitivity;
      final dYaw = event.delta.dx * k;
      final dPitch = event.delta.dy * k;
      _yaw += dYaw;
      _pitch = _clampPitch(_pitch + dPitch);
      final dtSeconds = math.max(
        (event.timeStamp - _lastMoveTime).inMicroseconds / 1e6,
        1 / 240,
      );
      _lastMoveTime = event.timeStamp;
      // Smooth the release velocity so one noisy event cannot fling the effect.
      _yawVelocity = _yawVelocity * 0.5 + (dYaw / dtSeconds) * 0.5;
      _pitchVelocity = _pitchVelocity * 0.5 + (dPitch / dtSeconds) * 0.5;
    }
    _repaint.ping();
  }

  void _onPointerEnd(PointerEvent _) {
    if (!widget.interactive) return;
    _dragging = false;
    // A mouse keeps hovering after a click. Touch has no hover, so it eases out.
    _pointerTarget = _mouseInside ? 1 : 0;
    _repaint.ping();
  }

  void _onHover(PointerHoverEvent event) {
    if (!widget.interactive) return;
    _mouseInside = true;
    _pointer = event.localPosition;
    _pointerTarget = 1;
    _repaint.ping();
  }

  void _onEnter(PointerEnterEvent event) {
    if (!widget.interactive) return;
    _mouseInside = true;
    _pointer = event.localPosition;
    _pointerTarget = 1;
    _repaint.ping();
  }

  void _onExit(PointerExitEvent event) {
    _mouseInside = false;
    if (!_dragging) _pointerTarget = 0;
    _repaint.ping();
  }

  EffectFrame _readFrame() => EffectFrame(
        time: _time,
        delta: _delta,
        yaw: _yaw,
        pitch: _pitch,
        pointer: _pointer,
        pointerStrength: _pointerStrength,
        quality: widget.quality,
      );

  @override
  Widget build(BuildContext context) {
    Widget child = RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HostPainter(
          readFrame: _readFrame,
          onPaint: widget.onPaint,
          repaint: _repaint,
        ),
      ),
    );

    if (widget.interactive) {
      child = MouseRegion(
        onEnter: _onEnter,
        onHover: _onHover,
        onExit: _onExit,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: child,
        ),
      );
    }

    final background = widget.background;
    if (background != null) {
      child = ColoredBox(color: background, child: child);
    }
    child = ClipRect(child: child);

    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: child);
    return Semantics(label: label, image: true, child: child);
  }
}

/// Notifies the painter that a new frame is needed, without rebuilding widgets.
class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _HostPainter extends CustomPainter {
  _HostPainter({
    required this.readFrame,
    required this.onPaint,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final EffectFrame Function() readFrame;
  final EffectPaintCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint(canvas, size, readFrame());

  @override
  bool shouldRepaint(_HostPainter oldDelegate) =>
      oldDelegate.onPaint != onPaint;
}