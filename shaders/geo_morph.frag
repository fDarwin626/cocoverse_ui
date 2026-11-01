#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;
uniform float uUnit;
uniform float uPixel;
uniform vec3 uMetal;
uniform vec3 uRoomTop;
uniform vec3 uRoomBottom;
uniform vec3 uGlow;
uniform vec3 uMorph;
uniform vec4 uLook;
uniform vec4 uCs;
uniform float uSteps;

out vec4 fragColor;

// The original's camera: 2.6 units back, looking down -z with a focal length of 1.5.
const float CAMERA_Z = 2.6;
const float FOCAL = 1.5;
// Hard ceiling for the march loop. uSteps decides how many are really used.
const int MAX_STEPS = 90;
const float STEP = 0.85;
const float HIT = 0.0008;

// uLook: x = size of the solid, y = highlight tightness, z = metalness,
// w = rim light strength. uCs: cos(yaw), sin(yaw), cos(pitch), sin(pitch).
// uMorph: x = id of the first shape, y = id of the second, z = how far the
// first has become the second. Ids: 0 box, 1 sphere, 2 octahedron, 3 torus.

float sdSphere(vec3 p, float r) {
  return length(p) - r;
}

float sdBox(vec3 p, float b) {
  vec3 q = abs(p) - vec3(b);
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdOctahedron(vec3 p, float s) {
  p = abs(p);
  return (p.x + p.y + p.z - s) * 0.57735027;
}

float sdTorus(vec3 p, float big, float small) {
  vec2 q = vec2(length(p.xz) - big, p.y);
  return length(q) - small;
}

float sdShape(vec3 p, float id) {
  float s = uLook.x;
  if (id < 0.5) {
    return sdBox(p, s * 0.78);
  } else if (id < 1.5) {
    return sdSphere(p, s);
  } else if (id < 2.5) {
    return sdOctahedron(p, s * 1.25);
  }
  return sdTorus(p, s * 0.72, s * 0.34);
}

// The two branches below depend only on uniforms, so every pixel takes the
// same one and a settled shape costs a single distance function.
float map(vec3 p) {
  float a = sdShape(p, uMorph.x);
  if (uMorph.z <= 0.0) {
    return a;
  }
  float b = sdShape(p, uMorph.y);
  if (uMorph.z >= 1.0) {
    return b;
  }
  return mix(a, b, uMorph.z);
}

vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.0015, 0.0);
  return normalize(vec3(
      map(p + e.xyy) - map(p - e.xyy),
      map(p + e.yxy) - map(p - e.yxy),
      map(p + e.yyx) - map(p - e.yyx)));
}

// Turns by yaw around the vertical axis, then by pitch around the horizontal one.
vec3 turn(vec3 v) {
  v = vec3(uCs.x * v.x + uCs.y * v.z, v.y, -uCs.y * v.x + uCs.x * v.z);
  return vec3(v.x, uCs.z * v.y - uCs.w * v.z, uCs.w * v.y + uCs.z * v.z);
}

// What a mirror-like surface would show in this direction: a gradient from
// the bottom colour to the top colour, plus a bright key light and a soft fill.
vec3 room(vec3 dir) {
  vec3 base = mix(uRoomBottom, uRoomTop, clamp(dir.y * 0.5 + 0.5, 0.0, 1.0));
  float key = pow(max(dot(dir, normalize(vec3(0.5, 0.75, 0.4))), 0.0), 26.0);
  float fill = pow(max(dot(dir, normalize(vec3(-0.6, -0.2, 0.75))), 0.0), 10.0);
  return base + vec3(1.0) * (key * 1.7 + fill * 0.35);
}

vec3 shade(vec3 p, vec3 rd) {
  vec3 n = normalAt(p);
  vec3 v = normalize(turn(-rd));

  vec3 reflected = room(reflect(-v, n));

  vec3 body = mix(
      uMetal * (0.25 + max(dot(n, normalize(vec3(0.4, 0.8, 0.5))), 0.0) * 0.8),
      reflected * uMetal,
      uLook.z);

  float fres = pow(1.0 - max(dot(n, v), 0.0), 4.0);
  vec3 col = mix(body, reflected, fres * 0.7);

  vec3 L = normalize(vec3(0.5, 0.75, 0.4));
  vec3 h = normalize(L + v);
  col += vec3(1.0) * pow(max(dot(n, h), 0.0), uLook.y) * 1.1;

  col += uGlow * fres * uLook.w * 3.0;
  return clamp(col, 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = vec2(frag.x - uOrigin.x, uOrigin.y - frag.y) / uUnit;

  vec3 ro = vec3(0.0, 0.0, CAMERA_Z);
  vec3 rd = normalize(vec3(uv, -FOCAL));
  // The angle one device pixel covers.
  float pix = uPixel / (uUnit * FOCAL);

  // The original turns the point it samples, so turn the ray once instead.
  vec3 roT = turn(ro);
  vec3 rdT = turn(rd);

  // No shape reaches further than the corner of the box, so every ray starts
  // where it enters that sphere and rays that miss it stop here.
  float outer = 1.36 * uLook.x + 0.002;
  float b = dot(roT, rdT);
  float disc = b * b - (dot(roT, roT) - outer * outer);
  if (disc <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float root = sqrt(disc);
  float t = max(-b - root, 0.0);
  float tFar = -b + root;

  bool hit = false;
  float dmin = 1.0e9;
  float tmin = t;
  for (int i = 0; i < MAX_STEPS; i++) {
    if (float(i) >= uSteps) {
      break;
    }
    float d = map(roT + rdT * t);
    if (d < HIT) {
      hit = true;
      break;
    }
    float ang = d / t;
    if (ang < dmin) {
      dmin = ang;
      tmin = t;
    }
    t += d * STEP;
    if (t > tFar) {
      break;
    }
  }

  if (hit) {
    fragColor = vec4(shade(roT + rdT * t, rd), 1.0);
  } else if (dmin < 0.7 * pix) {
    // A ray that only skims the solid gets partial coverage, which softens the edge.
    float cov = 1.0 - smoothstep(0.0, pix, dmin / 0.7);
    fragColor = vec4(shade(roT + rdT * tmin, rd) * cov, cov);
  } else {
    fragColor = vec4(0.0);
  }
}