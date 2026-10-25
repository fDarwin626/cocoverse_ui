#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpin;
uniform float uTilt;
uniform vec3 uAnchor;
uniform vec3 uColorA;
uniform vec3 uColorB;
uniform vec3 uColorC;

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float radiusPx = 0.5 * min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / radiusPx;
  p.y = -p.y;
  float r = length(p);

  // Soft one-pixel edge. Pixels outside the circle stop here.
  float edge = 1.0 / radiusPx;
  float alpha = 1.0 - smoothstep(1.0 - edge, 1.0, r);
  if (alpha <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  float z = sqrt(max(0.0, 1.0 - r * r));
  vec3 view = vec3(p.x, p.y, z);

  // Spin around the vertical axis, then tilt, to get the direction we sample.
  float cs = cos(uSpin);
  float ss = sin(uSpin);
  vec3 n = vec3(cs * view.x + ss * view.z, view.y, -ss * view.x + cs * view.z);
  float ct = cos(uTilt);
  float st = sin(uTilt);
  n = vec3(n.x, ct * n.y - st * n.z, st * n.y + ct * n.z);

  float lon = atan(n.z, n.x);
  float lat = asin(clamp(n.y, -1.0, 1.0));

  // Placeholder surface: flowing bands blended through the palette.
  float bands = 0.5 + 0.5 * sin(lat * 5.0 + sin(lon * 3.0 + uTime * 0.3) * 1.2);
  float swirl = 0.5 + 0.5 * sin(lon * 2.0 + lat * 3.0);
  vec3 color = mix(mix(uColorA, uColorB, bands), uColorC, swirl);

  // Lighting stays fixed in view space while the surface turns.
  vec3 light = normalize(vec3(-0.4, 0.6, 0.7));
  float diffuse = 0.35 + 0.65 * max(dot(view, light), 0.0);
  float rim = pow(1.0 - z, 2.4);
  vec3 halfway = normalize(light + vec3(0.0, 0.0, 1.0));
  float shine = pow(max(dot(view, halfway), 0.0), 60.0) * 0.4;

  vec3 rgb = color * diffuse + uAnchor * rim + vec3(shine);
  rgb = min(rgb, vec3(1.0));
  fragColor = vec4(rgb * alpha, alpha);
}