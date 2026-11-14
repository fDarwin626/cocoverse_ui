#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// Mito: a small clay robot that hovers on three rings of light. Like ClayBot it
// is drawn by marching a ray through one signed distance field, on a
// transparent canvas, with its shadow on an invisible floor.
//
// World units: the floor is y = 0. The robot's origin is the bottom of its pod,
// uLift above the floor. It is about six and a half units tall, and +z points
// at the lens.
//
// There are no legs. The pod tapers to a point where the rings are. The hands
// are rigid: a palm, four fingers and a thumb that never move on their own.
// The rings are flat 2-D ellipses of light, not geometry, so they are cheap.

uniform vec2 uOrigin;    // px position of the floor origin on the screen
uniform float uPx;       // px per world unit at the robot's depth
uniform vec4 uRect;      // px rectangle outside which nothing is drawn
uniform float uSteps;    // most steps a ray may march
uniform float uAoTaps;   // occlusion probes
uniform float uShSteps;  // most steps a shadow ray may march
uniform vec3 uSun;       // unit direction toward the sun
uniform float uSoft;     // how crisp shadow edges are (higher is crisper)
uniform vec3 uBoxMin;    // box around everything the robot can reach
uniform vec3 uBoxMax;
uniform float uPosX;     // how far it has glided along the space
uniform float uLift;     // height of the bottom of the pod above the floor
uniform vec2 uSq;        // squash: x and z scale, y scale
uniform vec3 uBx;        // body axes (columns of its rotation)
uniform vec3 uBy;
uniform vec3 uBz;
uniform vec3 uHx;        // head axes
uniform vec3 uHy;
uniform vec3 uHz;
uniform vec4 uEye;       // eye offset x, y, openness, joy (0 round, 1 happy arc)
uniform vec4 uArmA;      // left arm: cos and sin of its raise, cos and sin of its swing
uniform vec4 uArmB;      // right arm
uniform vec2 uArmExt;    // how far each arm is stretched out, 0 to 1
uniform vec4 uBodyBox;   // body box: centre y, half size x, y, z
uniform vec3 uClay;      // clay colour, linear
uniform vec3 uVisor;     // screen colour, linear
uniform vec3 uEyeCol;    // eye colour, as shown
uniform float uGlow;     // glow round the eyes
uniform vec3 uShadowCol; // shadow colour, as shown
uniform float uShadowAmt;// how dark the shadow is, 0 to 1
uniform vec3 uRing0;     // colour of the small ring, as shown
uniform vec3 uRing1;     // colour of the medium ring
uniform vec3 uRing2;     // colour of the big ring
uniform vec3 uRingGate;  // how strongly each ring is lit, small to big
uniform float uRingGlow; // overall ring brightness
uniform float uRingPhase;// ring animation clock, wraps every 2*pi*12

out vec4 fragColor;

const float CAM_Y = 3.33;
const float CAM_D = 30.0;
const vec3 HEAD_C = vec3(0.0, 5.0, 0.0);
const vec3 PIVOT = vec3(0.0, 4.2, 0.0);
const vec3 SHOULDER = vec3(1.4, 2.95, 0.0);
// Box round the head, centred on the head's centre.
const vec3 HEAD_B = vec3(1.6, 1.4, 1.45);
// Beyond this, no probe can tell a part's box from the part itself.
const float REACH = 1.5;
// Height over width of a ring seen from just above the floor.
const float RING_RATIO = 0.3;

// A smoothstep that also works when the first edge is the larger one.
float ss(float a, float b, float x) {
  float t = clamp((x - a) / (b - a), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

float smax(float a, float b, float k) {
  return -smin(-a, -b, k);
}

// Rounded rectangle in 2-D: half size b, corner radius r.
float sdRR(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// A bound on the distance to a 2-D ellipse. Inside it, a conservative one.
float sdEll2(vec2 p, vec2 r) {
  float k0 = length(p / r);
  if (k0 < 1.0) return (k0 - 1.0) * min(r.x, r.y);
  float k1 = max(length(p / (r * r)), 0.0001);
  return k0 * (k0 - 1.0) / k1;
}

float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdRBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdEll(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = max(length(p / (r * r)), 0.0001);
  return k0 * (k0 - 1.0) / k1;
}

float sdCap(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a;
  vec3 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

// A cone with a rounded end at each side (radius r1 at a, r2 at b).
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
  vec3 ba = b - a;
  float l2 = dot(ba, ba);
  float rr = r1 - r2;
  float a2 = l2 - rr * rr;
  float il2 = 1.0 / l2;
  vec3 pa = p - a;
  float y = dot(pa, ba);
  float z = y - l2;
  vec3 xv = pa * l2 - ba * y;
  float x2 = dot(xv, xv);
  float y2 = y * y * l2;
  float z2 = z * z * l2;
  float k = sign(rr) * rr * rr * x2;
  if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
  if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
  return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

// An arc about +y: half-aperture (sin, cos), radius ra, thickness rb.
float sdArc(vec2 p, vec2 sc, float ra, float rb) {
  p.x = abs(p.x);
  float d = (sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra);
  return d - rb;
}

// ------------------------------------------------------------------ head
//
// Head space: origin at the helmet's centre, +z toward the lens. The helmet is
// a squarish rounded block with a deep bezel, a flat dark screen set into it,
// a round cup on each side and a flat fin rising from each top corner. The
// coarse version leaves the screen out: shadow and sky probes only need the
// shell.
vec2 headD(vec3 p, bool fine) {
  // A smooth white egg, wider than it is tall.
  float shell = sdEll(p, vec3(1.45, 1.25, 1.3));
  if (!fine) return vec2(shell, 1.0);

  // The face: a big glossy black oval lens set into the front, standing a
  // hair proud of the shell, with the eyes drawn on it.
  float oval = sdEll2(p.xy - vec2(0.0, -0.12), vec2(1.3, 0.86));
  float lens = max(shell - 0.03, max(oval, 0.2 - p.z));
  return shell < lens ? vec2(shell, 1.0) : vec2(lens, 2.0);
}
// ------------------------------------------------------------------ hand
//
// Hand space: u runs along the forearm, s across the palm, f out of it. A
// chunky mitten: a fat palm, four short thick fingers side by side and a
// stubby thumb. Nothing in it ever moves.
float handD(vec3 h) {
  // Far from the hand, a sphere is all that is needed.
  float bound = length(h - vec3(0.0, 0.2, 0.0)) - 0.9;
  if (bound > 0.2) return bound;

  // A round mitt. There are no fingers.
  return sdRBox(h - vec3(0.0, 0.1, 0.0), vec3(0.3, 0.3, 0.24), 0.26);
}

// ------------------------------------------------------------------ arm
//
// Arm space: the shoulder is the origin and the arm hangs along -y. A round
// shoulder, an upper arm, an elbow ball, a forearm and the hand. A waving arm
// stretches its upper arm and swings the forearm up and forward, so the hand
// clears the helmet.
float armD(vec3 p, vec4 arm, float ext) {
  vec3 a = p;
  a.x = abs(a.x);
  a -= SHOULDER;
  a.yz = vec2(arm.z * a.y - arm.w * a.z, arm.w * a.y + arm.z * a.z);
  // At rest the flippers hang a little outward, as EVE's do; a waving one
  // loses that and lifts on its own.
  float fl = 0.04 * (1.0 - ext);
  vec2 cs = vec2(arm.x * cos(fl) - arm.y * sin(fl), arm.y * cos(fl) + arm.x * sin(fl));
  a.xy = vec2(a.x * cs.x + a.y * cs.y, -a.x * cs.y + a.y * cs.x);

  // A flat, leaf-shaped flipper like a penguin's: narrow where it joins the
  // body, broad toward the middle, thin front to back, with a round tip.
  float len = 3.0 + 0.2 * ext;
  float tt = clamp(-a.y / len, 0.0, 1.0);
  float wid = 0.28 * mix(0.5, 1.0, smoothstep(0.0, 0.5, tt));
  return sdEll(a - vec3(0.22 * tt * tt, -len * 0.5, 0.0), vec3(wid, len * 0.5, 0.14)) * 0.8;
}
// ------------------------------------------------------------------ body
//
// Body space: origin at the bottom of the pod.
float bodyD(vec3 p) {
  // The pod: an open cup. A straight wall at the top that curves in to a round
  // bottom where the rings are, with a round collar on the rim and an opening
  // the head sits against.
  float r = length(p.xz);
  float d = sdEll(vec3(p.x, min(p.y - 2.2, 0.0), p.z), vec3(1.5, 2.2, 1.42));
  d = max(d, p.y - 3.4);
  float collar = length(vec2(r - 1.36, p.y - 3.3)) - 0.17;
  d = smin(d, collar, 0.08);
  d = max(d, -max(r - 1.15, 3.0 - p.y));

  vec4 arm = p.x > 0.0 ? uArmB : uArmA;
  float ext = p.x > 0.0 ? uArmExt.y : uArmExt.x;
  return smin(d, armD(p, arm, ext), 0.05);
}
// World to body space, and body to head space.
vec3 toBody(vec3 ps) {
  vec3 pr = ps;
  pr.x -= uPosX;
  pr.y -= uLift;
  pr /= vec3(uSq.x, uSq.y, uSq.x);
  return vec3(dot(uBx, pr), dot(uBy, pr), dot(uBz, pr));
}

vec3 toHead(vec3 pr) {
  vec3 v = pr - PIVOT;
  return vec3(dot(uHx, v), dot(uHy, v), dot(uHz, v)) + PIVOT - HEAD_C;
}

// Distance (world units) and material (1 clay, 2 screen). A part is only
// evaluated when its box is near; boxes stand in when everything is far.
vec2 sceneD(vec3 ps, bool fine) {
  float kq = min(uSq.x, uSq.y);
  vec3 pr = toBody(ps);
  vec3 ph = toHead(pr);
  float bh = sdBox(ph, HEAD_B) * kq;
  float bb = sdBox(pr - vec3(0.0, max(uBodyBox.x, 2.0), 0.0), max(uBodyBox.yzw, vec3(4.6, 3.2, 1.7))) * kq;
  float farD = min(bh, bb);
  if (farD > REACH) return vec2(farD, 1.0);
  vec2 res = vec2(1e5, 1.0);
  if (bh < bb) {
    res = headD(ph, fine);
    res.x *= kq;
    if (bb < res.x) {
      float d = bodyD(pr) * kq;
      if (d < res.x) res = vec2(d, 1.0);
    }
  } else {
    res = vec2(bodyD(pr) * kq, 1.0);
    if (bh < res.x) {
      vec2 h = headD(ph, fine);
      h.x *= kq;
      if (h.x < res.x) res = h;
    }
  }
  return res;
}

float mapD(vec3 p) {
  return sceneD(p, true).x;
}

float mapC(vec3 p) {
  return sceneD(p, false).x;
}

vec3 calcN(vec3 p, float d0, float e) {
  return normalize(vec3(
    mapD(p + vec3(e, 0.0, 0.0)),
    mapD(p + vec3(0.0, e, 0.0)),
    mapD(p + vec3(0.0, 0.0, e))) - d0);
}

// A ray against a box: the distances where it enters and leaves.
vec2 rayBox(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
  vec3 inv = 1.0 / rd;
  vec3 t0 = (bmin - ro) * inv;
  vec3 t1 = (bmax - ro) * inv;
  vec3 lo = min(t0, t1);
  vec3 hi = max(t0, t1);
  return vec2(max(max(lo.x, lo.y), lo.z), min(min(hi.x, hi.y), hi.z));
}

float softShadow(vec3 ro, vec3 rd) {
  vec2 bt = rayBox(ro, rd, uBoxMin, uBoxMax);
  if (bt.y <= max(bt.x, 0.0)) return 1.0;
  float t = max(bt.x, 0.03);
  float res = 1.0;
  for (int i = 0; i < 24; i++) {
    if (float(i) >= uShSteps) break;
    float h = mapC(ro + rd * t);
    res = min(res, uSoft * h / t);
    t += clamp(h, 0.04, 0.8);
    if (res < 0.003 || t > bt.y) break;
  }
  res = clamp(res, 0.0, 1.0);
  return res * res * (3.0 - 2.0 * res);
}

// Small-scale occlusion, so creases read as soft lines, not black cuts.
float calcAO(vec3 p, vec3 n) {
  float occ = 0.0;
  float sc = 1.0;
  for (int i = 0; i < 5; i++) {
    if (float(i) >= uAoTaps) break;
    float h = 0.03 + 0.14 * float(i);
    occ += (h - mapD(p + n * h)) * sc;
    sc *= 0.72;
  }
  return mix(0.3, 1.0, clamp(1.0 - 1.5 * occ, 0.0, 1.0));
}

// Large-scale sky occlusion: probes up and out along the normal. This is what
// darkens the body under the overhanging helmet.
float skyVis(vec3 p, vec3 n) {
  vec3 dir = normalize(n + vec3(0.0, 1.0, 0.0));
  float occ = 0.0;
  for (int i = 0; i < 3; i++) {
    if (float(i) >= uAoTaps - 1.0) break;
    float h = 0.4 + 0.5 * float(i);
    occ += clamp(1.0 - mapC(p + dir * h) / h, 0.0, 1.0);
  }
  return 1.0 - 0.5 * occ / 3.0;
}

// The eyes are not geometry: a 2-D distance drawn on the screen in head
// space, so blinking, looking and the happy arcs are all one shape morphing.
float eyeSD(vec2 p) {
  vec2 q = p - vec2(uEye.x * 0.5, -0.05 + uEye.y * 0.7);
  q.x = abs(q.x) - 0.5;
  float hy = max(0.29 * uEye.z, 0.03);
  float bar = sdEll2(q, vec2(0.4, hy));
  float arc = sdArc(q + vec2(0.0, 0.15), vec2(0.906, 0.423), 0.28, 0.07);
  return mix(bar, arc, uEye.w);
}

// ------------------------------------------------------------------ rings
//
// One thruster ring: a flat ellipse of light under the pod. cy is how far
// below the bottom of the pod its centre hangs, rx its half width. The rings
// pulse one after another, smallest first, so a ripple of light runs down; a
// bright rim carries slowly turning gaps, with a soft glow round it. Returns
// premultiplied colour that is brighter than it is opaque, so it adds light.
vec4 ringD(vec2 w, float rx, float cy, vec3 col, float gate, float k, float dir) {
  if (gate <= 0.001) return vec4(0.0);
  float p = 0.5 + 0.5 * sin(uRingPhase * 1.5 - k * 1.1);
  float s = 1.0 + 0.09 * p;
  vec2 r = vec2(rx * s, rx * s * RING_RATIO);
  vec2 pc = w - vec2(0.0, uLift - cy);
  if (abs(pc.x) > r.x + 1.2 || abs(pc.y) > r.y + 1.2) return vec4(0.0);

  float d = sdEll2(pc, r);
  vec2 qn = pc / r;
  float t = max(0.05 + 0.025 * p, 1.4 / uPx);
  float rim = exp(-(d / t) * (d / t));
  float seg = 0.62 + 0.38 * cos(atan(qn.y, qn.x) * 5.0 + uRingPhase * dir);
  float outer = d > 0.0 ? exp(-d * 4.5) * 0.28 : 0.0;
  float len = length(qn);
  float inner = len < 1.0 ? (1.0 - len) * 0.16 : 0.0;
  float b = (rim * seg + outer + inner) * gate * uRingGlow * (0.72 + 0.28 * p);
  b = clamp(b, 0.0, 1.0);
  return vec4(col * b, b * 0.8);
}

// A soft pool of ring light on the floor under the robot. It fades as the
// robot rises.
vec4 floorPool(vec2 w) {
  vec2 q = vec2(w.x / 2.0, w.y / 0.55);
  float g = exp(-dot(q, q) * 2.0);
  float amt = uRingGate.y * uRingGlow * 0.4 *
      clamp(1.0 - (uLift - 1.6) * 0.35, 0.25, 1.0);
  float b = clamp(g * amt, 0.0, 1.0);
  return vec4(uRing2 * b, b * 0.5);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  if (frag.x < uRect.x || frag.y < uRect.y || frag.x > uRect.z || frag.y > uRect.w) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 ro = vec3(0.0, CAM_Y, CAM_D);
  vec2 q = vec2((frag.x - uOrigin.x) / uPx, (uOrigin.y - frag.y) / uPx - CAM_Y);
  vec3 rd = normalize(vec3(q, -CAM_D));
  float tf = rd.y < 0.0 ? -ro.y / rd.y : 1e9;
  // World units per pixel, per unit of distance along the ray.
  float pxk = 1.0 / (uPx * CAM_D);

  float cov = 0.0;
  vec3 col = vec3(0.0);
  vec2 bt = rayBox(ro, rd, uBoxMin, uBoxMax);
  if (bt.y > max(bt.x, 0.0)) {
    float t = max(bt.x, 0.0);
    float tEnd = min(bt.y, tf);
    bool hit = false;
    float rmin = 1e9;
    float tMin = t;
    for (int i = 0; i < 80; i++) {
      if (float(i) >= uSteps || t > tEnd) break;
      float d = sceneD(ro + rd * t, true).x;
      float fp = pxk * t;
      if (d < 0.35 * fp) {
        hit = true;
        break;
      }
      float r = d / fp;
      if (r < rmin) {
        rmin = r;
        tMin = t;
      }
      t += d;
    }
    if (hit) {
      rmin = 0.0;
      tMin = t;
    }
    // A ray that just misses still covers part of the pixel.
    cov = hit ? 1.0 : 1.0 - ss(0.4, 1.4, rmin);

    if (cov > 0.0) {
      vec3 p = ro + rd * tMin;
      vec2 dd = sceneD(p, true);
      float fp = pxk * tMin;
      vec3 n = calcN(p, dd.x, max(fp * 0.5, 0.0015));
      float ao = calcAO(p, n) * skyVis(p, n);
      float ndl = dot(n, uSun);
      float sh = ndl > 0.03 ? softShadow(p + n * 0.01, uSun) : 0.0;

      vec3 alb = dd.y > 1.5 ? uVisor : uClay;
      // A blue-grey sky, stronger from above and from the sun's side, plus
      // one low warm sun.
      vec2 sunSide = normalize(uSun.xz + vec2(0.00001));
      float side = max(dot(n.xz, sunSide), 0.0);
      vec3 sky = mix(vec3(0.34, 0.37, 0.42), vec3(0.52, 0.57, 0.64), n.y * 0.5 + 0.5)
        + vec3(0.02, 0.04, 0.07) * side;
      vec3 lit = sky * ao + vec3(0.36, 0.29, 0.22) * max(ndl, 0.0) * sh;

      // The rings light the underside of the pod.
      vec3 ringLin = pow(max(uRing1, vec3(0.0)), vec3(2.2));
      float low = 1.0 - ss(0.0, 1.9, p.y - uLift);
      float under = clamp(0.35 - 0.65 * n.y, 0.0, 1.0);
      lit += ringLin * (uRingGate.y * uRingGlow) * low * under * 1.6 * ao;

      // Metal: little diffuse, mostly a reflection of a simple sky with a
      // bright horizon band and a sun glint, tinted by the metal and faintly
      // brushed.
      vec3 rv = reflect(rd, n);
      vec3 pm = toBody(p);
      float brush = 0.97 + 0.03 * sin(pm.y * 70.0 + sin(pm.x * 9.0) * 2.0);
      vec3 env = mix(vec3(0.10, 0.11, 0.13), vec3(0.65, 0.72, 0.82), ss(-0.2, 0.5, rv.y));
      float hz = (rv.y - 0.05) / 0.12;
      env += vec3(0.9, 0.95, 1.0) * 0.5 * exp(-hz * hz);
      env += vec3(1.0, 0.9, 0.75) * pow(max(dot(rv, uSun), 0.0), 24.0) * 1.2 * sh;
      // Glossy plastic, not metal: mostly diffuse, with a clear reflection that
      // grows toward the edges. The face is the same gloss over black.
      float fres = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
      vec3 metal = alb * lit * 1.05 + env * (0.07 + 0.5 * fres) * ao;
      vec3 shown = dd.y > 1.5 ? alb * lit * 0.5 + env * (0.025 + 0.45 * fres) * ao : metal;
      col = pow(max(shown, vec3(0.0)), vec3(1.0 / 2.2));
      // A small light panel on the chest: three dots, in the eye colour, white
      // and the ring colour.
      vec3 pb = toBody(p);
      float onBody = (dd.y < 1.5 && pb.y < 3.3 && pb.z > 0.35) ? 1.0 : 0.0;
      float c0 = length(pb.xy - vec2(0.45, 2.45)) / 0.07;
      float c1 = length(pb.xy - vec2(0.67, 2.45)) / 0.07;
      float c2 = length(pb.xy - vec2(0.89, 2.45)) / 0.07;
      vec3 chest = uEyeCol * exp(-c0 * c0 * c0 * c0) + vec3(1.0) * exp(-c1 * c1 * c1 * c1)
        + uRing1 * exp(-c2 * c2 * c2 * c2);
      col += chest * onBody;
      if (dd.y > 1.5) {
        // Eyes: a 2-D shape on the screen, smoothed over the pixel's
        // footprint in head units.
        vec3 ph = toHead(toBody(p));
        float eD = eyeSD(ph.xy);
        float kq = min(uSq.x, uSq.y);
        float eW = 0.75 * fp / kq;
        float eye = 1.0 - smoothstep(-eW, eW, eD);
        float front = smoothstep(0.3, 0.5, ph.z);
        float halo = uGlow * exp(-max(eD, 0.0) * 7.0) * (1.0 - eye);
        col += uEyeCol * halo * 0.35 * front;
        // Fine horizontal scanlines, like EVE's LED eyes.
        float scan = 0.88 + 0.12 * smoothstep(-0.3, 0.3, sin(ph.y * 70.0));
        col = mix(col, uEyeCol * scan, eye * front);
      }
    }
  }

  // The shadow on the invisible floor: a soft translucent patch.
  vec4 shadow = vec4(0.0);
  if (tf < 1e8) {
    vec3 pf = ro + rd * tf;
    float sh = softShadow(pf + vec3(0.0, 0.002, 0.0), uSun);
    // Close to the robot the floor is also shaded by what is above it.
    vec3 m = clamp(pf, uBoxMin, uBoxMax);
    if (distance(pf.xz, m.xz) < 0.6) {
      float h = 0.3;
      sh *= mix(0.55, 1.0, clamp(mapD(pf + vec3(0.0, h, 0.0)) / h, 0.0, 1.0));
    }
    float a = (1.0 - sh) * uShadowAmt;
    shadow = vec4(uShadowCol * a, a);
  }

  // The thruster rings and the pool of light they throw on the floor, both
  // behind the robot.
  vec2 w = vec2((frag.x - uOrigin.x) / uPx - uPosX, (uOrigin.y - frag.y) / uPx);
  vec4 rings = ringD(w, 0.46, 0.22, uRing0, uRingGate.x, 0.0, 1.0)
      + ringD(w, 0.80, 0.60, uRing1, uRingGate.y, 1.0, -1.0)
      + ringD(w, 1.20, 1.04, uRing2, uRingGate.z, 2.0, 2.0);
  rings = clamp(rings, 0.0, 1.0);
  vec4 pool = floorPool(w);
  vec4 back = pool + shadow * (1.0 - pool.a);
  vec4 behind = rings + back * (1.0 - rings.a);

  vec4 robot = vec4(col * cov, cov);
  fragColor = robot + behind * (1.0 - cov);
}
