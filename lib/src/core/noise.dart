import 'dart:math' as math;

/// Smooth 2D gradient noise, roughly in the range -1 to 1.
///
/// The same input gives the same output every time, so an effect looks the
/// same on every run.
double gradientNoise2(double x, double y) {
  final xi = x.floor();
  final yi = y.floor();
  final xf = x - xi;
  final yf = y - yi;
  final u = _fade(xf);
  final v = _fade(yf);

  final a = _gradient(xi, yi, xf, yf);
  final b = _gradient(xi + 1, yi, xf - 1, yf);
  final c = _gradient(xi, yi + 1, xf, yf - 1);
  final d = _gradient(xi + 1, yi + 1, xf - 1, yf - 1);

  final bottom = a + (b - a) * u;
  final top = c + (d - c) * u;
  return (bottom + (top - bottom) * v) * 1.4;
}

double _fade(double t) => t * t * (3 - 2 * t);

double _gradient(int ix, int iy, double dx, double dy) {
  final angle = _hash(ix, iy) / 4294967296.0 * 2 * math.pi;
  return math.cos(angle) * dx + math.sin(angle) * dy;
}

int _hash(int x, int y) {
  var h = ((x * 73856093) ^ (y * 19349663) ^ 0x9E3779B9) & 0xFFFFFFFF;
  if (h == 0) h = 0x9E3779B9;
  h ^= (h << 13) & 0xFFFFFFFF;
  h ^= h >> 17;
  h ^= (h << 5) & 0xFFFFFFFF;
  h ^= (h << 13) & 0xFFFFFFFF;
  h ^= h >> 17;
  h ^= (h << 5) & 0xFFFFFFFF;
  return h;
}