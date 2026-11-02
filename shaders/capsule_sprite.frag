#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// A glass capsule seen from the front, ray traced per pixel. The capsule is
// a unit sphere (radius 1 in these units) with a thick glass wall; inside it
// sits a smaller satin sphere with two raised pill eyes. The upper half of
// the glass is clear and the lower half frosted, and the two halves meet at
// a tilted seam whose lip is drawn as a pale band with glass edge lines.

uniform vec2 uCenter;   // capsule centre in px, y down
uniform float uRadius;  // capsule radius in px
uniform vec3 uSeamN;    // seam plane normal, pointing to the clear half
uniform float uSeamD;   // seam plane offset
uniform float uRi;      // inner radius of the glass wall
uniform float uLip;     // inner radius of the seam lip
uniform float uBallR;   // sprite radius
uniform float uBallY;   // sprite height offset (it bobs)
uniform vec3 uRx;       // sprite's own x axis, in view space
uniform vec3 uRy;       // sprite's own y axis
uniform vec3 uRz;       // sprite's own z axis (the way it faces)
uniform vec4 uEye;      // half gap, half segment length, half width (rad), openness
uniform vec3 uBall;     // sprite colour, linear
uniform vec3 uEyeCol;   // eye colour, linear
uniform float uFrost;   // 0 clear, 1 the default look, 2 near opaque milk
uniform float uGloss;   // strength of every reflection
uniform float uGlow;    // bloom round the silhouette

out vec4 fragColor;

const float IOR = 1.5;

// A smoothstep that also works when the first edge is the larger one.
float ss(float a, float b, float x) {
  float t = clamp((x - a) / (b - a), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

float fresnel(float c) {
  float k = 1.0 - clamp(c, 0.0, 1.0);
  float k2 = k * k;
  return 0.04 + 0.96 * k2 * k2 * k;
}

// ------------------------------------------------------------- the studio
//
// The lights are painted where their reflections land on the front of a
// unit sphere, so a reflected direction R is looked up at normalize(R + view).
// Every surface in the scene reads the same studio.

// One short bright streak: its centre sits at polar (at, radius), its long
// axis points along tilt. soft widens it for rough surfaces.
float streak(vec2 m, float at, float radius, float tilt, float halfLen, float halfWid, float soft) {
  vec2 outward = vec2(cos(at), sin(at));
  vec2 along = vec2(cos(tilt), sin(tilt));
  vec2 d = m - outward * radius;
  vec2 q = vec2(max(abs(dot(d, along)) - halfLen, 0.0), dot(d, vec2(-along.y, along.x)));
  float w = halfWid + soft;
  float k = length(q) / w;
  float v = ss(1.0, 0.55, k) * 0.85 + exp(-k * k) * 0.15;
  return v * (halfWid / w);
}

vec3 studio(vec3 R, float soft, float rimAmt, float pull, float topAmt) {
  vec3 h = R + vec3(0.0, 0.0, 1.0);
  float lh = length(h);
  vec2 m = lh > 0.0001 ? h.xy / lh : vec2(0.0, 1.0);
  m *= pull;
  float rm = length(m);

  // All the lights sit in the upper right.
  float s = 0.0;
  if (m.x > -0.4 - soft * 3.0 && m.y > 0.1 - soft * 3.0) {
    s += streak(m, 1.618, 0.885, 2.810, 0.040, 0.024, soft) * topAmt;
    s += streak(m, 1.276, 0.840, 2.600, 0.130, 0.040, soft) * topAmt;
    s += streak(m, 1.066, 0.892, 2.513, 0.145, 0.033, soft) * topAmt;
    s += streak(m, 0.583, 0.884, 2.094, 0.160, 0.036, soft) * 0.9;
    s += streak(m, 0.597, 0.825, 2.025, 0.105, 0.040, soft);
  }
  vec3 c = vec3(1.0, 0.99, 0.98) * 28.0 * s;
  // A bright surround behind the capsule: every grazing view of the glass
  // picks it up, which makes the white rim all the way round.
  c += vec3(0.93, 0.95, 1.0) * 3.0 * ss(0.982, 0.999, rm) * rimAmt;
  // A broad dim softbox overhead, so the dark dome is never a hole.
  c += vec3(0.9, 0.93, 1.0) * 0.05 * ss(-0.2, 0.9, m.y) * (1.0 - rm * rm * 0.5);
  return c;
}

// ---------------------------------------------------------------- the frost
//
// How brightly the frosted half glows at P, a point on its wall. It is lit
// from outside, so it glows where the lights are behind it. reach is how much
// of the key light that point sees. The sprite blocks the light that comes in
// over the camera, which leaves a darker crescent tucked under it.
float frostLight(vec3 P, float reach) {
  vec3 n = normalize(P);
  float keyL = max(dot(n, normalize(vec3(-0.95, -0.15, 0.30))), 0.0);
  float backL = max(dot(n, normalize(vec3(0.55, -0.60, -0.60))), 0.0);
  vec3 toward = normalize(vec3(-0.10, 0.15, 0.98));
  vec3 oc = vec3(0.0, uBallY, 0.0) - P;
  float along = max(dot(oc, toward), 0.0);
  float miss = length(oc - toward * along);
  float clearAir = ss(uBallR * 0.95, uBallR * 1.12, miss);
  return 0.02 + reach * 1.1 * keyL * keyL * keyL + (0.85 * backL * backL + 0.05) * clearAir;
}

// --------------------------------------------------------------- geometry

vec2 sphereHit(vec3 ro, vec3 rd, vec3 c, float r) {
  vec3 oc = ro - c;
  float b = dot(oc, rd);
  float h = b * b - (dot(oc, oc) - r * r);
  if (h < 0.0) return vec2(-1.0);
  h = sqrt(h);
  return vec2(-b - h, -b + h);
}

// ------------------------------------------------------------ the sprite

vec3 shadeSprite(vec3 P, vec3 dir, float px) {
  vec3 N = normalize(P - vec3(0.0, uBallY, 0.0));
  // The surface point in the sprite's own frame.
  vec3 nl = vec3(dot(N, uRx), dot(N, uRy), dot(N, uRz));
  vec3 albedo = uBall;
  float eye = 0.0;
  vec3 Ns = N;

  // Only the cap round the face can hold an eye.
  float reachAngle = min(uEye.x + uEye.y + uEye.z + 0.05, 3.0);
  if (nl.z > cos(reachAngle)) {
    float eyeSin = sin(uEye.x);
    float eyeCos = cos(uEye.x);
    float side = nl.x < 0.0 ? -1.0 : 1.0;
    // East and north from the centre of this eye, in radians.
    vec2 q = vec2((nl.x - side * eyeSin) / eyeCos, nl.y);
    // A pill: a segment with a round cap. Closing it shortens and thins it.
    float lid = max(uEye.w, 0.12);
    float halfLen = uEye.y * lid;
    float halfWid = uEye.z * mix(0.7, 1.0, lid);
    vec2 a = vec2(q.x, max(abs(q.y) - halfLen, 0.0) * sign(q.y));
    float dd = length(a);
    float soft = px / uBallR * 1.2;
    float cover = ss(halfWid + soft, halfWid - soft, dd);
    if (cover > 0.0) {
      // The eye is a raised half cylinder: bend the normal out from its axis.
      float rise = sqrt(max(halfWid * halfWid - dd * dd, 0.0));
      vec3 east = vec3(1.0, 0.0, 0.0);
      vec3 north = vec3(0.0, 1.0, 0.0);
      vec3 bent = normalize(nl * max(rise, 0.0001) + (east * a.x + north * a.y) * 0.85);
      Ns = normalize(uRx * bent.x + uRy * bent.y + uRz * bent.z);
      eye = cover;
      albedo = mix(uBall, uEyeCol, cover);
    }
  }

  vec3 n = normalize(mix(N, Ns, eye));

  // Satin: a flat half-lambert body, a pale sheen at the lit rim, and a broad
  // softbox wash from the upper right.
  vec3 key = normalize(vec3(0.55, 0.65, 0.50));
  float lambert = dot(n, key) * 0.5 + 0.5;
  vec3 c = albedo * (0.78 + 0.34 * lambert);
  float limb = pow(1.0 - max(n.z, 0.0), 1.8);
  float litSide = ss(-0.4, 0.7, dot(n.xy, vec2(0.55, 0.83)));
  c += vec3(0.16, 0.17, 0.20) * limb * litSide * (1.0 - eye);
  float wash = pow(max(dot(n, normalize(vec3(0.6, 0.6, 0.4))), 0.0), 1.5);
  c += vec3(0.20, 0.21, 0.24) * wash * (1.0 - eye);
  // The eyes are glossier than the body.
  c += vec3(0.28) * pow(max(dot(n, normalize(vec3(0.55, 0.5, 0.66))), 0.0), 2.2) * eye;

  // The studio, blurred by the satin's roughness.
  vec3 R = reflect(dir, n);
  float F = fresnel(max(dot(-dir, n), 0.0));
  c += studio(R, mix(0.06, 0.04, eye), 0.10, 1.15, 0.15) * mix(F * 0.5, F * 1.0 + 0.02, eye) * uGloss;
  // The eyes' shade side cools to lilac.
  c = mix(c, c * vec3(0.86, 0.87, 1.0), eye * (1.0 - lambert));
  return c;
}

// ------------------------------------------------------- the far glass wall

vec3 backWallClear(vec3 Pw, vec3 dir) {
  vec3 Nin = -Pw / uRi;
  float F = fresnel(dot(-dir, Nin));
  vec3 c = studio(reflect(dir, Nin), 0.02, 0.4, 1.0, 1.0) * F * 0.5 * uGloss;
  // Smoky toward the rim, where the far wall is seen ever more edge on.
  float g = ss(0.25, 0.8, 1.0 - abs(dot(dir, Nin)));
  c += vec3(0.003, 0.0035, 0.005) + vec3(0.040, 0.042, 0.052) * g * g;
  return c;
}

vec3 backWallFrost(vec3 Pw) {
  return vec3(0.84, 0.88, 0.97) * 0.42 * frostLight(Pw, 0.25);
}

// ------------------------------------------------------------- the seam lip
//
// The lip is a ring on the cut plane, from uLip out to the shell. s runs from
// 0 at its inner edge to 1 at the outer surface. Returns the coverage, the
// bright edge lines, the depth of the plane at this pixel, and the dark
// refracted lines beside them.
vec4 seamBand(vec2 p, float px) {
  if (abs(uSeamN.z) < 0.001) return vec4(0.0, 0.0, -9.0, 0.0);
  float zp = (uSeamD - uSeamN.x * p.x - uSeamN.y * p.y) / uSeamN.z;
  vec3 P = vec3(p, zp);
  float rp = length(P);
  if (rp < uLip - 0.02 || rp > 1.0) return vec4(0.0, 0.0, zp, 0.0);

  vec2 g = (P.xy - P.z * uSeamN.xy / uSeamN.z) / max(rp, 0.0001);
  float width = 1.0 - uLip;
  float s = (rp - uLip) / width;
  float ds = length(g) * px / width;
  float cover = ss(-ds, ds, s) * ss(1.0 + ds, 1.0 - ds, s);

  // Lines a constant number of pixels wide: bright where the faces meet, and
  // a dark refracted line beside each.
  float w = max(1.3 * ds, 0.07);
  float lines = 0.0;
  lines += 1.00 * ss(max(1.8 * ds, 0.14), 0.0, abs(s - 0.90));
  lines += 0.70 * ss(w, 0.0, abs(s - 0.50));
  lines += 0.85 * ss(w, 0.0, abs(s - 0.08));
  float dark = 0.0;
  dark += ss(w * 1.3, 0.0, abs(s - 0.70));
  dark += ss(w * 1.1, 0.0, abs(s - 0.29));
  return vec4(cover, clamp(lines, 0.0, 1.0), zp, clamp(dark, 0.0, 1.0));
}

float tone(float x) {
  return x < 0.8 ? x : 0.8 + 0.2 * (1.0 - exp(-(x - 0.8) / 0.2));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float px = 1.0 / max(uRadius, 1.0);
  vec2 p = vec2(frag.x - uCenter.x, uCenter.y - frag.y) * px;
  float r = length(p);
  if (r > 1.3) {
    fragColor = vec4(0.0);
    return;
  }

  // Bloom round the silhouette: a tight core and a wider skirt.
  float beyond = max(r - 1.0, 0.0);
  float halo = (0.11 * exp(-beyond / 0.006) + 0.03 * exp(-beyond / 0.02)) * uGlow;
  vec3 haloLight = vec3(0.92, 0.95, 1.0) * halo;
  vec3 haloShown = pow(clamp(haloLight, 0.0, 1.0), vec3(1.0 / 2.2));
  float haloAlpha = max(haloShown.r, max(haloShown.g, haloShown.b));

  float cover = 1.0 - ss(1.0 - px, 1.0 + px, r);
  if (cover <= 0.0) {
    fragColor = vec4(haloShown, haloAlpha);
    return;
  }

  vec3 rd = vec3(0.0, 0.0, -1.0);
  vec3 ballC = vec3(0.0, uBallY, 0.0);
  float frostAmt = min(uFrost, 1.0);
  float milkPush = max(uFrost - 1.0, 0.0);

  float rr = min(r, 0.99999);
  vec3 P0 = vec3(p, sqrt(1.0 - rr * rr));
  vec3 N0 = P0;
  float Fo = fresnel(N0.z);
  float frontSide = dot(uSeamN, P0) - uSeamD;
  float fm = ss(0.012, -0.012, frontSide) * frostAmt;

  // The studio reflected off the front of the glass.
  vec3 refl = studio(reflect(rd, N0), 0.0, 1.0, 1.0, 1.0) * Fo * uGloss;

  // What is inside: light it gives off, and material that fills the pixel.
  vec3 inEmit = vec3(0.0);
  vec3 inBodyCol = vec3(0.0);
  float inBody = 0.0;
  float ballZ = -9.0;

  // The ray bends into the glass wall, then out into the cavity.
  vec3 r1 = refract(rd, N0, 1.0 / IOR);
  vec2 hi = sphereHit(P0, r1, vec3(0.0), uRi);
  vec3 Pi = P0 + r1 * max(hi.x, 0.0);
  vec3 r2 = refract(r1, Pi / uRi, IOR);
  bool reachesCavity = hi.x > 0.0 && dot(r2, r2) > 0.0001;

  if (reachesCavity) {
    vec3 cavCol = vec3(0.0);
    vec3 cavEmit = vec3(0.0);
    float cavBody = 0.0;

    vec2 hb = sphereHit(Pi, r2, ballC, uBallR);
    if (hb.x > 0.0) {
      vec3 Pb = Pi + r2 * hb.x;
      ballZ = Pb.z;
      // Glass tint through two walls.
      cavCol = shadeSprite(Pb, r2, px) * vec3(0.96, 0.975, 0.985);
      cavBody = 1.0;
    } else {
      vec2 hw = sphereHit(Pi, r2, vec3(0.0), uRi);
      vec3 Pw = Pi + r2 * hw.y;
      float wallFrost = ss(0.012, -0.012, dot(uSeamN, Pw) - uSeamD) * frostAmt;
      cavEmit = backWallClear(Pw, r2) * (1.0 - wallFrost);
      cavCol = backWallFrost(Pw);
      cavBody = wallFrost;
    }

    if (fm > 0.0) {
      // Frosted front: the cavity is blurred into a soft glow.
      vec3 oc = ballC - Pi;
      float along = max(dot(oc, r2), 0.0);
      float miss = length(oc - r2 * along);
      float nearBall = ss(uBallR + 0.24, uBallR - 0.22, miss);
      vec3 innerLight = cavCol * cavBody + cavEmit;
      vec3 behind = mix(innerLight * 0.35, uBall * 0.60, nearBall);
      // Straight on, frost only softens; toward the rim the path through it
      // grows and it turns to milk.
      float milk = pow(ss(0.80 + 0.2 * milkPush, 0.22, N0.z), 1.8 - milkPush);
      float crisp = ss(0.75, 0.95, N0.z) * (1.0 - milkPush);
      behind = mix(behind, innerLight, crisp * 0.3);
      float scatter = (0.55 + frostLight(P0, 0.85)) * (0.02 + 0.98 * milk);
      vec3 frostedFront = behind * (1.0 - milk * 0.8) + vec3(0.88, 0.90, 0.97) * scatter;
      inBodyCol = mix(cavCol, frostedFront, fm);
      inBody = mix(cavBody, 0.96, fm);
      inEmit = cavEmit * (1.0 - fm);
    } else {
      inBodyCol = cavCol;
      inBody = cavBody;
      inEmit = cavEmit;
    }
  } else {
    // The band round the edge, where the ray runs round inside the glass wall.
    float b = clamp((r - uRi) / (1.0 - uRi), 0.0, 1.0);
    // Clear: a smoky band with a bright line where it starts, fed by the
    // overhead softbox.
    vec3 rimClear = vec3(0.040, 0.042, 0.052) * (0.8 + 0.6 * b)
      + vec3(0.90, 0.93, 1.0) * 0.55 * exp(-pow(b / 0.12, 2.0)) * ss(-0.1, 0.8, p.y);
    vec3 rimFrost = vec3(0.88, 0.90, 0.97) * (0.55 + frostLight(P0, 0.85)) * 1.1;
    inEmit = rimClear * (1.0 - fm);
    inBodyCol = rimFrost;
    inBody = fm * 0.96;
  }

  vec3 light = (inBodyCol * inBody + inEmit) * (1.0 - Fo) + refl;
  float alpha = clamp(inBody + max(light.r, max(light.g, light.b)) * 1.6, 0.0, 1.0);

  // The seam's lip, in front of or behind the sprite.
  vec4 sb = seamBand(p, px);
  if (sb.x > 0.0 && sb.z > ballZ) {
    float hidden = sb.z < 0.0 ? fm * 0.85 : 0.0;
    float a = sb.x * (1.0 - hidden);
    vec3 under = alpha > 0.02 ? light / alpha : vec3(0.0);
    // The lip is the cut face of the glass: pale and solid, milky where it is
    // the frosted half's.
    vec3 lipCol = under * 0.62 + vec3(0.12, 0.125, 0.15) * (0.6 + 0.6 * frostAmt);
    lipCol = mix(lipCol, lipCol * 0.35, sb.w * 0.8);
    lipCol = mix(lipCol, vec3(1.5, 1.55, 1.6), sb.y);
    light = mix(light, lipCol * 0.92, a);
    alpha = mix(alpha, 0.92, a);
  }

  // Tone map and encode, then premultiply.
  vec3 shown = light / max(alpha, 0.001);
  shown = vec3(tone(shown.r), tone(shown.g), tone(shown.b));
  shown = pow(clamp(shown, 0.0, 1.0), vec3(1.0 / 2.2));
  float capsuleAlpha = alpha * cover;
  vec3 capsulePremult = shown * capsuleAlpha;

  // The bloom sits behind the capsule.
  float outAlpha = capsuleAlpha + haloAlpha * (1.0 - capsuleAlpha);
  vec3 outPremult = capsulePremult + haloShown * (1.0 - capsuleAlpha);
  fragColor = vec4(outPremult, outAlpha);
}
