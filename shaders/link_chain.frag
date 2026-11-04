#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// The chain's numbers are packed into plain vec4 arrays, because arrays of
// anything else are laid out differently on different Flutter backends.
const int MAXL = 40;
const int MAXG = 10;
const int MAXP = 16;
const int GSIZE = 4;
const int MAX_STEPS = 96;
const float LENS = 2.35;

uniform vec2 uOrigin;
uniform float uHeight;
uniform float uPixel;
uniform vec3 uCam;
uniform vec4 uHull;
uniform vec4 uCfg;
uniform vec4 uLink;
uniform vec4 uStyle;
uniform vec4 uTint;
uniform vec4 uA[MAXL];
uniform vec4 uB[MAXL];
uniform vec4 uC[MAXL];
uniform vec4 uG[MAXG];
uniform vec4 uPal[MAXP];

out vec4 fragColor;

// uCfg:   x = number of links, y = number of groups, z = finish (0 cartoon,
//         1 metallic), w = detail (0 low, 1 medium, 2 high).
// uLink:  x = half the straight run of a link, y = ring radius, z = tube
//         radius, w = bounding radius of one link.
// uStyle: x = colour change per link, y = colour slide, z = outline width,
//         w = number of palette colours.
// uTint:  xyz = colour of the metal.
// uA:     xyz = link centre, w = link number.
// uB:     xyz = link direction, w = 1 on every other link.
// uC:     xyz = link normal.
// uG:     xyz = centre of a group of four links, w = its radius.

// iq's link, https://iquilezles.org/articles/distfunctions/
float sdLink(vec3 p, float le, float r1, float r2) {
  vec3 q = vec3(p.x, max(abs(p.y) - le, 0.0), p.z);
  return length(vec2(length(q.xy) - r1, q.z)) - r2;
}

vec2 sphIntersect(vec3 ro, vec3 rd, vec4 sph) {
  vec3 oc = ro - sph.xyz;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - sph.w * sph.w;
  float h = b * b - c;
  if (h < 0.0) {
    return vec2(-1.0, -1.0);
  }
  h = sqrt(h);
  return vec2(-b - h, -b + h);
}

// Returns (distance, link number, local x, local z).
vec4 map(vec3 p) {
  float d = 1.0e9;
  float s = 0.0;
  vec2 lxz = vec2(0.0);
  float le = uLink.x;
  float r1 = uLink.y;
  float r2 = uLink.z;
  float bound = uLink.w;

  for (int g = 0; g < MAXG; g++) {
    if (float(g) >= uCfg.y) {
      break;
    }
    vec4 G = uG[g];
    if (length(p - G.xyz) - G.w > d) {
      continue;
    }

    for (int k = 0; k < GSIZE; k++) {
      if (float(g * GSIZE + k) >= uCfg.x) {
        break;
      }
      vec3 c = uA[g * GSIZE + k].xyz;
      if (length(p - c) - bound > d) {
        continue;
      }
      vec3 T = uB[g * GSIZE + k].xyz;
      vec3 N = uC[g * GSIZE + k].xyz;
      vec3 B = cross(T, N);
      vec3 dp = p - c;
      vec3 lp = vec3(dot(dp, N), dot(dp, T), dot(dp, B));
      vec3 sp = uB[g * GSIZE + k].w > 0.5 ? vec3(lp.z, lp.y, -lp.x) : lp;
      float e = sdLink(sp, le, r1, r2);
      if (e < d) {
        d = e;
        s = uA[g * GSIZE + k].w;
        lxz = lp.xz;
      }
    }


  }
  return vec4(d, s, lxz);
}

vec3 calcNormal(vec3 p) {
  vec2 e = vec2(1.0, -1.0) * 0.0030;
  return normalize(
      e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x +
      e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

// The palette is a ring, so the last colour blends back into the first.
vec3 paletteAt(float t) {
  float count = max(uStyle.w, 1.0);
  float f = fract(t) * count;
  float fi = floor(f);
  float k = smoothstep(0.20, 0.80, f - fi);
  vec3 c0 = uPal[0].xyz;
  vec3 c1 = uPal[0].xyz;
  float next = mod(fi + 1.0, count);
  for (int j = 0; j < MAXP; j++) {
    float fj = float(j);
    if (fj == fi) {
      c0 = uPal[j].xyz;
    }
    if (fj == next) {
      c1 = uPal[j].xyz;
    }
  }
  return mix(c0, c1, k);
}

// ---- cartoon finish -------------------------------------------------------

vec3 shadeCartoon(vec3 n, vec3 rd, float link) {
  vec3 albedo = paletteAt(link * uStyle.x + uStyle.y);

  // Three flat tones, like a cel: lit, middle and shade.
  vec3 L = normalize(vec3(-0.34, 0.76, 0.55));
  float lit = dot(n, L) * 0.5 + 0.5;
  float tone = 0.62 + 0.20 * smoothstep(0.30, 0.34, lit) +
      0.18 * smoothstep(0.62, 0.66, lit);
  vec3 col = albedo * tone;

  // An ink line wherever the surface turns away from the eye, which draws the
  // edge of every tube, including where one link crosses another.
  float rim = 1.0 - clamp(dot(n, -rd), 0.0, 1.0);
  float edge = 0.78 - uStyle.z;
  float ink = smoothstep(edge, edge + 0.045, rim);
  return mix(col, vec3(0.05, 0.03, 0.09), ink);
}

// ---- metallic finish ------------------------------------------------------

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float azDist(float a, float c) {
  float d = a - c;
  d = mod(d + 3.14159265, 6.28318531) - 3.14159265;
  return abs(d);
}

// A studio for the metal to reflect: a hard horizon, a lit ceiling, a key
// softbox and a weaker fill. Edges are what make a surface read as polished.
vec3 envColor(vec3 r) {
  float y = r.y;
  float a = atan(r.z, r.x);
  float flr = 0.19 + 0.21 * smoothstep(-1.00, -0.04, y);
  float ceilV = 0.44 + 0.26 * smoothstep(0.04, 0.80, y);
  float v = mix(flr, ceilV, smoothstep(-0.055, 0.055, y));
  v += 1.35 * smoothstep(0.30, 0.44, y) * smoothstep(1.25, 0.95, azDist(a, 2.10));
  v += 0.34 * smoothstep(0.02, 0.28, y) * smoothstep(1.05, 0.70, azDist(a, 0.90));
  v += 0.34 * exp(-abs(y) * 26.0);
  v -= 0.10 * exp(-abs(y + 0.16) * 16.0);
  return max(vec3(v * 0.985, v, v * 1.03), 0.0);
}

float calcAO(vec3 p, vec3 n, float taps) {
  float occ = 0.0;
  float sca = 1.0;
  for (int i = 0; i < 5; i++) {
    if (float(i) >= taps) {
      break;
    }
    float h = 0.015 + 0.16 * float(i) / 4.0;
    occ += (h - map(p + h * n).x) * sca;
    sca *= 0.80;
  }
  return clamp(1.0 - 1.7 * occ, 0.0, 1.0);
}

// One reflection bounce off the chain itself, only on the highest detail.
vec3 reflSample(vec3 p, vec3 n, vec3 rd) {
  vec3 r = reflect(rd, n);
  vec3 env = envColor(r);
  if (uCfg.w < 1.5) {
    return env;
  }
  vec3 o = p + n * 0.015;
  vec2 hs = sphIntersect(o, r, uHull);
  if (hs.y <= 0.0) {
    return env;
  }
  float t = max(hs.x, 0.02);
  float tMax = min(hs.y, 5.5);
  for (int i = 0; i < 16; i++) {
    if (t > tMax) {
      break;
    }
    float d = map(o + r * t).x;
    if (d < 0.005) {
      vec3 e2 = envColor(reflect(r, calcNormal(o + r * t))) * 0.55;
      return mix(e2, env, smoothstep(1.2, 5.0, t));
    }
    t += max(d, 0.008);
  }
  return env;
}

// Rolls highlights off into 1.0 instead of clipping them flat.
vec3 tonemap(vec3 c) {
  const float K = 0.80;
  vec3 hi = max(c - K, 0.0);
  return min(c, vec3(K)) + (1.0 - K) * (1.0 - exp(-hi / (1.0 - K)));
}

vec3 shadeMetal(vec3 p, vec3 n, vec3 rd) {
  vec3 F0 = uTint.xyz;
  float f = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 5.0);
  vec3 F = F0 + (1.0 - F0) * f;

  float ao = 1.0;
  if (uCfg.w > 0.5) {
    ao = calcAO(p, n, uCfg.w > 1.5 ? 5.0 : 3.0);
  }
  float rocc = mix(ao * ao, 1.0, 0.22);

  vec3 L = normalize(vec3(-0.34, 0.76, 0.55));
  vec3 L2 = normalize(vec3(0.58, 0.32, 0.74));
  vec3 h1 = normalize(L - rd);
  vec3 h2 = normalize(L2 - rd);
  float s1 = pow(clamp(dot(n, h1), 0.0, 1.0), 220.0);
  float s2 = pow(clamp(dot(n, h2), 0.0, 1.0), 42.0);

  vec3 col = F * reflSample(p, n, rd) * rocc +
      F0 * (s1 * 2.2 + s2 * 0.22) * ao +
      F0 * 0.045 * ao;
  return tonemap(col);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // The frame spans -1 to 1 in height, as in the original.
  vec2 q = vec2(frag.x - uOrigin.x, uOrigin.y - frag.y) * (2.0 / uHeight);
  vec3 ro = uCam;
  vec3 rd = normalize(vec3(q, -LENS));

  vec2 hull = sphIntersect(ro, rd, uHull);
  if (hull.y <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Only march where a ray is inside one of the link groups. Most pixels are
  // not, and they end here after a handful of sphere tests.
  float tMin = 1.0e9;
  float tMax = -1.0e9;
  for (int g = 0; g < MAXG; g++) {
    if (float(g) >= uCfg.y) {
      break;
    }
    vec2 h = sphIntersect(ro, rd, uG[g]);
    if (h.y > 0.0) {
      tMin = min(tMin, max(h.x, 0.001));
      tMax = max(tMax, h.y);
    }
  }
  if (tMax < 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  // One pixel's worth of cone radius at distance t. It doubles as the soft
  // silhouette: a ray that only grazes the surface is partly covered.
  float cone = (2.0 * uPixel / uHeight) / LENS;
  float steps = 48.0 + 24.0 * uCfg.w;
  float t = tMin;
  float cover = 1.0;
  float tNear = t;
  bool hit = false;
  vec4 res = vec4(0.0);

  for (int i = 0; i < MAX_STEPS; i++) {
    if (float(i) >= steps) {
      break;
    }
    vec4 m = map(ro + rd * t);
    float w = m.x / (cone * t * 2.4);
    if (w < cover) {
      cover = w;
      tNear = t;
      res = m;
    }
    if (m.x < cone * t * 0.35) {
      hit = true;
      res = m;
      tNear = t;
      break;
    }
    t += m.x;
    if (t > tMax) {
      break;
    }
  }

  float cov = hit ? 1.0 : 1.0 - smoothstep(0.0, 1.0, max(cover, 0.0));
  if (cov <= 0.001) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 p = ro + rd * tNear;
  vec3 n = calcNormal(p);
  vec3 col = uCfg.z > 0.5 ? shadeMetal(p, n, rd) : shadeCartoon(n, rd, res.y);
  fragColor = vec4(clamp(col, 0.0, 1.0) * cov, cov);
}