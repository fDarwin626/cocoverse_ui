#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// A wet glossy eyeball, ray traced per pixel, orthographic. Two spheres: the
// ball (radius 1) and a smaller corneal sphere whose cap bulges out past it
// over the iris. The cornea refracts onto a recessed iris plane, and both
// surfaces reflect a fixed studio.

uniform vec2 uCenter;   // eye centre, px, y down
uniform float uRadius;  // eye radius, px
uniform vec3 uRotX;     // eye-local x axis, in view space
uniform vec3 uRotY;     // eye-local y axis
uniform vec3 uRotZ;     // eye-local z axis (the gaze)
uniform float uCosA;
uniform float uSinA;
uniform float uZc;      // corneal sphere centre, along the gaze
uniform float uRc;      // corneal sphere radius
uniform float uIrisZ;   // iris plane, along the gaze
uniform float uIrisR;
uniform float uPupil;   // pupil radius, share of the iris
uniform vec3 uIris;
uniform vec3 uSclera;
uniform vec3 uCollar;
uniform vec2 uLight;    // cos, sin of the studio's roll
uniform float uGloss;
uniform float uRed;
uniform float uVeins;
uniform float uLimbus;
uniform float uFiber;
uniform float uTime;
uniform float uDetail;  // 0 drops the finest fibres and veins

out vec4 fragColor;

// A smoothstep that is safe when the edges are the wrong way round.
float sstep(float e0, float e1, float x) {
  float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

vec3 rotv(vec3 v) {
  return uRotX * v.x + uRotY * v.y + uRotZ * v.z;
}

vec3 rotT(vec3 v) {
  return vec3(dot(v, uRotX), dot(v, uRotY), dot(v, uRotZ));
}

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
        mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
    mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
        mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
    f.z);
}

// The studio. A rectangular light seen through a gnomonic projection, so its
// reflection keeps straight edges on the ball like a real softbox.
float box(vec3 R, vec3 d, vec3 up, vec2 hw, float soft) {
  float k = dot(R, d);
  if (k <= 0.0) return 0.0;
  vec3 rt = normalize(cross(up, d));
  vec3 u = cross(d, rt);
  vec2 uv = vec2(dot(R, rt), dot(R, u)) / k;
  vec2 t = clamp((abs(uv) - hw - vec2(soft)) / (-2.0 * soft), 0.0, 1.0);
  vec2 e = t * t * (3.0 - 2.0 * t);
  return e.x * e.y;
}

vec3 roll(vec3 v) {
  return vec3(uLight.x * v.x - uLight.y * v.y, uLight.y * v.x + uLight.x * v.y, v.z);
}

vec3 env(vec3 R) {
  vec3 c = vec3(0.0);
  c += vec3(1.0, 0.98, 0.97) * 16.0 *
       box(R, roll(normalize(vec3(0.40, 0.72, -0.55))), vec3(0.0, 0.0, 1.0), vec2(0.75, 0.75), 0.35);
  c += vec3(1.0, 0.97, 0.95) * 9.0 *
       box(R, roll(normalize(vec3(-0.92, 0.05, 0.25))), vec3(0.0, 1.0, 0.0), vec2(0.22, 0.65), 0.10);
  c += vec3(1.0, 0.95, 0.92) * 6.0 *
       box(R, roll(normalize(vec3(-0.80, -0.45, 0.10))), vec3(0.0, 1.0, 0.0), vec2(0.30, 0.18), 0.08);
  c += vec3(1.0, 0.9, 0.88) * 2.2 *
       box(R, roll(normalize(vec3(-0.45, -0.55, -0.70))), vec3(0.0, 1.0, 0.0), vec2(0.9, 0.35), 0.35);
  c += vec3(0.05, 0.045, 0.045) * (0.4 + 0.6 * sstep(-0.4, 1.0, R.y));
  return c;
}

// The iris: radial fibres from noise stretched along the angle, a ragged
// brown collarette, a dark limbal ring.
vec3 irisShade(vec2 q) {
  float r = length(q);
  float a = atan(q.y, q.x);
  vec2 cs = vec2(cos(a), sin(a));
  float w = (vnoise(vec3(cs * 5.0, r * 4.0)) - 0.5) * 0.06 +
            (vnoise(vec3(cs * 16.0, r * 10.0)) - 0.5) * 0.025;
  vec2 cw = vec2(cos(a + w), sin(a + w));
  float n1 = vnoise(vec3(cw * 9.0, r * 3.0 + 3.0));
  float t1 = pow(1.0 - abs(vnoise(vec3(cw * 38.0, r * 3.0 + 9.0)) * 2.0 - 1.0), 5.0);
  float t2 = 0.0;
  if (uDetail > 0.5) {
    t2 = pow(1.0 - abs(vnoise(vec3(cw * 63.0, r * 5.0 + 1.7)) * 2.0 - 1.0), 6.0);
  }
  float run = sstep(0.25, 0.75, vnoise(vec3(cw * 20.0, r * 13.0 + 4.0)));
  float thr = clamp((t1 + t2 * 0.8) * (0.30 + 0.70 * run), 0.0, 1.0);

  vec3 dark = uIris * vec3(0.06, 0.10, 0.03);
  vec3 light = mix(uIris, vec3(0.80, 0.95, 0.30), 0.3) * 1.5;
  vec3 c = mix(dark, uIris * 0.8, sstep(0.2, 0.75, n1) * 0.35 + 0.05);
  c = mix(c, light, thr * uFiber);
  if (uDetail > 0.5) {
    c *= 1.0 - 0.7 * sstep(0.68, 0.86, vnoise(vec3(cw * 16.0, r * 9.0 + 21.0))) * uFiber;
  }
  float n2 = vnoise(vec3(cw * 30.0, r * 7.0 + 9.0));
  c = mix(mix(dark, uIris, 0.5), c, uFiber);

  c *= mix(1.0, 0.30, sstep(0.80, 1.0, r) * (0.5 + 0.5 * uLimbus));

  float pr = uPupil;
  float cr = pr * (1.35 + 0.8 * (vnoise(vec3(cs * 6.0, 11.0)) - 0.5) + 0.45 * (n2 - 0.5));
  float collar = sstep(cr, cr - 0.07, r);
  vec3 cc = uCollar * (0.35 + 1.5 * n2);
  cc = mix(cc, vec3(0.50, 0.05, 0.03),
           sstep(0.62, 0.85, vnoise(vec3(cs * 23.0, r * 14.0))) * 0.8);
  c = mix(c, cc, collar * 0.85);

  float jag = 0.03 * (vnoise(vec3(cs * 13.0, 2.0)) - 0.5);
  c *= mix(0.45, 1.0, sstep(pr, pr + 0.14, r));
  float pupil = sstep(pr + 0.012, pr - 0.012, r + jag);
  return mix(c, vec3(0.004), pupil);
}

float veinLines(vec3 n, float f, float seed) {
  vec3 wq = n * f;
  wq += vec3(vnoise(wq * 0.5 + seed), vnoise(wq * 0.5 + seed + 7.1), vnoise(wq * 0.5 + seed + 3.3)) * 0.8;
  float v = vnoise(wq);
  return sstep(0.018, 0.0, abs(v - 0.5));
}

vec3 scleraAlbedo(vec3 nl) {
  vec3 a = uSclera;
  float away = sstep(uCosA - 0.06, uCosA - 0.55, nl.z);
  float v = 0.0;
  if (uVeins > 0.001) {
    float big = veinLines(nl, 5.0, 0.0);
    float fine = 0.0;
    if (uDetail > 0.5) {
      fine = veinLines(nl, 11.0, 17.0) * 0.6;
    }
    v = clamp(big + fine, 0.0, 1.0) * away * uVeins;
  }
  a = mix(a, vec3(0.62, 0.07, 0.07), v * 0.75);
  a *= mix(vec3(1.0), vec3(1.0, 0.82, 0.82), vnoise(nl * 3.0 + 5.0) * 0.5 * uRed);
  return a;
}

// Per-channel wrap: red scatters further round the terminator than blue.
vec3 diffuse(vec3 n, vec3 albedo) {
  vec3 L = roll(normalize(vec3(0.50, 0.70, 0.55)));
  float ndl = dot(n, L);
  vec3 wrap = vec3(0.90, 0.50, 0.50) * (0.35 + 0.65 * uRed);
  vec3 d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
  d *= d;
  float fill = max(0.0, dot(n, roll(normalize(vec3(-0.85, -0.15, 0.50)))));
  return albedo * (d * 1.55 + vec3(0.30, 0.16, 0.16) * fill + 0.03);
}

// The soft grey ring round the iris, pulled toward grey.
vec3 limbShade(vec3 c, float k) {
  k = clamp(k, 0.0, 1.0);
  float g = dot(c, vec3(0.3, 0.5, 0.2));
  return mix(c, vec3(min(g, 1.2)) * 0.22, k);
}

vec2 sphereHit(vec3 ro, vec3 rd, vec3 c, float r) {
  vec3 oc = ro - c;
  float b = dot(oc, rd);
  float h = b * b - (dot(oc, oc) - r * r);
  if (h < 0.0) return vec2(-1.0, h);
  return vec2(-b - sqrt(h), h);
}

float tone(float x) {
  return x < 0.8 ? x : 0.8 + 0.2 * (1.0 - exp(-(x - 0.8) / 0.2));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float px = 0.75 / uRadius;
  vec2 p = vec2(frag.x - uCenter.x, uCenter.y - frag.y) / uRadius;

  vec3 ro = vec3(p, 4.0);
  vec3 rd = vec3(0.0, 0.0, -1.0);
  vec3 fwd = uRotZ;
  vec3 cc = fwd * uZc;

  vec2 hE = sphereHit(ro, rd, vec3(0.0), 1.0);
  vec2 hC = sphereHit(ro, rd, cc, uRc);
  vec3 PC = ro + rd * hC.x;
  bool capHit = hC.x > 0.0 && dot(PC, fwd) > uCosA;

  // The ball's disc, plus the corneal cap where it stands proud of it.
  float cov = 1.0 - sstep(1.0 - px, 1.0 + px, length(p));
  vec2 dc = p - cc.xy;
  vec3 rimC = cc + vec3(normalize(dc + vec2(0.000001)) * uRc, 0.0);
  float capRim = sstep(uCosA - 0.01, uCosA + 0.01, dot(rimC, fwd));
  cov = max(cov, (1.0 - sstep(uRc - px, uRc + px, length(dc))) * capRim);
  if (cov <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 col;
  if (capHit) {
    // Cornea: refract onto the recessed iris plane.
    vec3 N = normalize(PC - cc);
    vec3 Pl = rotT(PC);
    vec3 rr = refract(rd, N, 1.0 / 1.376);
    vec3 rl = rotT(rr);
    float t = (uIrisZ - Pl.z) / min(rl.z, -0.001);
    vec2 q = (Pl.xy + rl.xy * t) / (uIrisR * 0.95);
    float rq = length(q);

    vec3 ir = vec3(0.0);
    if (rq < 1.06) {
      ir = irisShade(q);
      float il = 0.75 + 0.5 * max(0.0, dot(fwd, roll(normalize(vec3(0.30, 0.75, 0.60)))));
      ir *= il * (0.78 + 0.22 * sstep(0.9, -0.4, q.y));
    }
    vec3 under = vec3(0.0);
    if (rq > 0.95) {
      under = diffuse(normalize(fwd + rotv(vec3(q * uIrisR, 0.0))),
                      scleraAlbedo(vec3(q * uSinA, uCosA)));
    }
    vec3 base = mix(ir, under, sstep(0.97, 1.06, rq));

    float lr = (rq - 1.03) / 0.10;
    float rim = length(Pl.xy) / uSinA;
    float lc = (rim - 1.0) / 0.10;
    base = limbShade(base, uLimbus * max(exp(-lr * lr), exp(-lc * lc)));

    float ndv = max(0.0, N.z);
    float F = 0.025 + 0.975 * pow(1.0 - ndv, 5.0);
    col = base * (1.0 - F) + env(reflect(rd, N)) * F * uGloss * 1.4;
  } else {
    // Sclera.
    vec3 P = ro + rd * max(hE.x, 0.0);
    if (hE.x < 0.0) P = vec3(normalize(p) * 0.999, 0.03);
    vec3 N = normalize(P);
    vec3 nl = rotT(N);
    col = diffuse(N, scleraAlbedo(nl));
    float lg = (uCosA - nl.z) / 0.06;
    col = limbShade(col, uLimbus * exp(-lg * lg));
    float graze = pow(1.0 - clamp(N.z, 0.0, 1.0), 3.0);
    col *= mix(vec3(1.0), vec3(0.62, 0.24, 0.23), graze * 0.9 * uRed);
    float F = 0.04 + 0.96 * pow(1.0 - clamp(N.z, 0.0, 1.0), 5.0);
    col += env(reflect(rd, N)) * F * uGloss;
  }

  col = vec3(tone(col.r), tone(col.g), tone(col.b));
  col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2));
  col += (hash13(vec3(frag, uTime)) - 0.5) / 255.0;
  fragColor = vec4(col * cov, cov);
}