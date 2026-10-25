import 'package:flutter/foundation.dart';

class EffectController extends ChangeNotifier {
  bool _paused = false;
  int _resetCount = 0;

  /// Whether the effect is currently paused.
  bool get isPaused => _paused;

  /// How many times [reset] has been called. Effects use this to detect a reset.
  int get resetCount => _resetCount;

  /// Freezes the animation.
  void pause() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  /// Continues the animation after [pause].
  void resume() {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
  }

  /// Returns the effect to its starting state.
  void reset() {
    _resetCount++;
    notifyListeners();
  }
}