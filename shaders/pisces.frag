#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uCenter;   // fish centre in px, y down
uniform float uK;       // px per body length
uniform vec3 uFwd;      // the fish's forward, up and side axes in view space
uniform vec3 uUp;
uniform vec3 uSide;
uniform vec4 uBody;     // beat phase, beat amplitude, turn bend, gulp
uniform vec3 uCap;      // hood colour, linear
uniform vec3 uSkin;     // body colour, linear
uniform vec4 uLook;     // body depth, sheen, opacity, march steps
uniform vec3 uBelly;    // belly colour, linear

out vec4 fragColor;

const float PI = 3.14159265;
const float SE_P = 2.3;
const float SNOUT = 0.10;
const float BUTT = 0.09;
const float M_CORNER = 0.1;
// the eye in rest body coordinates: x forward from mid-body, y up, radius
const vec3 EYE = vec3(0.35, 0.02, 0.05);

float sm(float a, float b, float x) {
  float t = clamp((x - a) / (b - a), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

float h21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vn2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
             mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 tone(vec3 c) {
  c = 1.0 - exp(-max(c, vec3(0.0)));
  return pow(c, vec3(1.0 / 2.2));
}

// ---- body shape: s runs from the snout (0) to the tail stalk (1)

float halfH(float s) {
  float t = pow(clamp(s, 0.0, 1.0), 1.16);
  float w = max(sin(PI * t), 0.0);
  return 0.07 + 0.24 * pow(w, 0.85);
}

// The centre line sags at the snout and rises toward the tail stalk.
float centerY(float s) {
  return -0.012 * sin(PI * clamp(s, 0.0, 1.0))
      + 0.045 * sm(0.7, 1.0, s)
      - 0.04 * (1.0 - sm(0.0, 0.16, s));
}

float capG(float s) {
  if (s < SNOUT) {
    float q = 1.0 - max(s, 0.0) / SNOUT;
    return sqrt(max(0.0, 1.0 - q * q));
  }
  if (s > 1.0) {
    float q = (s - 1.0) / BUTT;
    return sqrt(max(0.0, 1.0 - q * q));
  }
  return 1.0;
}

// Sideways offset of the spine at s, and its slope.
float latD(float s, out float dp) {
  float sc = max(s, 0.0);
  float ph = uBody.x;
  float amp = uBody.y;
  float bend = uBody.z;
  float s12 = pow(max(sc, 1e-4), 1.2);
  float s22 = s12 * sc;
  float a1 = ph - 3.2 * sc;
  float sn = sin(a1);
  float cs = cos(a1);
  float w1 = 0.09 * s22 * sn;
  float dw1 = 0.09 * (2.2 * s12 * sn - 3.2 * s22 * cs);
  float sn2 = sin(ph + 0.9);
  float w2 = 0.014 * (1.0 - sc) * sn2;
  float dw2 = -0.014 * sn2;
  float u = max(sc - 0.2, 0.0);
  dp = amp * (dw1 - dw2) + bend * 2.6 * u;
  return amp * (w1 - w2) + bend * (1.3 * u * u - 0.03);
}

// Bent space back to the straight body: the ring s and the rest-side offset.
void unbend(vec3 P, out float s, out float rz) {
  float dp;
  float s0 = 0.5 - P.x;
  float lat0 = latD(s0, dp);
  float m0 = inversesqrt(1.0 + dp * dp);
  s = 0.5 - P.x + dp * m0 * m0 * (P.z - lat0);
  float lat1 = latD(s, dp);
  float m1 = inversesqrt(1.0 + dp * dp);
  float dx = P.x - (0.5 - s);
  rz = m1 * ((P.z - lat1) + dp * dx);
}

float mouthY(float s) {
  return -0.052 - 0.014 * sm(0.0, M_CORNER, s) - 0.012 * sm(M_CORNER - 0.02, M_CORNER + 0.01, s);
}

float lipT(float s) {
  return 0.045 - 0.029 * sm(0.0, M_CORNER, s);
}

// Distance to the body, in body lengths (P is in bent space).
float bodyDist(vec3 P) {
  float s;
  float rz;
  unbend(P, s, rz);
  float y = P.y;
  float x = 0.5 - s;
  float g = capG(s);
  float h = halfH(s) * uLook.x;
  float hh = max(h * g, 1e-3);
  float hw = max(0.78 * h * g, 1e-3);
  float a = (y - centerY(s)) / hh;
  float b = rz / hw;
  float r = pow(pow(abs(a), SE_P) + pow(abs(b), SE_P), 1.0 / SE_P);
  float d = (r - 1.0) * min(hh, hw);
  float rr = max(r, 1e-3);
  float yn = clamp(a / rr, -1.0, 1.0);
  float zn = clamp(b / rr, -1.0, 1.0);

  // The hood: lumps over the crown and cheeks, sunk round the eye, and a
  // smooth swell over the forehead so the head is curved, not flat.
  float hood = sm(0.02, 0.08, s) * (1.0 - sm(0.24, 0.36, s + 0.05 * yn)) * sm(-0.7, 0.05, yn);
  if (hood > 0.0) {
    float lump = 0.5 + 0.25 * sin(x * 21.0 + y * 17.0 + 1.3) + 0.25 * sin(rz * 25.0 - y * 19.0 + x * 11.0);
    float re = length(vec2(x - EYE.x, y - EYE.y)) / EYE.z;
    float socket = mix(1.0, sm(1.05, 1.9, re), sm(0.2, 0.35, abs(zn)));
    d -= 0.034 * hood * (0.35 + 0.65 * lump) * socket;
  }
  d -= 0.02 * sm(0.02, 0.10, s) * (1.0 - sm(0.12, 0.30, s)) * sm(0.0, 0.6, yn);

  // The snout and the tail stalk end in rounded caps.
  float dEnd = max(-s, s - (1.0 + BUTT));
  return length(vec2(max(d, 0.0), max(dEnd, 0.0))) + min(max(d, dEnd), 0.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  if (frag.x < -uSize.x || frag.y < -uSize.y) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 v = vec2((frag.x - uCenter.x) / uK, (uCenter.y - frag.y) / uK);
  vec3 w = vec3(v, 1.5);
  vec3 ro = vec3(dot(uFwd, w), dot(uUp, w), dot(uSide, w));
  vec3 rd = vec3(-uFwd.z, -uUp.z, -uSide.z);

  // Skip rays that miss the sphere around the fish.
  float bR = 0.68;
  float bq = dot(ro, rd);
  float cq = dot(ro, ro) - bR * bR;
  float hq = bq * bq - cq;
  if (hq < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  hq = sqrt(hq);
  float t = max(-bq - hq, 0.0);
  float tMax = -bq + hq;

  float pixel = 1.0 / uK;
  float minD = 1.0e9;
  float tBest = t;
  bool hit = false;
  for (int i = 0; i < 72; i++) {
    if (float(i) >= uLook.w || t > tMax) {
      break;
    }
    float d = bodyDist(ro + rd * t);
    if (d < minD) {
      minD = d;
      tBest = t;
    }
    if (d < 0.0012) {
      hit = true;
      break;
    }
    t += d * 0.7;
  }
  if (!hit && minD > pixel) {
    fragColor = vec4(0.0);
    return;
  }
  float coverage = hit ? 1.0 : 1.0 - sm(0.0, pixel, minD);

  vec3 pB = ro + rd * tBest;
  vec2 ee = vec2(0.0015, -0.0015);
  vec3 nB = normalize(
      ee.xyy * bodyDist(pB + ee.xyy) + ee.yyx * bodyDist(pB + ee.yyx) +
      ee.yxy * bodyDist(pB + ee.yxy) + ee.xxx * bodyDist(pB + ee.xxx));
  vec3 N = uFwd * nB.x + uUp * nB.y + uSide * nB.z;
  vec3 V = vec3(0.0, 0.0, 1.0);

  // Where on the straight body this point is.
  float s;
  float rz;
  unbend(pB, s, rz);
  float ry = pB.y;
  float rx = 0.5 - s;
  float g = capG(s);
  float h = halfH(s) * uLook.x;
  float hh = max(h * g, 1e-3);
  float hw = max(0.78 * h * g, 1e-3);
  float a = (ry - centerY(s)) / hh;
  float b = rz / hw;
  float r = pow(pow(abs(a), SE_P) + pow(abs(b), SE_P), 1.0 / SE_P);
  float rr = max(r, 1e-3);
  float yn = clamp(a / rr, -1.0, 1.0);
  float zn = clamp(b / rr, -1.0, 1.0);
  float side = zn >= 0.0 ? 1.0 : -1.0;

  // ---- pigment: hood, body, and a whitish belly
  float capEdge = 0.255 + 0.085 * (1.0 - yn * yn) + 0.02 * yn;
  float cap = 1.0 - sm(capEdge - 0.07, capEdge + 0.06, s);
  vec3 body = uSkin;
  vec3 cream = mix(body, uBelly, 0.75);
  vec3 goldM = mix(body, vec3(1.0, 0.45, 0.03), 0.5);
  vec3 alb = body;
  float mottle = vn2(vec2(s * 6.0, yn * 2.6) + 11.0);
  alb = mix(alb, goldM, 0.3 * sm(0.4, 0.85, mottle));
  alb = mix(alb, mix(body, uCap, 0.45) * 0.92, sm(0.4, 0.85, yn) * sm(0.28, 0.42, s));
  alb = mix(alb, cream, sm(-0.25, -0.8, yn) * 0.85 * (1.0 - sm(0.5, 0.78, s)));
  alb = mix(alb, mix(body, uCap, 0.5), sm(0.86, 0.99, s));
  vec3 capCol = mix(uCap, mix(uCap, cream, 0.35), sm(-0.4, -0.95, yn));
  alb = mix(alb, capCol, cap);

  // ---- skin: fine overlapping scales, as a rough finish that glints. The
  // pattern fades out when the scales get too small to see.
  float scaleOn = sm(capEdge, capEdge + 0.05, s) * (1.0 - sm(0.96, 1.01, s)) * (1.0 - sm(0.82, 0.97, abs(yn)));
  float ndvG = clamp(N.z, 0.0, 1.0);
  float fw = 1.0 / max(uK * min(0.03, 0.1 * hh), 1e-3);
  float detail = (1.0 - sm(0.35, 0.8, fw)) * sm(0.12, 0.35, ndvG);
  vec2 g2 = vec2(s / 0.03, yn * 10.0);
  vec2 cell = vec2(0.0);
  vec2 dl = vec2(0.0);
  const float RS = 0.78;
  bool got = false;
  for (int i = -1; i <= 0; i++) {
    float cx = floor(g2.x) + float(i);
    float off = mod(cx, 2.0) * 0.5;
    float ry2 = floor(g2.y - off);
    for (int j = -1; j <= 1; j++) {
      vec2 c = vec2(cx + 0.5, ry2 + float(j) + 0.5 + off);
      vec2 dd = g2 - c;
      if (!got && dot(dd, dd) < RS * RS) {
        got = true;
        cell = c;
        dl = dd;
      }
    }
  }
  float rrS = length(dl) / RS;
  float su = dl.x / RS;
  float sv = dl.y / RS;
  float hs = h21(cell);
  float hs2 = h21(cell + 17.3);
  float sk = scaleOn * detail;
  float freeRim = sm(0.6, 0.92, rrS) * sm(-0.15, 0.35, su);
  float pocket = sm(0.5, 0.92, rrS) * sm(0.1, -0.5, su);
  float radii = (0.5 + 0.5 * sin(atan(sv, su + 0.75) * 18.0)) * sm(0.25, 0.7, rrS) * (1.0 - sm(0.3, 0.6, fw));
  alb *= mix(1.0, 0.86 + 0.26 * hs, sk);
  alb *= 1.0 - 0.3 * pocket * sk;
  alb *= 1.0 - 0.07 * radii * sk;
  alb = mix(alb, goldM, 0.4 * freeRim * sk);
  // each scale is a shallow dome at its own small angle: the diffuse light
  // sees a softened version, the gold mirror and the glints the full one
  vec3 tiltL = vec3(-dl.x * 0.24 + (hs - 0.5) * 0.18, dl.y * 0.2 + (hs2 - 0.5) * 0.18, 0.0) * sk;
  vec3 tilt = uFwd * tiltL.x + uUp * tiltL.y + uSide * tiltL.z;
  vec3 Ns = normalize(N + tilt);
  N = normalize(N + tilt * 0.35);

  // ---- mouth: lips with their own relief, and the slit between them,
  // which opens as the fish gulps
  float nearMouth = 0.0;
  float lipWet = 0.0;
  if (s < 0.14) {
    float run = 1.0 - sm(M_CORNER, M_CORNER + 0.02, s);
    float taper = sm(0.0, M_CORNER, s);
    float gape = uBody.w * (1.0 - taper);
    float d = ry - mouthY(s);
    float dn = d / 0.04;
    nearMouth = run * exp(-dn * dn);
    float tU = lipT(s);
    float tL = 0.7 * tU;
    float uU = clamp(d / tU, 0.0, 1.0);
    float uL = clamp(-d / tL, 0.0, 1.0);
    float bU = 16.0 * uU * uU * (1.0 - uU) * (1.0 - uU);
    float bL = 16.0 * uL * uL * (1.0 - uL) * (1.0 - uL);
    float dbU = 32.0 * uU * (1.0 - uU) * (1.0 - 2.0 * uU) / tU;
    float dbL = -32.0 * uL * (1.0 - uL) * (1.0 - 2.0 * uL) / tL;
    float dhd = (0.006 * dbU + 0.004 * dbL) * run;
    float dyds = (mouthY(s + 0.002) - mouthY(s - 0.002)) / 0.004;
    vec3 Ty = uUp;
    vec3 Tx = uFwd;
    Ty -= N * dot(Ty, N);
    Tx -= N * dot(Tx, N);
    N = normalize(N - (Ty * dhd + Tx * (dhd * dyds)));
    float mU = sm(-0.001, 0.004, d) * (1.0 - sm(tU * 0.8, tU * 1.25, d)) * run;
    float mL = (1.0 - sm(-0.004, 0.001, d)) * (1.0 - sm(tL * 0.8, tL * 1.3, -d)) * run;
    vec3 lipC = mix(alb, cream, 0.32) * vec3(1.08, 0.98, 0.94);
    vec3 jawC = mix(alb, cream, 0.5) * 1.05;
    alb = mix(alb, lipC, 0.25 * nearMouth * (1.0 - taper));
    alb = mix(alb, lipC, 0.85 * mU);
    alb = mix(alb, jawC, 0.75 * mL);
    float tuck = (d + 0.004) / 0.006;
    alb *= 1.0 - 0.3 * exp(-tuck * tuck) * run;
    float slitH = 0.0018 + 0.010 * gape;
    float pxW = 1.0 / uK;
    float slit = (1.0 - sm(slitH, slitH + pxW * 1.2, abs(d))) * run * min(1.0, (slitH * 2.0 + pxW * 0.6) / pxW);
    vec3 inner = mix(vec3(0.17, 0.06, 0.035), vec3(0.10, 0.015, 0.012), gape);
    alb = mix(alb, inner, slit * (0.75 + 0.25 * gape));
    lipWet = max(bU, bL) * run;
    Ns = N;
  }

  // ---- wen: fine lumps over the hood, as a bump on the normal
  float wen = cap * sm(0.03, 0.08, s) * sm(-0.6, 0.1, yn) * (1.0 - nearMouth);
  if (wen > 0.0) {
    vec3 q = vec3(rx, ry, rz) * 22.0;
    vec3 bump = vec3(vn2(q.yz + 3.1), vn2(q.xz + 7.7), vn2(q.xy + 1.3)) - 0.5;
    q *= 2.3;
    bump += 0.5 * (vec3(vn2(q.yz + 5.3), vn2(q.xz + 2.2), vn2(q.xy + 9.1)) - 0.5);
    vec3 bv = uFwd * bump.x + uUp * bump.y + uSide * bump.z;
    N = normalize(N + bv * 0.9 * wen);
    Ns = N;
  }

  // ---- gill cover: one thin dark crease where the hood ends, with a faint
  // lit edge behind it
  float sg = 0.245 + 0.085 * (1.0 - yn * yn) + 0.015 * yn;
  float dg = s - sg;
  float gillMask = sm(-0.9, -0.55, yn) * (1.0 - sm(0.5, 0.8, yn));
  float cw = max(0.0055, 0.8 / uK);
  float crease = exp(-dg * dg / (cw * cw)) * gillMask;
  float gillHi = sm(0.004, 0.012, dg) * (1.0 - sm(0.012, 0.03, dg)) * gillMask;
  alb *= 1.0 - 0.45 * crease;

  // ---- nostril
  vec2 nd = vec2(rx - (0.5 - 0.072), ry - 0.075);
  alb *= 1.0 - 0.55 * (1.0 - sm(0.006, 0.013, length(nd))) * sm(0.25, 0.35, abs(zn));

  // ---- lighting: a key light from the upper left, a fill from below. The
  // matte hood is lit all round; the scaled body mirrors the studio like gilt.
  vec3 L = normalize(vec3(-0.40, 0.86, 0.24));
  vec3 L2 = normalize(vec3(-0.1, -0.9, 0.25));
  float ndl = dot(N, L);
  float ndv = clamp(dot(N, V), 0.0, 1.0);
  float wr = mix(0.1, 0.65, cap);
  float d1 = max(0.0, (ndl + wr) / (1.0 + wr));
  float d2 = max(0.0, (dot(N, L2) + wr) / (1.0 + wr));
  vec3 H = normalize(L + V);
  float sheen = uLook.y;
  vec3 Rv = reflect(-V, Ns);
  float upR = sm(0.2, 0.95, Rv.y);
  float dnR = sm(0.3, 0.95, -Rv.y);
  float env = 1.7 * upR * upR + dnR * dnR + 0.03;
  float metal = scaleOn * (1.0 - cap) * 0.72;
  float spec = pow(max(dot(N, H), 0.0), 90.0) * 0.55 * (1.0 + 1.5 * lipWet);
  float glint = pow(max(dot(Ns, H), 0.0), 240.0) * step(0.45, hs2) * 3.2 * sk;
  vec3 specC = mix(vec3(1.0, 0.93, 0.78), goldM, 0.45);
  float fres = pow(1.0 - ndv, 2.2);
  float mxc = max(max(uCap.r, uCap.g), max(uCap.b, 1e-4));
  vec3 col = alb * (2.2 * d1 + 1.1 * d2 + 0.14) * (1.0 - 0.45 * metal);
  col += goldM * env * metal * 1.75 * sheen;
  col *= mix(1.0, 0.45, fres);
  col += alb * (uCap / mxc) * fres * 0.3;
  col += specC * (spec + glint) * 1.4 * sheen;
  col += alb * gillHi * 0.2;

  // ---- eye: a glossy black pupil in a gold ring, with a shadowed socket
  vec2 e = vec2(rx - EYE.x, ry - EYE.y);
  float re = length(e) / EYE.z;
  if (re < 1.3 && abs(zn) > 0.3) {
    float few = max(1.0 / (uK * EYE.z), 1e-3);
    float inEye = 1.0 - sm(1.0 - few, 1.0 + few, re);
    float rc = min(re, 1.0);
    vec3 eLocal = vec3(e / EYE.z * 0.9, side * sqrt(max(0.05, 1.0 - rc * rc * 0.81)));
    vec3 En = normalize(uFwd * eLocal.x + uUp * eLocal.y + uSide * eLocal.z);
    float ang = atan(e.y, e.x);
    float fib = 0.85 + 0.15 * sin(ang * 23.0 + h21(vec2(floor(ang * 3.7), 1.0)) * 6.0);
    vec3 iris = mix(vec3(0.95, 0.62, 0.1), vec3(0.45, 0.2, 0.02), sm(0.66, 0.97, re)) * fib;
    float pup = 1.0 - sm(0.62 - few, 0.62 + few, re);
    vec3 ec = mix(iris, vec3(0.006, 0.006, 0.009), pup);
    ec *= 1.0 - 0.6 * sm(0.86, 1.0, re);
    float ediff = max(0.0, dot(En, L)) * 1.1 + 0.45;
    vec3 Re = reflect(-V, En);
    float eg = pow(max(dot(Re, L), 0.0), 380.0) * 7.0
        + pow(max(dot(Re, normalize(L + vec3(0.6, -0.3, 0.4))), 0.0), 120.0) * 1.2;
    vec3 eyeCol = ec * ediff * 1.6 + vec3(eg);
    float ring = sm(0.95, 1.05, re) * (1.0 - sm(1.05, 1.3, re));
    col *= 1.0 - 0.35 * ring;
    col = mix(col, eyeCol, inEye);
  }

  float alpha = coverage * uLook.z;
  fragColor = vec4(tone(col) * alpha, alpha);
}