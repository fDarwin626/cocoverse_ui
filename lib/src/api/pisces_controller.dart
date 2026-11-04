import 'effect_controller.dart';

/// A side of the space a fish swims in.
enum PiscesSide {
  /// The top edge.
  top,

  /// The bottom edge.
  bottom,

  /// The left edge.
  left,

  /// The right edge.
  right,
}

/// Controls a Pisces fish: send it across, catch it, or send it to rest.
class PiscesController extends EffectController {
  /// How many times [swim] has been called.
  int swimCount = 0;

  /// How many times [kill] has been called.
  int killCount = 0;

  /// How many times [rest] has been called.
  int restCount = 0;

  /// The side the last [swim] asked the fish to come in from. Null: any.
  PiscesSide? swimFrom;

  /// The side the last [swim] asked the fish to leave by. Null: opposite.
  PiscesSide? swimTo;

  /// Sends the fish across the space, in at [from] and out at [to].
  void swim({PiscesSide? from, PiscesSide? to}) {
    swimFrom = from;
    swimTo = to;
    swimCount++;
    notifyListeners();
  }

  /// Catches the fish: it croaks, floats up and fades out.
  void kill() {
    killCount++;
    notifyListeners();
  }

  /// Sends an idle fish down to rest at the bottom.
  void rest() {
    restCount++;
    notifyListeners();
  }
}