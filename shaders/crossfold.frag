#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// Three chamfered bars, each a convex body of 26 planes, ray cast per pixel.
// The surface is the website's mirror material: what makes it read as metal
// is the environment it reflects (a hard horizon and a few bright softboxes).

uniform vec2 uCenter;     // px position of the middle of the figure, y down
uniform float uScale;     // view units per pixel
uniform vec3 uRight;      // camera right, in scene space
uniform vec3 uUp;         // camera up
uniform vec3 uFwd;        // camera forward
uniform vec3 uCam;        // camera position
uniform vec3 uBase;       // the one colour, in linear light
uniform float uRough;     // 0..1
uniform float uReflect;   // 0..1 (metallic only)
uniform float uMetal;     // 1 metallic, 0 matte
uniform float uGrid;      // samples per side: 1 or 2
uniform vec4 uPlane[78];  // 26 planes a bar: world normal, offset

out vec4 fragColor;

const float PI = 3.14159265359;

const vec3 SKY_LOW = vec3(0.30, 0.35, 0.47);
const vec3 SKY_HIGH = vec3(0.80, 0.84, 0.95);
const vec3 GROUND_DEEP = vec3(0.0035, 0.0038, 0.0050);
const vec3 GROUND_NEAR = vec3(0.052, 0.055, 0.066);
const vec3 HORIZON = vec3(0.55, 0.53, 0.49);

const vec3 BOX_A_DIR = vec3(-0.5774, 0.5774, -0.5774);
const vec3 BOX_B_DIR = vec3(0.5774, -0.5774, -0.5774);
const vec3 BOX_C_DIR = vec3(-0.5774, -0.5774, 0.5774);
const vec3 BOX_A = vec3(1.90, 1.90, 1.96);
const vec3 BOX_B = vec3(1.30, 1.26, 1.20);
const vec3 BOX_C = vec3(1.00, 1.03, 1.12);

float boxLobe(vec3 R, vec3 d, float sharp) {
  return pow(max(dot(R, d), 0.0), sharp);
}

vec3 envSample(vec3 R, float r) {
  float t = clamp(R.y * 0.5 + 0.5, 0.0, 1.0);
  vec3 ground = mix(GROUND_DEEP, GROUND_NEAR, smoothstep(-0.85, -0.02, R.y));
  vec3 sky = mix(SKY_LOW, SKY_HIGH, smoothstep(0.02, 0.90, R.y));
  float e = 0.006 + 0.45 * r * r;
  vec3 c = mix(ground, sky, smoothstep(0.5 - e, 0.5 + e, t));
  c += HORIZON * exp(-(R.y * R.y) / (0.004 + 0.30 * r * r)) * (1.0 - 0.6 * r);
  c += BOX_A * boxLobe(R, BOX_A_DIR, mix(500.0, 5.0, r));
  c += BOX_B * boxLobe(R, BOX_B_DIR, mix(260.0, 4.0, r));
  c += BOX_C * boxLobe(R, BOX_C_DIR, mix(200.0, 3.0, r));
  return c;
}

float dGGX(float NoH, float a) {
  float a2 = a * a;
  float d = NoH * NoH * (a2 - 1.0) + 1.0;
  return a2 / (PI * d * d);
}

float vSmith(float NoV, float NoL, float a) {
  float a2 = a * a;
  float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
  float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
  return 0.5 / max(gv + gl, 0.00001);
}

vec3 fSchlick(vec3 f0, float u) {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - u, 0.0, 1.0), 5.0);
}

vec3 lightTerm(vec3 N, vec3 V, vec3 L, vec3 f0, float a, vec3 col) {
  vec3 H = normalize(L + V);
  float NoL = max(dot(N, L), 0.0);
  float NoV = max(dot(N, V), 0.0001);
  float NoH = max(dot(N, H), 0.0);
  float VoH = clamp(dot(V, H), 0.0, 1.0);
  return dGGX(NoH, a) * vSmith(NoV, NoL, a) * fSchlick(f0, VoH) * col * NoL;
}

vec3 aces(vec3 x) {
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 encode(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  vec3 lo = c * 12.92;
  vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
  return mix(hi, lo, step(c, vec3(0.0031308)));
}

// Polished metal: what it reflects does all the work.
vec3 metalShade(vec3 N, vec3 V) {
  float r = clamp(uRough, 0.03, 1.0);
  float a = r * r;
  vec3 f0 = clamp(uBase * uReflect, vec3(0.0), vec3(1.0));
  float NoV = clamp(dot(N, V), 0.0001, 1.0);
  vec3 R = reflect(-V, N);
  vec3 Fe = f0 + (max(vec3(1.0 - r), f0) - f0) * pow(1.0 - NoV, 5.0);
  vec3 col = envSample(R, r) * Fe;
  col += lightTerm(N, V, BOX_A_DIR, f0, a, vec3(0.55, 0.55, 0.57));
  col += lightTerm(N, V, BOX_B_DIR, f0, a, vec3(0.22, 0.21, 0.20));
  return col;
}

// Matt plastic: soft light on the colour, a faint reflection, a small glint.
vec3 matteShade(vec3 N, vec3 V) {
  float r = clamp(uRough, 0.03, 1.0);
  float NoV = clamp(dot(N, V), 0.0, 1.0);
  vec3 R = reflect(-V, N);
  float up = N.y * 0.5 + 0.5;
  vec3 amb = mix(vec3(0.10, 0.10, 0.12), vec3(0.62, 0.64, 0.70), up);
  float kA = max(dot(N, BOX_A_DIR), 0.0);
  float kB = max(dot(N, BOX_B_DIR), 0.0);
  float kC = max(dot(N, BOX_C_DIR), 0.0);
  vec3 light = amb + vec3(1.05, 1.05, 1.08) * kA + vec3(0.35, 0.34, 0.32) * kB
      + vec3(0.28, 0.30, 0.36) * kC + vec3(0.22) * NoV;
  vec3 diffuse = uBase * light * 0.78;
  float fres = 0.045 + 0.955 * pow(1.0 - NoV, 5.0);
  vec3 refl = envSample(R, max(r, 0.35)) * fres * (1.0 - 0.5 * r);
  vec3 H = normalize(BOX_A_DIR + V);
  float spec = pow(max(dot(N, H), 0.0), mix(120.0, 10.0, r)) * (0.10 + 0.25 * (1.0 - r));
  return diffuse + refl + vec3(spec);
}

vec4 trace(vec2 frag) {
  vec3 ro = uCam;
  vec3 rd = normalize(
      uRight * ((frag.x - uCenter.x) * uScale) +
      uUp * ((uCenter.y - frag.y) * uScale) +
      uFwd);

  // Nothing to find outside the ball that holds the figure.
  float bq = dot(ro, rd);
  float cq = dot(ro, ro) - 3.8025;
  if (bq * bq - cq < 0.0) return vec4(0.0);

  float bestT = 1e9;
  vec3 bestN = vec3(0.0);
  for (int s = 0; s < 3; s++) {
    float t0 = 0.0;
    float t1 = 1e9;
    vec3 n0 = vec3(0.0);
    bool miss = false;
    for (int k = 0; k < 26; k++) {
      vec4 pl = uPlane[s * 26 + k];
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
    }
  }
  if (bestT > 1e8) return vec4(0.0);

  vec3 P = ro + rd * bestT;
  vec3 N = normalize(bestN);
  vec3 V = normalize(ro - P);
  vec3 col;
  if (uMetal > 0.5) {
    col = metalShade(N, V);
  } else {
    col = matteShade(N, V);
  }
  return vec4(encode(aces(col)), 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec4 acc = vec4(0.0);
  float n = 0.0;
  // One ray, or four for smooth edges.
  for (int j = 0; j < 2; j++) {
    for (int i = 0; i < 2; i++) {
      if (float(i) >= uGrid || float(j) >= uGrid) continue;
      vec2 off = vec2(
          (float(i) + 0.5) / uGrid - 0.5,
          (float(j) + 0.5) / uGrid - 0.5);
      acc += trace(frag + off);
      n += 1.0;
    }
  }
  fragColor = acc / max(n, 1.0);
}