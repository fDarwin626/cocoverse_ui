#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uYaw;
uniform float uPitch;
uniform float uSquash;
uniform float uHover;
uniform vec2 uPointer;
uniform float uDetail;
uniform float uScale;
uniform float uTurbulence;
uniform float uSpecks;
uniform vec3 uDeep;
uniform vec3 uBase;
uniform vec3 uCore;
uniform vec3 uHighlight;

out vec4 fragColor;

float hash3(vec3 p) {
  return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(41.3, 289.7))) * 43758.5453);
}

// Smooth value noise in the range -1 to 1.
float noise3(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  vec3 u = f * f * (3.0 - 2.0 * f);
  float a = hash3(i);
  float b = hash3(i + vec3(1.0, 0.0, 0.0));
  float c = hash3(i + vec3(0.0, 1.0, 0.0));
  float d = hash3(i + vec3(1.0, 1.0, 0.0));
  float e = hash3(i + vec3(0.0, 0.0, 1.0));
  float g = hash3(i + vec3(1.0, 0.0, 1.0));
  float h = hash3(i + vec3(0.0, 1.0, 1.0));
  float k = hash3(i + vec3(1.0, 1.0, 1.0));
  float near = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  float far = mix(mix(e, g, u.x), mix(h, k, u.x), u.y);
  return mix(near, far, u.z) * 2.0 - 1.0;
}

float fbm(vec3 p, float octaves) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 3; i++) {
    if (float(i) >= octaves) {
      break;
    }
    sum += amplitude * noise3(p);
    p = p * 2.03 + vec3(1.7, -3.1, 2.3);
    amplitude *= 0.5;
  }
  return sum;
}

// Rotates v around the vertical axis by yaw, then around the horizontal axis by pitch.
vec3 turn(vec3 v, float yaw, float pitch) {
  float cy = cos(yaw);
  float sy = sin(yaw);
  v = vec3(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z);
  float cp = cos(pitch);
  float sp = sin(pitch);
  return vec3(v.x, cp * v.y - sp * v.z, sp * v.y + cp * v.z);
}

vec3 rotateAround(vec3 v, vec3 axis, float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vec3 screenBlend(vec3 a, vec3 b) {
  return 1.0 - (1.0 - a) * (1.0 - clamp(b, 0.0, 1.0));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float radiusPx = 0.5 * min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / radiusPx;
  p.y = -p.y;

  // The jelly squash, then the position inside a unit disc.
  vec2 q = p / uScale;
  q *= vec2(1.0 - uSquash * 0.5, 1.0 + uSquash * 0.5);
  float r = length(q);
  if (r > 1.5) {
    fragColor = vec4(0.0);
    return;
  }

  float px = 1.0 / (radiusPx * uScale);
  vec2 dir = q / max(r, 1.0e-4);
  vec3 rimA = mix(uCore, vec3(1.0), 0.35);
  vec3 rimB = mix(uHighlight, vec3(1.0), 0.45);
  float cyanAmt = smoothstep(0.1, 0.9, dot(dir, normalize(vec2(0.6, 0.8))));
  vec3 rimColor = mix(rimA, rimB, cyanAmt * 0.7);

  // The faint halo outside the sphere.
  float halo = exp(-max(r - 1.0, 0.0) / 0.05) * 0.07 * (1.0 + uHover * 0.5);
  if (r > 1.0 + 2.0 * px) {
    fragColor = vec4(rimColor * halo, halo);
    return;
  }

  float rr = min(r, 0.999);
  float z = sqrt(max(0.0, 1.0 - rr * rr));
  vec3 n = vec3(q * (rr / max(r, 1.0e-4)), z);
  n = turn(n, uYaw, uPitch);

  float phase = uTime * 0.5236;
  vec3 rockAxis = normalize(vec3(0.342, 0.94, 0.0));
  vec3 m = rotateAround(n, rockAxis, 0.35 * sin(phase));
  vec3 P = m * 1.7 + vec3(12.1, 6.4, 14.8);
  vec3 drift = vec3(cos(phase), sin(phase), 0.0) * 0.3;

  // Warp the position with noise so the surface folds and flows.
  vec3 w = vec3(0.0);
  if (uDetail > 0.5) {
    w = vec3(
        noise3(P * 0.8 + drift),
        noise3(P * 0.8 + vec3(5.2, 1.3, 2.8) + drift.yzx),
        noise3(P * 0.8 + vec3(-3.7, 8.1, -1.9) - drift.zxy));
  }
  vec3 Pw = P + 0.9 * uTurbulence * w;

  float f = fbm(Pw + 0.5 * drift.zxy, 1.0 + uDetail);
  float t = clamp(f * 0.8 + 0.5, 0.0, 1.0);

  // Folds: where the noise crosses zero, the surface reads as a crease.
  float n1 = noise3(Pw * 1.1 + vec3(2.0, -1.0, 0.5));
  float n2 = noise3(Pw * 2.3 + vec3(-4.1, 3.3, 1.7));
  float height = 0.65 * abs(n1) + 0.35 * abs(n2);
  float crease = 1.0 - smoothstep(0.0, 0.06, abs(n1));

  vec3 col = mix(uDeep, uBase, smoothstep(0.15, 0.65, t));
  col = mix(col, uDeep * 0.55, crease * 0.45);

  // Cheap relief: compare the height with a point shifted toward the light.
  float relief = 1.0;
  if (uDetail > 1.5) {
    vec3 shifted = Pw + normalize(vec3(-0.45, 0.6, 0.65)) * 0.06;
    float height2 = 0.65 * abs(noise3(shifted * 1.1 + vec3(2.0, -1.0, 0.5)))
        + 0.35 * abs(noise3(shifted * 2.3 + vec3(-4.1, 3.3, 1.7)));
    relief = clamp(1.0 + (height - height2) / 0.06 * 0.35, 0.6, 1.5);
  }
  col *= relief * (0.88 + 0.22 * t);

  // The glowing core, low on the sphere.
  vec2 warped = q + w.xy * 0.3;
  float blobA = 1.0 - smoothstep(0.0, 0.8,
      length((warped - vec2(0.03, -0.06)) * vec2(0.8, 1.15)));
  float blobB = 1.0 - smoothstep(0.0, 0.4, length(warped - vec2(-0.08, -0.72)));
  float blotch = 0.5 + 0.5 * noise3(Pw * 0.9 + vec3(11.0, -4.0, 2.0));
  float glow = clamp(max(blobA, blobB * 0.85) * (0.75 + 0.5 * blotch), 0.0, 1.0);
  glow = smoothstep(0.05, 0.8, glow);
  float fres = pow(1.0 - z, 2.0);
  glow = max(glow, fres * (1.0 - 0.75 * cyanAmt) * (0.6 + 0.4 * blotch) * 0.85);

  // Touch makes the glow bloom where the finger is.
  vec2 toTouch = q - uPointer;
  glow = max(glow, exp(-dot(toTouch, toTouch) * 6.0) * uHover * 0.9);

  vec3 lavender = mix(uBase, uCore, 0.55);
  vec3 coreColor = mix(lavender, uCore, smoothstep(0.3, 0.8, t));
  col = mix(col, coreColor, smoothstep(0.0, 0.7, glow));
  col = mix(col, uCore * 1.08, smoothstep(0.6, 1.0, glow) * 0.6);

  // Thin bright veins, mostly in the upper part and away from the glow.
  float vein = pow(1.0 - abs(n1), 12.0);
  float veinGlow = pow(1.0 - abs(n1), 3.0) * 0.35;
  float region = smoothstep(0.35, 0.75, blotch) * (1.0 - 0.8 * glow)
      * smoothstep(-0.5, 0.8, dot(q, normalize(vec2(0.25, 1.0))));
  col = screenBlend(col, uHighlight * (vein + veinGlow) * region * 0.8);

  // Small white specks on a flattened map of the surface.
  vec2 st = m.xy / max(1.0 + m.z, 0.25);
  vec2 cell = st * 14.0;
  vec2 id = floor(cell);
  vec2 within = fract(cell);
  float chance = hash2(id + 3.1);
  vec2 spot = 0.2 + 0.6 * vec2(hash2(id + 17.3), hash2(id + 41.7));
  float dist = length(within - spot) / 14.0;
  float tone = hash2(id + 73.1);
  float radius = 0.012 * (0.6 + 0.8 * tone);
  float speck = step(chance, uSpecks) * (1.0 - smoothstep(radius - px, radius + px, dist));
  vec3 speckColor = mix(vec3(0.95, 0.93, 1.0), mix(uCore, vec3(1.0), 0.6), step(0.6, tone) * 0.7);
  col = mix(col, speckColor, clamp(speck, 0.0, 1.0) * 0.9);

  // Rim light, inner glow and a little shade on one side.
  float rimBand = exp(-(1.0 - rr) / 0.05);
  float rimLit = 0.75 + 0.35 * max(-dir.y, 0.0);
  col = screenBlend(col, rimColor * (rimBand + 0.25 * fres) * (1.0 + uHover * 0.35) * rimLit);
  col += col * (1.0 - rr * rr) * 0.25 * (1.0 + uHover * 0.4);
  col *= 1.0 - 0.10 * clamp(dot(q, normalize(vec2(0.7, -0.7))), 0.0, 1.0);

  float disc = 1.0 - smoothstep(1.0 - 1.5 * px, 1.0 + 0.5 * px, r);
  vec3 body = clamp(col, 0.0, 1.0);
  vec3 outside = rimColor * halo;
  fragColor = vec4(
      body * disc + outside * (1.0 - disc),
      clamp(disc + halo * (1.0 - disc), 0.0, 1.0));
}