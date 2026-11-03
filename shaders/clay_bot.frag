#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// A small matte clay robot, drawn by marching a ray through one signed
// distance field. There is no floor and no background: only the robot, and
// its shadow on an invisible floor, which is drawn as a soft translucent
// patch on a transparent canvas.
//
// World units: the floor is y = 0, the robot stands between the feet at the
// origin and is about six units tall, and +z points at the lens.

uniform vec2 uOrigin;    // px position of the world origin on the screen
uniform float uPx;       // px per world unit at the robot's depth
uniform vec4 uRect;      // px rectangle outside which nothing is drawn
uniform float uSteps;    // most steps a ray may march
uniform float uAoTaps;   // occlusion probes
uniform float uShSteps;  // most steps a shadow ray may march
uniform vec3 uSun;       // unit direction toward the sun
uniform float uSoft;     // how crisp shadow edges are (higher is crisper)
uniform vec3 uBoxMin;    // box around everything the robot can reach
uniform vec3 uBoxMax;
uniform float uWalkX;    // how far it has walked along the floor
uniform float uHop;      // how far it is lifted
uniform vec2 uSq;        // squash: x and z scale, y scale
uniform vec3 uBx;        // body axes (columns of its rotation)
uniform vec3 uBy;
uniform vec3 uBz;
uniform vec3 uHx;        // head axes
uniform vec3 uHy;
uniform vec3 uHz;
uniform vec4 uEye;       // eye offset x, y, openness, joy (0 round, 1 happy arc)
uniform vec2 uFeet;      // lift of the left and right foot
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

out vec4 fragColor;

const float CAM_Y = 3.33;
const float CAM_D = 30.0;
const vec3 HEAD_C = vec3(0.0, 4.08, 0.0);
const vec3 PIVOT = vec3(0.0, 2.55, 0.0);
const vec3 SHOULDER = vec3(1.017, 1.62, 0.05);
const vec3 HEAD_B = vec3(2.9, 2.32, 1.0);
// Beyond this, no probe can tell a part's box from the part itself.
const float REACH = 1.5;

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

// A 2-D outline (distance d2) extruded to half depth hz, every depth edge
// rounded by re.
float extrude(float d2, float z, float hz, float re) {
  vec2 w = vec2(d2 + re, abs(z) - hz + re);
  return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - re;
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

// An arc about +y: half-aperture (sin, cos), radius ra, thickness rb.
float sdArc(vec2 p, vec2 sc, float ra, float rb) {
  p.x = abs(p.x);
  float d = (sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra);
  return d - rb;
}

// ------------------------------------------------------------------ head
//
// Head space: origin at the helmet's centre, +z toward the lens. The helmet
// is a slightly wide ellipse from the front, rolled into a deep pillow, with
// a soft round bed in its face for a domed screen. The coarse version leaves
// the screen out: shadow and sky probes only need the shell.
vec2 headD(vec3 p, bool fine) {
  float shell = extrude(sdEll2(p.xy, vec2(2.5, 2.3)), p.z, 0.95, 0.8);
  vec2 v = p.xy - vec2(0.0, -0.1);
  shell = smax(shell, -extrude(sdEll2(v, vec2(2.02, 1.8)), p.z - 0.95, 0.3, 0.05), 0.16);

  // Ears: a short round disc each side.
  vec3 e = vec3(abs(p.x) - 2.6, p.y, p.z + 0.05);
  vec2 we = vec2(length(e.yz) - 0.42, abs(e.x) - 0.06);
  float ear = min(max(we.x, we.y), 0.0) + length(max(we, 0.0)) - 0.2;
  shell = smin(shell, ear, 0.05);
  if (!fine) return vec2(shell, 1.0);

  // The screen: a domed round pillow sitting proud in that bed.
  vec2 n = v / vec2(1.98, 1.76);
  float sz = p.z - 0.62 + 0.12 * dot(n, n);
  float screen = extrude(sdEll2(v, vec2(1.98, 1.76)), sz, 0.34, 0.17) * 0.9;
  return shell < screen ? vec2(shell, 1.0) : vec2(screen, 2.0);
}

// ------------------------------------------------------------------ body
//
// Body space: origin between the feet.
float bodyD(vec3 p) {
  // Walking lifts one foot: the lower body on that side rises, fading out by
  // the waist, so the step reads without separate legs.
  float lift = mix(uFeet.x, uFeet.y, smoothstep(-0.3, 0.3, p.x));
  vec3 q = p;
  q.y -= lift * (1.0 - smoothstep(0.0, 1.0, q.y));
  float d = sdRBox(q - vec3(0.0, 1.05, 0.0), vec3(0.99, 1.05, 0.72), 0.5);
  // An arch between the feet: a low triangle, blended wide, so the flanks
  // flare into feet and the peak rounds over.
  vec2 ta = vec2(abs(q.x), q.y + 0.06);
  float tri = max(dot(ta, vec2(0.33, 0.944)) - 0.3 * 0.944, -ta.y);
  d = smax(d, -max(tri, abs(q.z) - 1.4), 0.17);
  d *= 1.0 - 1.1 * max(uFeet.x, uFeet.y);

  // Arms hinge at the shoulder: swing forward and back, then raise outward.
  vec4 arm = p.x > 0.0 ? uArmB : uArmA;
  float ext = p.x > 0.0 ? uArmExt.y : uArmExt.x;
  vec3 a = p;
  a.x = abs(a.x);
  a -= SHOULDER;
  a.yz = vec2(arm.z * a.y - arm.w * a.z, arm.w * a.y + arm.z * a.z);
  a.xy = vec2(a.x * arm.x + a.y * arm.y, -a.x * arm.y + a.y * arm.x);
  a.y += 0.3 + 0.5 * ext;
  // A waving arm stretches like soft clay, so the hand clears the helmet.
  float hand = sdEll(a, vec3(0.24 - 0.03 * ext, 0.37 + 0.5 * ext, 0.25 - 0.03 * ext));
  return smin(d, hand, 0.06);
}

// World to body space, and body to head space.
vec3 toBody(vec3 ps) {
  vec3 pr = ps;
  pr.x -= uWalkX;
  pr.y -= uHop;
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
  float bb = sdBox(pr - vec3(0.0, uBodyBox.x, 0.0), uBodyBox.yzw) * kq;
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
  vec2 q = p - vec2(uEye.x, -0.5 + uEye.y);
  q.x = abs(q.x) - 0.5;
  float hy = max(0.4 * uEye.z, 0.03);
  float bar = sdRR(q, vec2(0.39, hy), min(0.13, hy));
  float arc = sdArc(q + vec2(0.0, 0.15), vec2(0.906, 0.423), 0.28, 0.07);
  return mix(bar, arc, uEye.w);
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
      col = pow(max(alb * lit, vec3(0.0)), vec3(1.0 / 2.2));

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
        col = mix(col, uEyeCol, eye * front);
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

  vec4 robot = vec4(col * cov, cov);
  fragColor = robot + shadow * (1.0 - cov);
}
