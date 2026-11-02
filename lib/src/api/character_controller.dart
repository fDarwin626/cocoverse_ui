import 'effect_controller.dart';

/// Controls a character from code: everything [EffectController] does, plus
/// one-off actions.
///
/// Create one, pass it to a character's `controller` parameter, and dispose it
/// when you are done. Use a plain property, such as a mood, for something that
/// stays true for a while, and these actions for something that just happened.
class CharacterController extends EffectController {
  int _blinks = 0;
  int _shakes = 0;
  int _nods = 0;
  int _bounces = 0;

  /// How many times [blink] has been called. Characters use this to notice it.
  int get blinkCount => _blinks;

  /// How many times [shake] has been called.
  int get shakeCount => _shakes;

  /// How many times [nod] has been called.
  int get nodCount => _nods;

  /// How many times [bounce] has been called.
  int get bounceCount => _bounces;

  /// Makes the character blink once, whatever its own blink setting.
  void blink() {
    _blinks++;
    notifyListeners();
  }

  /// Shakes the character's head, as for a no. For example, a wrong password.
  void shake() {
    _shakes++;
    notifyListeners();
  }

  /// Nods the character's head, as for a yes. For example, an accepted code.
  void nod() {
    _nods++;
    notifyListeners();
  }

  /// Makes the character hop, as for a success.
  void bounce() {
    _bounces++;
    notifyListeners();
  }
}