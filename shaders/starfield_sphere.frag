#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpin;
uniform float uTilt;
uniform float uDetail;
uniform vec3 uAnchor;
uniform vec3 uColorA;
uniform vec3 uColorB;
uniform vec3 uColorC;

out vec4 fragColor;

float rand(vec3 p) {
  return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
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

// Star light for the direction n. The sphere is split into six square faces,
// each cut into a grid of cells, and each cell may hold one star.
vec3 starLight(vec3 n, float cells, float seed) {
  vec3 a = abs(n);
  vec2 uv;
  float face;
  if (a.x >= a.y && a.x >= a.z) {
    uv = n.yz / a.x;
    face = n.x > 0.0 ? 0.0 : 1.0;
  } else if (a.y >= a.z) {
    uv = n.xz / a.y;
    face = n.y > 0.0 ? 2.0 : 3.0;
  } else {
    uv = n.xy / a.z;
    face = n.z > 0.0 ? 4.0 : 5.0;
  }

  vec2 g = uv * cells;
  vec2 id = floor(g);
  vec2 f = fract(g);
  vec3 key = vec3(id, face + seed * 6.0);

  // Keep stars away from cell edges so no star is ever cut off.
  vec2 pos = 0.25 + 0.5 * vec2(rand(key + 1.0), rand(key + 2.0));
  float d = length(f - pos);

  float keep = step(0.5, rand(key + 3.0));
  float big = rand(key + 4.0);
  float size = 0.5 + 1.5 * big * big;
  float twinkle = 0.65 + 0.35 * sin(uTime * (1.0 + 3.0 * rand(key + 5.0)) + 40.0 * rand(key + 6.0));
  float glow = exp(-d * d * 160.0 / size) * keep * twinkle * (0.6 + 0.5 * size);

  vec3 tint = mix(vec3(1.0), mix(uColorB, uColorC, rand(key + 7.0)), 0.4);
  return tint * glow;
}

// A soft band of colored mist along a great circle.
vec3 mistLight(vec3 n) {
  float lon = atan(n.z, n.x);
  float lat = n.y;
  float across = dot(n, normalize(vec3(0.3, 1.0, 0.25)));
  float band = exp(-across * across * 10.0);
  float cloud = 0.5 + 0.5 * sin(lon * 3.0 + 2.0 * sin(lat * 4.0 + uTime * 0.2));
  cloud *= 0.5 + 0.5 * sin(lon * 5.0 - lat * 3.0 - uTime * 0.15 + 1.3);
  vec3 tint = mix(uColorA, uColorB, 0.5 + 0.5 * sin(lon * 2.0 + lat * 2.0));
  return tint * band * (0.15 + 0.45 * cloud) * 0.7;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float radiusPx = 0.5 * min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / radiusPx;
  p.y = -p.y;
  float r = length(p);

  // Soft one-pixel edge. Pixels outside the circle stop here.
  float edge = 1.0 / radiusPx;
  float coverage = 1.0 - smoothstep(1.0 - edge, 1.0, r);
  if (coverage <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 stars = vec3(0.0);
  vec3 mist = vec3(0.0);
  int shells = 1 + int(uDetail);

  for (int i = 0; i < 3; i++) {
    if (i >= shells) {
      break;
    }
    float fi = float(i);
    float radius = 1.0 - 0.2 * fi;
    float q = r / radius;
    if (q >= 1.0) {
      continue;
    }
    float depth = sqrt(1.0 - q * q);
    float yaw = uSpin * (1.0 + 0.4 * fi) + fi * 1.7;
    float pitch = uTilt + 0.35 * fi;
    float cells = 7.0 - fi;
    float fade = 1.0 - 0.15 * fi;

    vec3 front = turn(vec3(p / radius, depth), yaw, pitch);
    stars += starLight(front, cells, fi) * fade;
    if (uDetail > 0.5) {
      vec3 back = turn(vec3(p / radius, -depth), yaw, pitch);
      stars += starLight(back, cells, fi + 3.0) * 0.45 * fade;
    }
    if (i == 0) {
      mist = mistLight(front);
    }
  }

  // Glass: bright rim, a blue and red fringe at the edges, two soft highlights.
  float rim = pow(r, 12.0);
  vec3 fringe = (vec3(1.0, 0.35, 0.45) * max(p.x, 0.0)
      + vec3(0.3, 0.55, 1.0) * max(-p.x, 0.0)) * rim * 0.45;
  vec2 h1 = p - vec2(-0.38, 0.42);
  vec2 h2 = p - vec2(0.45, -0.38);
  float spec = exp(-dot(h1, h1) * 45.0) * 0.35 + exp(-dot(h2, h2) * 90.0) * 0.12;

  vec3 light = stars + mist + fringe + vec3(spec) + uAnchor * rim * 0.4;

  // A very faint tint, so the ball is mostly see-through.
  float tintAlpha = 0.10 + 0.20 * rim;
  vec3 tint = uAnchor * tintAlpha;

  float lum = max(light.r, max(light.g, light.b));
  float alpha = clamp(tintAlpha + lum, 0.0, 1.0);
  vec3 rgb = min(tint + light, vec3(alpha));
  fragColor = vec4(rgb * coverage, alpha * coverage);
}