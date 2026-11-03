import 'dart:math' as math;
import 'dart:typed_data';

// Every length here is in link radii, the way the original measures them.
const double _ring = 1.0;

/// Fewest links a chain can have and still hang without coming apart.
const int minLinkCount = 12;

/// Most links the shader can draw.
const int maxLinkCount = 40;

const double _clampMargin = 0.20;
const double _bendSafety = 0.60;
const int _relaxPasses = 14;
const int _clampPasses = 8;
const int _threadPasses = 6;
const double _threadFloor = 0.05;
const double _threadGain = 1.0;
const double _threadStep = 0.15;
const double _damping = 0.985;

/// How the chain's own weight pulls, in link radii per second squared.
const double ropeGravity = 26.0;

/// The bend at which two neighbouring links stop being linked, in radians.
///
/// Holding the segment length alone is not enough to keep a chain together,
/// because a kink tilts each link away from the segment joining them until the
/// near cap of one no longer passes through the hole of the other. This is the
/// exact angle where that happens for links with the given measures.
double articulationLimit(double le, double r2, double seg) {
  final reach = le + _ring;
  final hole = _ring - r2;
  double clearance(double th) {
    final x = seg * math.sin(th * 0.5) - reach * math.sin(th);
    final y = seg * math.cos(th * 0.5) - reach * math.cos(th);
    final v = math.max(y.abs() - le, 0.0);
    return hole - math.sqrt(x * x + v * v);
  }

  if (clearance(0) <= 0) return 0;
  var lo = 0.0;
  var hi = math.pi;
  for (var k = 0; k < 24; k++) {
    final m = (lo + hi) * 0.5;
    if (clearance(m) > 0) {
      lo = m;
    } else {
      hi = m;
    }
  }
  return lo;
}

/// A chain of links on a rope that cannot stretch past the point where its
/// links would come apart, and cannot bend so sharply that they would unlink.
class LinkChainRope {
  /// Creates a rope of [links] links. [linkLength] and [linkThickness] are
  /// percentages, as in the original.
  LinkChainRope({
    required int links,
    double linkLength = 58,
    double linkThickness = 36,
  })  : count = math.min(maxLinkCount, math.max(minLinkCount, links)),
        px = Float64List(maxLinkCount),
        py = Float64List(maxLinkCount),
        pz = Float64List(maxLinkCount),
        ox = Float64List(maxLinkCount),
        oy = Float64List(maxLinkCount),
        oz = Float64List(maxLinkCount),
        _snapX = Float64List(maxLinkCount),
        _snapY = Float64List(maxLinkCount),
        _snapZ = Float64List(maxLinkCount),
        _tanX = Float64List(maxLinkCount),
        _tanY = Float64List(maxLinkCount),
        _tanZ = Float64List(maxLinkCount) {
    double unit(double v) => math.min(1.0, math.max(0.0, v));
    le = (0.30 + unit(linkLength / 100) * 1.20) * _ring;
    r2 = (0.14 + unit(linkThickness / 100) * 0.34) * _ring;
    // The pitch that guarantees interlock, and the length past which two links
    // come apart.
    pitch = 2 * (le + _ring - r2) - 0.25 * _ring;
    maxPitch = 2 * (le + _ring - r2) - _clampMargin * _ring;
    _cosMaxBend =
        math.cos(articulationLimit(le, r2, maxPitch) * _bendSafety);
    ropeLength = pitch * (count - 1);
    _separation = (_ring + r2) * 1.35;
  }

  /// Number of links.
  final int count;

  /// Half the straight run of a link.
  late final double le;

  /// Tube radius of a link.
  late final double r2;

  /// Distance between link centres at rest.
  late final double pitch;

  /// Distance past which two links come apart. Never exceeded.
  late final double maxPitch;

  /// Length of the whole rope.
  late final double ropeLength;

  /// Radius of the ball that holds one link.
  double get bound => le + _ring + r2;

  /// Link positions and where they were one step ago.
  final Float64List px, py, pz, ox, oy, oz;

  late final double _cosMaxBend;
  late final double _separation;

  final Float64List _snapX, _snapY, _snapZ;
  final Float64List _tanX, _tanY, _tanZ;

  double _a0x = 0, _a0y = 0, _a0z = 0, _a1x = 0, _a1y = 0, _a1z = 0;

  /// Lays the chain out straight between two points, with no slack.
  void seedStraight(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
  ) {
    for (var i = 0; i < count; i++) {
      final k = i / (count - 1);
      px[i] = x0 + (x1 - x0) * k;
      py[i] = y0 + (y1 - y0) * k;
      pz[i] = z0 + (z1 - z0) * k;
      ox[i] = px[i];
      oy[i] = py[i];
      oz[i] = pz[i];
    }
  }

  /// Lays the chain out as a clean V hanging between two points.
  void seedHanging(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
  ) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    final dz = z1 - z0;
    final gap = math.sqrt(dx * dx + dy * dy + dz * dz);
    final hang = math.sqrt(math.max(ropeLength * ropeLength - gap * gap, 0.01)) / 2;
    final mx = (x0 + x1) / 2;
    final my = (y0 + y1) / 2 - hang;
    final mz = (z0 + z1) / 2;
    final half = (count - 1) / 2;
    for (var i = 0; i < count; i++) {
      if (i <= half) {
        final k = i / half;
        px[i] = x0 + (mx - x0) * k;
        py[i] = y0 + (my - y0) * k;
        pz[i] = z0 + (mz - z0) * k;
      } else {
        final k = (i - half) / half;
        px[i] = mx + (x1 - mx) * k;
        py[i] = my + (y1 - my) * k;
        pz[i] = mz + (z1 - mz) * k;
      }
      ox[i] = px[i];
      oy[i] = py[i];
      oz[i] = pz[i];
    }
  }

  /// The longest gap between two neighbouring links right now.
  double get longestSegment {
    var longest = 0.0;
    for (var i = 0; i < count - 1; i++) {
      final dx = px[i + 1] - px[i];
      final dy = py[i + 1] - py[i];
      final dz = pz[i + 1] - pz[i];
      longest = math.max(longest, math.sqrt(dx * dx + dy * dy + dz * dz));
    }
    return longest;
  }

  /// Height of the lowest link.
  double get lowest {
    var low = double.infinity;
    for (var i = 0; i < count; i++) {
      low = math.min(low, py[i]);
    }
    return low;
  }

  /// Moves the chain on by one fixed step of [dt] seconds, with both ends held
  /// at the given points. [gx] and [gy] are the pull of gravity. When [grab]
  /// is a link number, that link is pulled toward the grab point by
  /// [grabPull], which is a fraction from 0 to 1.
  void step(
    double dt, {
    required double ax0,
    required double ay0,
    required double az0,
    required double ax1,
    required double ay1,
    required double az1,
    required double gx,
    required double gy,
    int grab = -1,
    double grabX = 0,
    double grabY = 0,
    double grabZ = 0,
    double grabPull = 0,
  }) {
    final n = count;
    _a0x = ax0;
    _a0y = ay0;
    _a0z = az0;
    _a1x = ax1;
    _a1y = ay1;
    _a1z = az1;

    final gdx = gx * dt * dt;
    final gdy = gy * dt * dt;
    for (var i = 0; i < n; i++) {
      final cx = px[i];
      final cy = py[i];
      final cz = pz[i];
      px[i] = cx + (cx - ox[i]) * _damping + gdx;
      py[i] = cy + (cy - oy[i]) * _damping + gdy;
      pz[i] = cz + (cz - oz[i]) * _damping;
      ox[i] = cx;
      oy[i] = cy;
      oz[i] = cz;
    }

    // The grabbed link is pulled, never pinned, so the chain's weight can
    // argue back and release throws it at the speed it was moving. The pull
    // point is first brought inside the reach of both ends, so the spring only
    // ever asks for something the chain can do.
    var tgX = grabX;
    var tgY = grabY;
    var tgZ = grabZ;
    final grabbing = grab > 0 && grab < n - 1;
    if (grabbing) {
      for (var rep = 0; rep < 4; rep++) {
        for (var e = 0; e < 2; e++) {
          final ax = e == 0 ? ax0 : ax1;
          final ay = e == 0 ? ay0 : ay1;
          final az = e == 0 ? az0 : az1;
          final reach = pitch * (e == 0 ? grab : n - 1 - grab) * 0.985;
          final dx = tgX - ax;
          final dy = tgY - ay;
          final dz = tgZ - az;
          final d = math.sqrt(dx * dx + dy * dy + dz * dz);
          final safe = d < 1e-6 ? 1e-6 : d;
          if (safe <= reach) continue;
          final sc = reach / safe;
          tgX = ax + dx * sc;
          tgY = ay + dy * sc;
          tgZ = az + dz * sc;
        }
      }
      px[grab] += (tgX - px[grab]) * grabPull;
      py[grab] += (tgY - py[grab]) * grabPull;
      pz[grab] += (tgZ - pz[grab]) * grabPull;
    }

    for (var pass = 0; pass < _relaxPasses; pass++) {
      _pin();
      for (var i = 0; i < n - 1; i++) {
        final j = i + 1;
        var dx = px[j] - px[i];
        var dy = py[j] - py[i];
        var dz = pz[j] - pz[i];
        final len = math.sqrt(dx * dx + dy * dy + dz * dz);
        final d = len < 1e-6 ? 1e-6 : len;
        final k = ((d - pitch) / d) * 0.5;
        dx *= k;
        dy *= k;
        dz *= k;
        if (i != 0) {
          px[i] += dx;
          py[i] += dy;
          pz[i] += dz;
        }
        if (j != n - 1) {
          px[j] -= dx;
          py[j] -= dy;
          pz[j] -= dz;
        }
      }

      if (grabbing) {
        final k = grabPull * 0.5;
        px[grab] += (tgX - px[grab]) * k;
        py[grab] += (tgY - py[grab]) * k;
        pz[grab] += (tgZ - pz[grab]) * k;
      }

      // Light self-repulsion every third pass, so the bight piles up instead of
      // passing through itself.
      if (pass % 3 == 0) {
        final sepSq = _separation * _separation;
        for (var i = 0; i < n; i++) {
          for (var j = i + 2; j < n; j++) {
            var dx = px[j] - px[i];
            var dy = py[j] - py[i];
            var dz = pz[j] - pz[i];
            final d2 = dx * dx + dy * dy + dz * dz;
            if (d2 > sepSq || d2 < 1e-9) continue;
            final d = math.sqrt(d2);
            final k = ((_separation - d) / d) * 0.28;
            dx *= k;
            dy *= k;
            dz *= k;
            if (i != 0 && i != n - 1) {
              px[i] -= dx;
              py[i] -= dy;
              pz[i] -= dz;
            }
            if (j != 0 && j != n - 1) {
              px[j] += dx;
              py[j] += dy;
              pz[j] += dz;
            }
          }
        }
      }
    }

    // From here on the chain is projected, not sprung: position is set and
    // velocity is left alone, which is why the whole projection is carried
    // into the old positions at the end.
    for (var i = 0; i < n; i++) {
      _snapX[i] = px[i];
      _snapY[i] = py[i];
      _snapZ[i] = pz[i];
    }

    for (var rep = 0; rep < _clampPasses; rep++) {
      _walk(true);
    }

    // Answer the measured threading clearance. Only pairs actually losing
    // their thread are touched.
    for (var rep = 0; rep < _threadPasses; rep++) {
      _pin();
      _tangents();
      var touched = false;
      for (var i = 0; i < n - 1; i++) {
        final deficit = _threadFloor - _clearance(i, i + 1);
        if (deficit <= 0) continue;
        touched = true;
        var push = deficit * _threadGain;
        if (push > _threadStep * maxPitch) push = _threadStep * maxPitch;
        _straighten(i, push);
        _straighten(i + 1, push);
      }
      if (!touched) break;
      _walk(false);
    }

    _walk(false);

    // Share the snap between the two links of each remaining over-long gap.
    _pin();
    for (var i = 0; i < n - 1; i++) {
      final j = i + 1;
      final pinI = i == 0;
      final pinJ = j == n - 1;
      if (pinI && pinJ) continue;
      var dx = px[j] - px[i];
      var dy = py[j] - py[i];
      var dz = pz[j] - pz[i];
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      final d = len < 1e-6 ? 1e-6 : len;
      if (d <= maxPitch) continue;
      final k = ((d - maxPitch) / d) * (pinI || pinJ ? 1.0 : 0.5);
      dx *= k;
      dy *= k;
      dz *= k;
      if (!pinI) {
        px[i] += dx;
        py[i] += dy;
        pz[i] += dz;
      }
      if (!pinJ) {
        px[j] -= dx;
        py[j] -= dy;
        pz[j] -= dz;
      }
    }

    for (var i = 0; i < n; i++) {
      ox[i] += px[i] - _snapX[i];
      oy[i] += py[i] - _snapY[i];
      oz[i] += pz[i] - _snapZ[i];
    }
  }

  /// One step with both ends loose, for a chain that has been let go.
  void stepFree(double dt, {required double gx, required double gy}) {
    final n = count;
    for (var i = 0; i < n; i++) {
      final cx = px[i];
      final cy = py[i];
      final cz = pz[i];
      px[i] = cx + (cx - ox[i]) * 0.995 + gx * dt * dt;
      py[i] = cy + (cy - oy[i]) * 0.995 + gy * dt * dt;
      pz[i] = cz + (cz - oz[i]) * 0.995;
      ox[i] = cx;
      oy[i] = cy;
      oz[i] = cz;
    }
    for (var pass = 0; pass < _relaxPasses; pass++) {
      for (var i = 0; i < n - 1; i++) {
        final j = i + 1;
        final dx = px[j] - px[i];
        final dy = py[j] - py[i];
        final dz = pz[j] - pz[i];
        final len = math.sqrt(dx * dx + dy * dy + dz * dz);
        final d = len < 1e-6 ? 1e-6 : len;
        final k = ((d - pitch) / d) * 0.5;
        px[i] += dx * k;
        py[i] += dy * k;
        pz[i] += dz * k;
        px[j] -= dx * k;
        py[j] -= dy * k;
        pz[j] -= dz * k;
      }
    }
  }

  void _pin() {
    final last = count - 1;
    px[0] = _a0x;
    py[0] = _a0y;
    pz[0] = _a0z;
    px[last] = _a1x;
    py[last] = _a1y;
    pz[last] = _a1z;
  }

  /// Places link [k] from link [i]: the direction brought into the bend cone
  /// and the length clamped, in one move.
  void _place(int i, int k, bool useCone) {
    var ex = px[k] - px[i];
    var ey = py[k] - py[i];
    var ez = pz[k] - pz[i];
    final raw = math.sqrt(ex * ex + ey * ey + ez * ez);
    final el = raw < 1e-6 ? 1e-6 : raw;
    final len = el > maxPitch ? maxPitch : el;
    ex /= el;
    ey /= el;
    ez /= el;

    // The link on the far side of i fixes the incoming direction.
    final h = i + (i - k);
    if (useCone && h >= 0 && h < count) {
      var dx = px[i] - px[h];
      var dy = py[i] - py[h];
      var dz = pz[i] - pz[h];
      final dlRaw = math.sqrt(dx * dx + dy * dy + dz * dz);
      final dl = dlRaw < 1e-6 ? 1e-6 : dlRaw;
      dx /= dl;
      dy /= dl;
      dz /= dl;
      final ca = dx * ex + dy * ey + dz * ez;
      if (ca < _cosMaxBend) {
        var wx = ex - dx * ca;
        var wy = ey - dy * ca;
        var wz = ez - dz * ca;
        var wl = math.sqrt(wx * wx + wy * wy + wz * wz);
        if (wl < 1e-6) {
          // Folded back exactly on itself: any perpendicular will do.
          wx = dx.abs() < 0.9 ? 1.0 : 0.0;
          wy = dx.abs() < 0.9 ? 0.0 : 1.0;
          wz = 0.0;
          final dp = wx * dx + wy * dy + wz * dz;
          wx -= dx * dp;
          wy -= dy * dp;
          wz -= dz * dp;
          wl = math.sqrt(wx * wx + wy * wy + wz * wz);
          if (wl < 1e-6) wl = 1e-6;
        }
        wx /= wl;
        wy /= wl;
        wz /= wl;
        final sn = math.sqrt(math.max(1 - _cosMaxBend * _cosMaxBend, 0.0));
        ex = dx * _cosMaxBend + wx * sn;
        ey = dy * _cosMaxBend + wy * sn;
        ez = dz * _cosMaxBend + wz * sn;
      }
    }
    px[k] = px[i] + ex * len;
    py[k] = py[i] + ey * len;
    pz[k] = pz[i] + ez * len;
  }

  /// Walks the chain from each end in turn, so the whole length is carried.
  void _walk(bool useCone) {
    final n = count;
    px[0] = _a0x;
    py[0] = _a0y;
    pz[0] = _a0z;
    for (var i = 1; i < n; i++) {
      _place(i - 1, i, useCone);
    }
    px[n - 1] = _a1x;
    py[n - 1] = _a1y;
    pz[n - 1] = _a1z;
    for (var i = n - 2; i >= 0; i--) {
      _place(i + 1, i, useCone);
    }
  }

  void _tangents() {
    final n = count;
    for (var i = 0; i < n; i++) {
      final a = i > 0 ? i - 1 : 0;
      final b = i < n - 1 ? i + 1 : n - 1;
      final x = px[b] - px[a];
      final y = py[b] - py[a];
      final z = pz[b] - pz[a];
      final raw = math.sqrt(x * x + y * y + z * z);
      final l = raw < 1e-6 ? 1e-6 : raw;
      _tanX[i] = x / l;
      _tanY[i] = y / l;
      _tanZ[i] = z / l;
    }
  }

  /// How much room link [j]'s near cap has inside link [i]'s hole. Negative
  /// means the pair is no longer threaded.
  double _clearance(int i, int j) {
    final reach = le + _ring;
    final vx = px[i] - px[j];
    final vy = py[i] - py[j];
    final vz = pz[i] - pz[j];
    final sg = _tanX[j] * vx + _tanY[j] * vy + _tanZ[j] * vz >= 0 ? 1.0 : -1.0;
    final dx = px[j] + sg * reach * _tanX[j] - px[i];
    final dy = py[j] + sg * reach * _tanY[j] - py[i];
    final dz = pz[j] + sg * reach * _tanZ[j] - pz[i];
    final par = dx * _tanX[i] + dy * _tanY[i] + dz * _tanZ[i];
    final ex = dx - _tanX[i] * par;
    final ey = dy - _tanY[i] * par;
    final ez = dz - _tanZ[i] * par;
    final perp = math.sqrt(ex * ex + ey * ey + ez * ez);
    final run = par.abs() - le;
    final v = run > 0 ? run : 0.0;
    return _ring - r2 - math.sqrt(perp * perp + v * v);
  }

  /// Straightens link [m] by [amount], the one move that always buys clearance
  /// back whichever way the chain is curving.
  void _straighten(int m, double amount) {
    final i = m - 1;
    final j = m + 1;
    if (i < 0 || j > count - 1) return;
    final pinI = i == 0;
    final pinJ = j == count - 1;
    if (pinI && pinJ) return;
    var dx = px[j] - px[i];
    var dy = py[j] - py[i];
    var dz = pz[j] - pz[i];
    final raw = math.sqrt(dx * dx + dy * dy + dz * dz);
    final d = raw < 1e-6 ? 1e-6 : raw;
    final k = (amount / d) * (pinI || pinJ ? 1.0 : 0.5);
    dx *= k;
    dy *= k;
    dz *= k;
    if (!pinI) {
      px[i] -= dx;
      py[i] -= dy;
      pz[i] -= dz;
    }
    if (!pinJ) {
      px[j] += dx;
      py[j] += dy;
      pz[j] += dz;
    }
  }
}