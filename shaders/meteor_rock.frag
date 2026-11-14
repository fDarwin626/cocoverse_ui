#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// The meteor's rock, ray cast per pixel. Every slab is a convex body made of
// planes, so a ray meets it by clipping against those planes. The grain, the
// bump, the weathered plates, the fissures and the heat are the original
// website's rock shader, sampled in the slab's own "rest" space so they stay
// painted on the stone as it tumbles.

uniform vec2 uCenter;   // px position of the origin on the screen, y down
uniform float uFocal;   // px per unit at distance 1 from the lens
uniform float uCamD;    // lens distance from the origin
uniform float uTime;    // melt clock
uniform float uHeat;    // how hard the melt glows
uniform float uLava;    // how far the hollow's light reaches
uniform float uOct;     // noise octaves, 3 to 5
uniform float uSlabs;   // how many slabs are in the arrays
uniform float uInner;   // inner radius of the hollow
uniform vec3 uCore;     // the point light in the hollow
uniform float uGround;  // how much red fire-bounce the rock takes
uniform vec4 uPlane[168]; // 14 planes a slab: world normal, offset
uniform vec4 uSlabB[12];  // world centre, bounding radius
uniform vec4 uSlabQ[12];  // quaternion taking world back to rest
uniform vec4 uSlabC[12];  // rest centroid, slab value

out vec4 fragColor;

const vec3 KEY = vec3(0.2182, 0.8729, 0.4364);
const vec3 FILL = vec3(0.7518, -0.1253, -0.6474);
const vec3 BOUNCE = vec3(0.0, -0.9701, 0.2425);
const vec3 GROUND = vec3(1.0, 0.0194, 0.0018);
const vec3 LAVA = vec3(1.0, 0.0437, 0.0);
const vec3 HOT = vec3(1.0, 0.552, 0.144);
const vec3 ROCK = vec3(0.0086, 0.0075, 0.0060);

float hash31(vec3 p) {
  p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash31(i + vec3(0.0, 0.0, 0.0)), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
        mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
    mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
        mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.1, 1.0)), f.x), f.y),
    f.z);
}

float fbm(vec3 p) {
  float a = 0.5;
  float s = 0.0;
  for (int i = 0; i < 5; i++) {
    if (float(i) >= uOct) break;
    s += a * vnoise(p);
    p *= 2.03;
    a *= 0.5;
  }
  return s;
}

vec3 qrot(vec4 q, vec3 v) {
  vec3 u = q.xyz;
  return v + 2.0 * cross(u, cross(u, v) + q.w * v);
}

// A neutral key from above, a cool fill from behind, the fire's bounce from
// below, a dim sky, and the melt in the hollow as a point light.
vec3 shade(vec3 P, vec3 N, vec3 V, vec3 albedo, float spec, float gloss, float ground) {
  float key = max(dot(N, KEY), 0.0);
  vec3 col = albedo * key * 2.05;
  col += albedo * max(dot(N, FILL), 0.0) * vec3(0.2, 0.235, 0.35);
  col += albedo * max(dot(N, BOUNCE), 0.0) * GROUND * 1.55 * ground;
  float up = N.y * 0.5 + 0.5;
  col += albedo * mix(GROUND * 0.42 * ground, vec3(0.078, 0.085, 0.108), up);
  vec3 toCore = uCore - P;
  float dist = max(length(toCore), 0.0001);
  vec3 L = toCore / dist;
  float atten = 1.0 / (1.0 + dist * dist * 3.2);
  col += albedo * LAVA * max(dot(N, L), 0.0) * atten * uLava * 5.5 * (0.35 + 0.65 * ground);
  vec3 H = normalize(KEY + V);
  col += vec3(1.0) * pow(max(dot(N, H), 0.0), gloss) * spec;
  return col;
}

vec3 aces(vec3 color) {
  const mat3 inMat = mat3(
    vec3(0.59719, 0.07600, 0.02840),
    vec3(0.35458, 0.90834, 0.13383),
    vec3(0.04823, 0.01566, 0.83777));
  const mat3 outMat = mat3(
    vec3(1.60475, -0.10208, -0.00327),
    vec3(-0.53108, 1.10813, -0.07276),
    vec3(-0.07367, -0.00605, 1.07602));
  color *= 1.0 / 0.6;
  color = inMat * color;
  vec3 a = color * (color + 0.0245786) - 0.000090537;
  vec3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
  color = outMat * (a / b);
  return clamp(color, 0.0, 1.0);
}

vec3 encode(vec3 c) {
  vec3 lo = c * 12.92;
  vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
  return mix(hi, lo, step(c, vec3(0.0031308)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec3 ro = vec3(0.0, 0.0, uCamD);
  vec3 rd = normalize(vec3((frag.x - uCenter.x) / uFocal, (uCenter.y - frag.y) / uFocal, -1.0));

  float bestT = 1e9;
  vec3 bestN = vec3(0.0);
  vec3 bestRest = vec3(0.0);
  float bestV = 0.0;

  for (int s = 0; s < 12; s++) {
    if (float(s) >= uSlabs) break;
    vec4 b = uSlabB[s];
    vec3 oc = ro - b.xyz;
    float bq = dot(oc, rd);
    float cq = dot(oc, oc) - b.w * b.w;
    if (bq * bq - cq < 0.0) continue;

    float t0 = 0.0;
    float t1 = 1e9;
    vec3 n0 = vec3(0.0);
    bool miss = false;
    for (int k = 0; k < 14; k++) {
      vec4 pl = uPlane[s * 14 + k];
      float denom = dot(pl.xyz, rd);
      float num = pl.w - dot(pl.xyz, ro);
      if (denom < -0.00001) {
        float t = num / denom;
        if (t > t0) {
          t0 = t;
          n0 = pl.xyz;
        }
      } else if (denom > 0.00001) {
        t1 = min(t1, num / denom);
      } else if (num < 0.0) {
        miss = true;
      }
    }
    if (!miss && t0 > 0.0 && t0 < t1 && t0 < bestT) {
      bestT = t0;
      bestN = n0;
      vec3 p = ro + rd * t0;
      bestRest = qrot(uSlabQ[s], p - b.xyz) + uSlabC[s].xyz;
      bestV = uSlabC[s].w;
    }
  }

  if (bestT > 1e8) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 P = ro + rd * bestT;
  vec3 N = bestN;
  vec3 V = normalize(ro - P);
  vec3 rest = bestRest;

  // Grain is sampled in rest space, so it is painted on the rock.
  float grain = fbm(rest * 9.0);
  float coarse = fbm(rest * 1.9 + 11.0);

  // Bump the normal by the slope of the grain.
  float e = 0.035;
  vec3 g = vec3(
    fbm(rest * 9.0 + vec3(e, 0.0, 0.0)) - grain,
    fbm(rest * 9.0 + vec3(0.0, e, 0.0)) - grain,
    fbm(rest * 9.0 + vec3(0.0, 0.0, e)) - grain);
    // Fine grit on top, random facets per pixel, so the stone reads as rough
  // at any size and not as smooth clouds.
  vec3 grit = vec3(
    vnoise(rest * 61.0),
    vnoise(rest * 61.0 + 7.3),
    vnoise(rest * 61.0 + 13.9)) - 0.5;
  N = normalize(N - (g - N * dot(g, N)) * 6.0 + grit * 0.3);

  // Weathered grey plates over cold char, the way basalt breaks.
  float plate = smoothstep(0.44 + (0.5 - bestV) * 0.28, 0.74, coarse + grain * 0.14);
  // The grain breaks the plates up, so they read as flaking stone.
  plate *= smoothstep(0.30, 0.62, grain);
  vec3 albedo = mix(ROCK, ROCK + vec3(0.34, 0.335, 0.325), plate * 0.16);
  albedo *= (0.86 + grain * 0.38) * (0.55 + bestV * 0.5);

    vec3 col = shade(P, N, V, albedo, 0.0, 26.0, uGround);

  // Heat is depth, and only depth: the faces that look into the hollow.
  float depth = length(rest);
  float heat = 1.0 - smoothstep(uInner * 0.96, uInner * 1.55, depth);
  heat *= heat;
  float vein = smoothstep(0.34, 0.78, fbm(rest * 5.0 + vec3(0.0, uTime * 0.35, 0.0)));
  float melt = heat * (0.35 + vein * 0.9);
  col += mix(LAVA, HOT, vein * 0.8) * melt * uHeat;

  // Fissures: the ridge of one smooth noise, a few long thin curves, with a
  // dim skirt so the line reads as a split with heat behind it.
  float fis = vnoise(rest * 1.6 + 3.7);
  float ridge = 1.0 - abs(fis - 0.5) * 22.0;
  float mask = smoothstep(0.44, 0.74, fbm(rest * 0.9 + 9.1));
  float line = smoothstep(0.5, 1.0, ridge) * mask;
  float skirt = smoothstep(-1.6, 1.0, ridge) * mask;
  col += mix(LAVA, HOT, line * 0.8) * (line * 2.6 + skirt * skirt * 0.55) * uHeat * 0.35;

  fragColor = vec4(encode(aces(col)), 1.0);
}