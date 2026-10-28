#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;
uniform float uUnit;
uniform float uPixel;
uniform float uPhase;
uniform float uSteps;
uniform float uAo;
uniform float uAoScale;
uniform vec3 uGeo;
uniform vec3 uShape;
uniform vec2 uTilt;
uniform vec3 uCenter;
uniform vec4 uStroke;
uniform vec4 uStroke2;
uniform vec4 uSurf;
uniform vec4 uLight;
uniform vec2 uSeed;
uniform vec3 uBase;
uniform vec3 uBlack;
uniform vec3 uFoil0;
uniform vec3 uFoil1;
uniform vec3 uFoil2;
uniform vec3 uFoil3;
uniform vec3 uFoil4;
uniform vec3 uFoil5;
uniform vec3 uFoil6;

out vec4 fragColor;

const float PI = 3.14159265;
const float TAU = 6.28318531;
// Hard ceiling for the march loop. uSteps decides how many are really used.
const int MAX_STEPS = 90;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// Distance to a regular polygon with n sides and apothem ap.
float sdPoly(vec2 p, float ap, float n) {
  float an = PI / n;
  float a = atan(p.y, p.x);
  float bn = 2.0 * an * floor((a + an) / (2.0 * an));
  float c = cos(bn);
  float s = sin(bn);
  vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
  float he = ap * tan(an);
  return length(q - vec2(ap, clamp(q.y, -he, he))) * sign(q.x - ap);
}

// World space to the ring's own space: moved to its centre, tipped by the
// tilt and divided by the scale.
vec3 toObj(vec3 p) {
  vec3 q = p - vec3(uCenter.xy, 0.0);
  return vec3(
      q.x,
      uTilt.x * q.y - uTilt.y * q.z,
      uTilt.y * q.y + uTilt.x * q.z) / max(uShape.z, 0.001);
}

// Distance to the ring, in the ring's own space. The cross-section is a
// rounded polygon that twists as it goes around.
float mapObj(vec3 q) {
  float u = atan(q.y, q.x);
  vec2 c = vec2(length(q.xy) - uGeo.x, q.z);
  float th = (uShape.y * u + uPhase) / uShape.x;
  float cs = cos(th);
  float sn = sin(th);
  vec2 cp = vec2(cs * c.x + sn * c.y, -sn * c.x + cs * c.y);
  float rad = uGeo.y * uGeo.z;
  return sdPoly(cp, uGeo.y - rad, uShape.x) - rad;
}

float map(vec3 p) {
  return 0.7 * mapObj(toObj(p)) * uShape.z;
}

vec3 calcNormal(vec3 p) {
  float e = 0.0005 * uShape.z;
  const vec2 k = vec2(1.0, -1.0);
  return normalize(
      k.xyy * map(p + k.xyy * e) +
      k.yyx * map(p + k.yyx * e) +
      k.yxy * map(p + k.yxy * e) +
      k.xxx * map(p + k.xxx * e));
}

// Ambient occlusion from up to four samples. uAoScale keeps the strength the
// same when fewer samples are used.
float calcAO(vec3 p, vec3 n) {
  float occ = 0.0;
  float w = 1.0;
  float S = uShape.z;
  for (int i = 1; i <= 4; i++) {
    if (float(i) > uAo) {
      break;
    }
    float hh = 0.014 * float(i) * S;
    occ += (hh - map(p + n * hh) / 0.7) * w;
    w *= 0.65;
  }
  return clamp(1.0 - uLight.w * 10.0 * occ * uAoScale / S, 0.35, 1.0);
}

// The i-th foil colour, for i = 0 to 6. Seven plain uniforms and no array,
// because indexing arrays by a variable is unreliable in Flutter shaders.
vec3 foilColor(float i) {
  vec3 c = uFoil0;
  c = mix(c, uFoil1, step(0.5, i));
  c = mix(c, uFoil2, step(1.5, i));
  c = mix(c, uFoil3, step(2.5, i));
  c = mix(c, uFoil4, step(3.5, i));
  c = mix(c, uFoil5, step(4.5, i));
  c = mix(c, uFoil6, step(5.5, i));
  return c;
}

// Walks around the foil palette. x wraps, so the palette is a loop.
vec3 foil(float x) {
  x = fract(x) * 7.0;
  float i = floor(x);
  float fr = smoothstep(0.0, 1.0, x - i);
  float a = min(i, 6.0);
  float b = a >= 6.0 ? 0.0 : a + 1.0;
  return mix(foilColor(a), foilColor(b), fr);
}

vec3 shadeRing(vec3 p, vec3 rd, float t, float pix) {
  vec3 n = calcNormal(p);
  vec3 L = normalize(uLight.xyz);
  float S = uShape.z;
  float ndv = clamp(dot(n, -rd), 0.0, 1.0);
  float diff = max(dot(n, L), 0.0);
  float occ = calcAO(p, n);
  float amb = uSurf.z;
  float light = (amb * (0.85 + 0.15 * n.y) + (1.0 - amb) * diff) * occ * uSurf.w;
  float spec = pow(max(dot(reflect(rd, n), L), 0.0), 28.0);
  vec3 col = uBase * light + 0.05 * spec;

  // Where on the surface this point is: around the ring (u), and around the
  // tube (v), then which brush stroke owns it.
  vec3 q = toObj(p);
  float u = atan(q.y, q.x);
  float rho = length(q.xy);
  vec2 c = vec2(rho - uGeo.x, q.z);
  float th = (uShape.y * u + uPhase) / uShape.x;
  float cs = cos(th);
  float sn = sin(th);
  vec2 cp = vec2(cs * c.x + sn * c.y, -sn * c.x + cs * c.y);
  float v = atan(cp.y, cp.x);
  float M = uStroke.x;
  float rows = uStroke.y;
  float su = (u + PI) / TAU * M;
  float iu = floor(su);
  float bb = (su - iu - 0.5) * TAU / M * rho;
  float sv = v / TAU * rows;
  float iv = floor(sv + 0.5);
  float along = (sv - iv) * TAU / rows * length(cp);
  float hl = max(0.5 * uStroke.z * TAU / rows * uGeo.y * 1.25, 0.0005);
  float A = uStroke2.x * TAU / M * rho;
  float K = PI * uStroke2.y / hl;
  float xx = clamp(along, -hl, hl);
  float dy = A * K * cos(K * xx);
  float dP = (bb - A * sin(K * xx)) / sqrt(1.0 + dy * dy);
  float d = length(vec2(dP, along - xx));
  float hw = 0.5 * uStroke.w;
  float px = t * pix / S / max(ndv, 0.3);
  float m = 1.0 - smoothstep(hw - 0.7 * px, hw + 0.7 * px, d);
  if (m > 0.0) {
    vec2 cell = vec2(mod(iu, M), mod(iv, rows));
    float h1 = hash21(cell + uSeed);
    float h2 = hash21(cell.yx * 1.73 + uSeed.yx + 11.0);
    float x = h1 + (xx / (2.0 * hl)) * 0.45 + uStroke2.w * (1.0 - ndv) + 0.12 * n.y;
    vec3 fc = foil(x);
    vec3 sc = h2 < uStroke2.z ? mix(uBlack, fc, 0.1 + 0.3 * (1.0 - ndv)) : fc;
    float sp = hash21(floor(vec2(along, bb) * 700.0) + cell * 13.0 + uSeed * 3.0);
    sc *= 1.0 + uSurf.y * (sp - 0.5);
    sc = sc * clamp(0.3 + 0.8 * light, 0.0, 1.3) +
        uSurf.x * spec * vec3(1.0, 0.86, 0.93);
    col = mix(col, sc, m);
  }
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = vec2(frag.x - uOrigin.x, uOrigin.y - frag.y) / uUnit;

  // The original's camera: a 30 degree field of view looking down -z.
  float f = uCenter.z;
  vec3 ro = vec3(0.0, 0.0, f);
  vec3 rd = normalize(vec3(uv, -f));
  // The angle one device pixel covers.
  float pix = uPixel / (uUnit * f);

  // Bounding sphere and slab around the ring, so most rays stop right here.
  float S = uShape.z;
  float an = PI / uShape.x;
  float rad = uGeo.y * uGeo.z;
  float corner = (uGeo.y - rad) / cos(an) + rad;
  float rOut = (uGeo.x + corner) * S * 1.03;
  float hz = corner * S * 1.03;
  vec3 C = vec3(uCenter.xy, 0.0);
  vec3 oc = ro - C;
  float b = dot(oc, rd);
  float h = b * b - (dot(oc, oc) - rOut * rOut);
  if (h <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float sq = sqrt(h);
  float t0 = -b - sq;
  float t1 = -b + sq;
  float zo = uTilt.y * oc.y + uTilt.x * oc.z;
  float zd = uTilt.y * rd.y + uTilt.x * rd.z;
  if (abs(zd) > 1.0e-5) {
    float ta = (-hz - zo) / zd;
    float tb = (hz - zo) / zd;
    t0 = max(t0, min(ta, tb));
    t1 = min(t1, max(ta, tb));
  }
  if (t1 <= t0) {
    fragColor = vec4(0.0);
    return;
  }

  float t = t0;
  bool hit = false;
  float dmin = 1.0e9;
  float tmin = t0;
  for (int i = 0; i < MAX_STEPS; i++) {
    if (float(i) >= uSteps) {
      break;
    }
    float d = map(ro + rd * t);
    if (d < 0.4 * t * pix) {
      hit = true;
      break;
    }
    float ang = d / t;
    if (ang < dmin) {
      dmin = ang;
      tmin = t;
    }
    t += d;
    if (t > t1) {
      break;
    }
  }

  if (hit) {
    vec3 col = clamp(shadeRing(ro + rd * t, rd, t, pix), 0.0, 1.0);
    fragColor = vec4(col, 1.0);
  } else if (dmin < 0.7 * pix) {
    // A ray that only skims the ring gets partial coverage, which softens the edge.
    float cov = 1.0 - smoothstep(0.0, pix, dmin / 0.7);
    vec3 col = clamp(shadeRing(ro + rd * tmin, rd, tmin, pix), 0.0, 1.0);
    fragColor = vec4(col * cov, cov);
  } else {
    fragColor = vec4(0.0);
  }
}
