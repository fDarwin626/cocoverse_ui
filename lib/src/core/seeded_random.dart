/// A small deterministic random generator that behaves the same on every platform.
class SeededRandom {
  /// Creates a generator. The same [seed] always gives the same sequence.
  SeededRandom(int seed)
      : _state = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _state;

  /// The next value in the range 0 (inclusive) to 1 (exclusive).
  double nextDouble() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x / 4294967296.0;
  }

  /// The next value in the range [min] (inclusive) to [max] (exclusive).
  double range(double min, double max) => min + (max - min) * nextDouble();

  /// The next whole number from 0 (inclusive) to [max] (exclusive).
  int nextInt(int max) => (nextDouble() * max).floor();
}