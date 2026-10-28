#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;
uniform float uRadius;
uniform vec4 uMods;
uniform float uSharp;
uniform float uAmp;
uniform float uShine;
uniform float uGlow;
uniform float uYaw;
uniform float uPitch;
uniform float uSpan;
uniform float uObjScale;
uniform float uSteps;
uniform float uRelax;
uniform float uPixel;
uniform vec2 uBand;
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uBright;
uniform vec3 uRim;

out vec4 fragColor;

// Radius of the shell with no waves on it.
const float BASE = 0.16;
// Camera distance of the original (1 / its perspective of 0.15).
const float CAMERA_DISTANCE = 6.666667;
// Hard ceiling for the march loop. uSteps decides how many are really used.
const int MAX_STEPS = 56;
// Halvings used to pin down the surface once the march steps inside it.
const int BISECT_STEPS = 4;
// Caps the slope estimate so the pinched poles cannot stall the march.
const float GRAD_MAX = 24.0;
const float TINY = 1.0e-4;
const float PI = 3.14159265;
// A needle thinner than BAND_LO pixels is averaged away, one wider than BAND_HI is kept.
const float BAND_LO = 3.0;
const float BAND_HI = 8.0;
// Smallest pixel size, in shell units, that the shape is smoothed for. It keeps
// the poles looking the same at every on-screen size. Raise it for smoother
// poles, lower it for more needles.
const float MIN_BAND_PX = 0.0035;
const vec3 KEY = vec3(-0.42, 0.6, 0.68);
const vec3 FILL = vec3(0.6, -0.35, 0.72);

// pow(|x|, uSharp) in .x, and the slope factor uSharp * |x|^(uSharp - 1) * sign(x) in .y.
vec2 powAbs(float x) {
  float a = max(abs(x), TINY);
  float p = pow(a, uSharp - 1.0);
  return vec2(p * a, uSharp * p * (x < 0.0 ? -1.0 : 1.0));
}

// For the direction (th, ph): the radius in .x, its slope along th in .y and
// along ph in .z. The radius is a sum of four waves, two that only depend on
// ph and two that only depend on th.
vec3 shape(float th, float ph, float reach) {
  float a1 = uMods.x * ph;
  float a2 = uMods.y * ph;
  float a3 = uMods.z * th;
  float a4 = uMods.w * th;
  float s1 = sin(a1);
  float c1 = cos(a1);
  float s2 = sin(a2);
  float c2 = cos(a2);
  float s3 = sin(a3);
  float c3 = cos(a3);
  float s4 = sin(a4);
  float c4 = cos(a4);

  vec2 w1 = powAbs(s1);
  vec2 w2 = powAbs(c2);
  vec2 w3 = powAbs(s3);
  vec2 w4 = powAbs(c4);

  // Needles thinner than a few pixels would only sparkle, so they fade to
  // their average. reach is the length of one radian of ph, in pixels.
  float k1 = smoothstep(BAND_LO, BAND_HI,
      reach * uBand.y * PI / max(abs(uMods.x), 0.01));
  float k2 = smoothstep(BAND_LO, BAND_HI,
      reach * uBand.y * PI / max(abs(uMods.y), 0.01));
  float v1 = uBand.x + k1 * (w1.x - uBand.x);
  float v2 = uBand.x + k2 * (w2.x - uBand.x);

  float radius = BASE + (v1 + v2 + w3.x + w4.x) * uAmp;
  float slopeTh = (w3.y * c3 * uMods.z - w4.y * s4 * uMods.w) * uAmp;
  float slopePh = (k1 * w1.y * c1 * uMods.x - k2 * w2.y * s2 * uMods.y) * uAmp;
  return vec3(radius, slopeTh, slopePh);
}

// cs holds cos(yaw), sin(yaw), cos(pitch), sin(pitch).
// Turns by yaw around the vertical axis, then by pitch around the horizontal one.
vec3 toWorld(vec3 v, vec4 cs) {
  v = vec3(cs.x * v.x + cs.y * v.z, v.y, -cs.y * v.x + cs.x * v.z);
  return vec3(v.x, cs.z * v.y - cs.w * v.z, cs.w * v.y + cs.z * v.z);
}

// The exact inverse of toWorld.
vec3 toObject(vec3 v, vec4 cs) {
  v = vec3(v.x, cs.z * v.y + cs.w * v.z, -cs.w * v.y + cs.z * v.z);
  return vec3(cs.x * v.x - cs.y * v.z, v.y, cs.y * v.x + cs.x * v.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = (frag - uCenter) / uRadius;
  p.y = -p.y;

  vec4 cs = vec4(cos(uYaw), sin(uYaw), cos(uPitch), sin(uPitch));

  // The original's camera: a small field of view far away, sized so the
  // shorter side of the box spans uSpan units at the middle of the shell.
  vec2 plane = p * (uSpan * 0.5);
  vec3 rayWorld = normalize(vec3(plane, -CAMERA_DISTANCE));
  vec3 ro = toObject(vec3(0.0, 0.0, CAMERA_DISTANCE) / uObjScale, cs);
  vec3 rd = toObject(rayWorld, cs);

  // Only the sphere that can hold the tallest spike needs to be marched.
  float outer = BASE + 4.0 * uAmp + 0.002;
  float b = dot(ro, rd);
  float disc = b * b - (dot(ro, ro) - outer * outer);
  if (disc <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float root = sqrt(disc);
  float tNear = max(-b - root, 0.0);
  float tFar = -b + root;

  // Size of one device pixel inside the shell. uPixel is 1 / devicePixelRatio.
  float pxObj = (uSpan * 0.5 / uRadius) / uObjScale * uPixel;
  float pxBand = max(pxObj, MIN_BAND_PX);
  float hitDist = 0.25 * pxObj;
  float minStep = 0.5 * hitDist;

  float t = tNear;
  float tPrev = tNear;
  float bestGap = 1.0e9;
  float bestT = tNear;
  float hitF = 1.0;
  bool hit = false;

  for (int i = 0; i < MAX_STEPS; i++) {
    if (float(i) >= uSteps || t > tFar) {
      break;
    }
    vec3 q = ro + rd * t;
    float len = max(length(q), TINY);
    float cy = clamp(q.y / len, -1.0, 1.0);
    float sinT = max(sqrt(max(1.0 - cy * cy, 0.0)), 1.0e-3);
    vec3 sh = shape(acos(cy), atan(q.z, q.x), len * sinT / pxBand);

    // Distance to the shell, estimated from the signed gap and the slope.
    float f = len - sh.x;
    float gx = sh.y / len;
    float gy = sh.z / (len * sinT);
    float dist = f / min(sqrt(1.0 + gx * gx + gy * gy), GRAD_MAX);

    if (dist < bestGap) {
      bestGap = dist;
      bestT = t;
    }
    if (dist < hitDist) {
      hit = true;
      hitF = f;
      break;
    }
    tPrev = t;
    t += max(dist * uRelax, minStep);
  }

  // The last step landed inside the shell: halve back toward the surface.
  if (hit && hitF < 0.0) {
    float lo = tPrev;
    float hi = t;
    for (int k = 0; k < BISECT_STEPS; k++) {
      float mid = 0.5 * (lo + hi);
      vec3 q = ro + rd * mid;
      float len = max(length(q), TINY);
      float cy = clamp(q.y / len, -1.0, 1.0);
      float sinB = max(sqrt(max(1.0 - cy * cy, 0.0)), 1.0e-3);
      float f = len - shape(acos(cy), atan(q.z, q.x), len * sinB / pxBand).x;
      if (f > 0.0) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    t = hi;
  }

  // A ray that only skims the shell gets partial coverage, which softens the edge.
  float coverage = 1.0;
  float tShade = t;
  if (!hit) {
    coverage = 1.0 - clamp((bestGap - hitDist) / (pxObj - hitDist), 0.0, 1.0);
    if (coverage <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    tShade = bestT;
  }

  // Surface normal from the slopes of the radius, which is the same normal
  // the original builds from neighbouring vertices.
  vec3 q = ro + rd * tShade;
  vec3 dir = q / max(length(q), TINY);
  float cy = clamp(dir.y, -1.0, 1.0);
  float sinT = max(sqrt(max(1.0 - cy * cy, 0.0)), 1.0e-3);
  vec3 sh = shape(acos(cy), atan(dir.z, dir.x), length(q) * sinT / pxBand);
  float hz = max(length(dir.xz), TINY);
  float cosP = dir.x / hz;
  float sinP = dir.z / hz;
  vec3 eTh = vec3(cy * cosP, -sinT, cy * sinP);
  vec3 ePh = vec3(-sinP, 0.0, cosP);
  vec3 nObj = normalize(sh.x * dir - sh.y * eTh - (sh.z / sinT) * ePh);

  vec3 n = toWorld(nObj, cs);
  vec3 posWorld = toWorld(q, cs) * uObjScale;
  vec3 view = normalize(vec3(0.0, 0.0, CAMERA_DISTANCE) - posWorld);

  // How far this point sticks out, from 0 at the base to 1 at the tallest spike.
  float height = (sh.x - BASE) / max(uAmp * 4.0, 0.0001);

  float key = max(dot(n, KEY), 0.0);
  float fill = max(dot(n, FILL), 0.0) * 0.35;
  vec3 halfway = normalize(KEY + view);
  float spec = pow(max(dot(n, halfway), 0.0), uShine);

  vec3 col = mix(uDeep, uMid, smoothstep(0.05, 0.55, height));
  col = mix(col, uBright, smoothstep(0.6, 1.0, height));
  col *= 0.35 + key * 0.85 + fill;

  float fres = pow(1.0 - max(dot(n, view), 0.0), 4.0);
  col += uRim * fres * (0.5 + uGlow * 6.0);
  col += uBright * spec * 0.5;

  vec3 rgb = clamp(col, 0.0, 1.0);
  fragColor = vec4(rgb * coverage, coverage);
}
