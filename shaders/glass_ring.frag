#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uHasPlate;
uniform vec3 uRotA;
uniform vec3 uRotB;
uniform vec3 uRotC;
uniform vec2 uCenter;
uniform float uScale;
uniform float uTube;
uniform float uChromatic;
uniform float uFrost;
uniform float uSamples;
uniform vec3 uTint;

uniform sampler2D uPlate;

out vec4 fragColor;

const float CAMERA = 5.0;
const float TAN_HALF = 0.41421356;
const float RING_RADIUS = 0.8;
const float IOR = 1.5;

// The rotation is passed as the three columns of an orthonormal matrix.
vec3 toObject(vec3 v) {
  return vec3(dot(uRotA, v), dot(uRotB, v), dot(uRotC, v));
}

vec3 toView(vec3 v) {
  return uRotA * v.x + uRotB * v.y + uRotC * v.z;
}

float ringDistance(vec3 p) {
  return length(vec2(length(p.xy) - RING_RADIUS, p.z)) - uTube;
}

float rand(vec2 co) {
  return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// The backdrop. u is in screen space with y pointing up.
vec4 plate(vec2 u) {
  if (uHasPlate < 0.5) {
    return vec4(0.0);
  }
  vec2 c = clamp(u, 0.0, 1.0);
  return texture(uPlate, vec2(c.x, 1.0 - c.y));
}

// A dark studio with three soft lights: left, right and top.
vec3 environment(vec3 dir) {
  vec3 left = normalize(vec3(-0.9, 0.15, 0.45));
  vec3 right = normalize(vec3(0.9, 0.1, 0.45));
  vec3 top = normalize(vec3(0.0, 1.0, 0.35));
  float boxes = smoothstep(0.80, 0.97, dot(dir, left))
      + smoothstep(0.80, 0.97, dot(dir, right))
      + smoothstep(0.82, 0.97, dot(dir, top)) * 0.9;
  return vec3(0.06) + vec3(boxes) * 1.6;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 suv = vec2(frag.x / uSize.x, 1.0 - frag.y / uSize.y);
  vec2 ndc = suv * 2.0 - 1.0;
  float aspect = uSize.x / uSize.y;

  vec3 viewRay = normalize(vec3(ndc.x * TAN_HALF * aspect, ndc.y * TAN_HALF, -1.0));
  vec3 center = vec3(uCenter, -CAMERA);
  vec3 ro = toObject(-center) / uScale;
  vec3 rd = toObject(viewRay);

  // Skip rays that miss the sphere that wraps the ring.
  float boundR = RING_RADIUS + uTube;
  float b = dot(ro, rd);
  float c = dot(ro, ro) - boundR * boundR;
  float h = b * b - c;
  if (h < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  h = sqrt(h);
  float t = max(-b - h, 0.0);
  float tMax = -b + h;

  // Half a logical pixel, in object units, used to soften the silhouette.
  float pixel = TAN_HALF * CAMERA / (uSize.y * uScale);
  float minD = 1.0e9;
  float tBest = t;
  bool hit = false;
  for (int i = 0; i < 64; i++) {
    if (t > tMax) {
      break;
    }
    float d = ringDistance(ro + rd * t);
    if (d < minD) {
      minD = d;
      tBest = t;
    }
    if (d < 0.0012) {
      hit = true;
      break;
    }
    t += d * 0.9;
  }
  if (!hit && minD > pixel) {
    fragColor = vec4(0.0);
    return;
  }
  float coverage = hit ? 1.0 : 1.0 - smoothstep(0.0, pixel, minD);

  // Surface point and normal (the normal of a ring is known exactly).
  vec3 pObj = ro + rd * tBest;
  float rho = max(length(pObj.xy), 1.0e-4);
  vec2 q = vec2(rho - RING_RADIUS, pObj.z);
  vec3 nObj = normalize(vec3(pObj.xy / rho * q.x, q.y));

  vec3 viewPos = center + uScale * toView(pObj);
  vec3 normal = normalize(toView(nObj));
  vec3 toEye = normalize(-viewPos);
  float facing = max(dot(normal, toEye), 0.0);
  float fresnel = pow(1.0 - facing, 4.0);

  // How far the glass bends the view, plus a gentle lens toward the middle.
  vec2 lens = (suv - 0.5) * 0.15 * facing * facing;
  vec3 bent = refract(-toEye, normal, 1.0 / IOR);
  vec2 offset = bent.xy * 0.2 - lens;

  vec3 reflection = environment(reflect(-toEye, normal));

  // Sample the backdrop three times, shifted a little for red, green and blue.
  float spread = uChromatic * 0.1;
  vec2 uvR = suv + offset * (1.0 + spread);
  vec2 uvG = suv + offset;
  vec2 uvB = suv + offset * (1.0 - spread);

  vec3 seen = vec3(0.0);
  float seenAlpha = 0.0;
  float taps = uSamples;
  if (taps < 0.5) {
    seen.r = plate(uvR).r;
    vec4 g = plate(uvG);
    seen.g = g.g;
    seenAlpha = g.a;
    seen.b = plate(uvB).b;
  } else {
    float turn = rand(frag) * 6.2831853;
    float radius = 0.0;
    float blur = uFrost * 0.025;
    for (int i = 0; i < 8; i++) {
      if (float(i) >= taps) {
        break;
      }
      float angle = float(i) * 2.39996323 + turn;
      radius += 1.0 / taps;
      vec2 jitter = vec2(cos(angle), sin(angle)) * radius * blur;
      seen.r += plate(uvR + jitter).r;
      vec4 g = plate(uvG + jitter);
      seen.g += g.g;
      seenAlpha += g.a;
      seen.b += plate(uvB + jitter).b;
    }
    seen /= taps;
    seenAlpha /= taps;
  }

  vec3 clearGlass = mix(uTint, reflection, 0.5);
  vec3 through = mix(clearGlass, seen * uTint, seenAlpha);
  vec3 color = mix(through, reflection, fresnel * 0.8);

  float baseAlpha = max(0.25, fresnel * 0.85);
  float alpha = mix(baseAlpha, 1.0, seenAlpha) * coverage;
  fragColor = vec4(min(color, vec3(1.0)) * alpha, alpha);
}