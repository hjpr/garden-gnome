#version 460 core

// Ground texture without visible repeats.
//
// Two tricks hide the tiling of a small seamless texture:
// 1. Hex tiling (Mikkelsen, "Practical Real-Time Hex-Tiling", 2022): the
//    ground is split into hexagonal cells, each showing the texture at a
//    random offset and rotation, cross-faded where cells meet.
// 2. Macro variation: slow noise, tens of metres across, shifts the
//    brightness and drifts the colour toward a tint (e.g. dry grass), so
//    the eye has no grid to follow.
//
// Flutter web binds samplers clamped and unfiltered, so this shader wraps
// and filters (bilinear) the texture itself.

#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;       // screen position of the world origin, px
uniform float uPxPerMetre;  // current zoom
uniform float uMetres;      // ground covered by one texture repeat
uniform vec2 uTexSize;      // size of the bound texture in texels
uniform float uSeed;        // keeps ground types from sharing a pattern
uniform float uRotate;      // 1 lets cells rotate, 0 offset only
uniform float uVariation;   // strength of the brightness drift
uniform vec4 uTint;         // colour drifted toward (rgb) and how far (a)
uniform vec3 uMean;         // the texture's average colour
uniform vec2 uEdge;         // edge mask mode: x = strength (0 = colour), y = noise size m
uniform vec2 uAtlasGrid;    // 3 x 1 variants, or legacy 1 x 1
uniform float uLevels;      // 3 = full + mid + far copies bound, else full only
uniform sampler2D uTexture;
// The same atlas shrunk 4x and 16x, read when zoomed out so fine detail
// averages out instead of shimmering. Bound to uTexture when absent.
uniform sampler2D uTextureMid;
uniform sampler2D uTextureFar;

out vec4 fragColor;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Hashes without sin(), stable in 32-bit floats (Dave Hoskins).
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  return 0.55 * valueNoise(p) + 0.3 * valueNoise(p * 2.03 + 17.1) +
      0.15 * valueNoise(p * 4.01 + 31.7);
}

// Each zoomed-out copy is this much smaller than the one before.
const float kLevelStep = 4.0;

// Wrap every bilinear tap INSIDE the chosen square tile. Never let
// hardware filtering or modulo over the full atlas sample a neighbour.
vec3 texel(vec2 t, vec2 tile, float level) {
  vec2 size = uTexSize / pow(kLevelStep, level);
  vec2 tileSize = size / uAtlasGrid;
  vec2 at = (tile * tileSize + mod(t, tileSize) + 0.5) / size;
  if (level < 0.5) return texture(uTexture, at).rgb;
  if (level < 1.5) return texture(uTextureMid, at).rgb;
  return texture(uTextureFar, at).rgb;
}

// The texture at uv (1 = one repeat), wrapped and bilinear filtered.
vec3 sampleLevel(vec2 uv, vec2 tile, float level) {
  vec2 p = uv * (uTexSize / pow(kLevelStep, level) / uAtlasGrid) - 0.5;
  vec2 i = floor(p);
  vec2 f = p - i;
  vec3 a = texel(i, tile, level);
  vec3 b = texel(i + vec2(1.0, 0.0), tile, level);
  vec3 c = texel(i + vec2(0.0, 1.0), tile, level);
  vec3 d = texel(i + vec2(1.0, 1.0), tile, level);
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// How far zoomed out, in copies: 0 = full size, 1 = mid, 2 = far, with
// fractions blending the two neighbours. Set once per pixel in main().
float gLod = 0.0;

vec3 sampleWrapped(vec2 uv, vec2 tile) {
  float low = floor(gLod);
  vec3 near = sampleLevel(uv, tile, low);
  float t = gLod - low;
  if (t < 0.01) return near;
  return mix(near, sampleLevel(uv, tile, low + 1.0), t);
}

// The texture as seen through hex cell [vertex]: shifted and turned by a
// random amount about the cell's centre.
vec3 cellSample(vec2 uv, vec2 vertex, vec2 centre) {
  vec2 r = hash22(vertex + uSeed);
  float angle = uRotate * r.x * 6.2831853;
  float c = cos(angle);
  float s = sin(angle);
  vec2 d = uv - centre;
  vec2 turned = vec2(c * d.x - s * d.y, s * d.x + c * d.y) + centre;
  // Independent hash stream: variant choice must not follow rotation or
  // offset, and must stay anchored to the world-cell lattice.
  float variant = floor(hash12(vertex + vec2(127.1, 311.7) + uSeed * 2.37)
      * (uAtlasGrid.x * uAtlasGrid.y));
  vec2 tile = vec2(mod(variant, uAtlasGrid.x), floor(variant / uAtlasGrid.x));
  return sampleWrapped(turned + r * 7.31, tile);
}

// Hex cells per texture repeat: a cell covers about two-thirds of it.
const float kCellScale = 1.5;

void main() {
  vec2 world = (FlutterFragCoord().xy - uOrigin) / uPxPerMetre;
  vec2 uv = world / uMetres;

  // Full-size texels per screen pixel: above 1 the picture is shrunk on
  // screen and its detail would shimmer, so read a smaller copy.
  float texelsPerPixel =
      (uTexSize.x / uAtlasGrid.x) / max(uMetres * uPxPerMetre, 1e-3);
  float levels = uLevels > 2.5 ? 3.0 : 1.0;
  float lod = log2(max(texelsPerPixel, 1.0)) / log2(kLevelStep);
  gLod = clamp(lod, 0.0, levels - 1.0);

  // Triangle grid on the skewed hex lattice: the three cell centres
  // around this point and how much each one counts.
  vec2 st = uv * kCellScale * 3.4641016;
  vec2 skewed = vec2(st.x - 0.57735027 * st.y, 1.15470054 * st.y);
  vec2 base = floor(skewed);
  vec3 t = vec3(fract(skewed), 0.0);
  t.z = 1.0 - t.x - t.y;
  float s = step(0.0, -t.z);
  float s2 = 2.0 * s - 1.0;
  vec3 w = vec3(-t.z * s2, s - t.y * s2, s - t.x * s2);
  vec2 v1 = base + vec2(s, s);
  vec2 v2 = base + vec2(s, 1.0 - s);
  vec2 v3 = base + vec2(1.0 - s, s);

  // Cell centres back in uv space.
  float toUv = 1.0 / (kCellScale * 3.4641016);
  vec2 c1 = vec2(v1.x + 0.5 * v1.y, 0.8660254 * v1.y) * toUv;
  vec2 c2 = vec2(v2.x + 0.5 * v2.y, 0.8660254 * v2.y) * toUv;
  vec2 c3 = vec2(v3.x + 0.5 * v3.y, 0.8660254 * v3.y) * toUv;

  vec3 a = cellSample(uv, v1, c1);
  vec3 b = cellSample(uv, v2, c2);
  vec3 c = cellSample(uv, v3, c3);

  // Sharpen the cross-fade and let brighter detail win, so the join
  // reads as one texture instead of a ghosted double image.
  vec3 lum = mix(vec3(1.0), vec3(luma(a), luma(b), luma(c)), 0.6);
  vec3 weights = lum * pow(w, vec3(6.0));
  weights /= weights.x + weights.y + weights.z;
  vec3 colour = a * weights.x + b * weights.y + c * weights.z;

  // Blending three unrelated samples flattens contrast toward the
  // average colour; stretch it back out (variance-preserving blend).
  float spread = inversesqrt(dot(weights, weights));
  colour = uMean + (colour - uMean) * min(spread, 1.8);

  // Slow brightness drift and tint patches, fixed to the ground.
  float drift = fbm(world / 16.0 + uSeed * 1.7);
  colour *= 1.0 + uVariation * (drift - 0.5) * 2.0;
  float patches = smoothstep(0.42, 0.78, fbm(world / 7.0 + uSeed * 3.3 + 50.0));
  vec3 tinted = uTint.rgb * (luma(colour) / max(luma(uTint.rgb), 0.01));
  colour = mix(colour, tinted, uTint.a * patches);

  // Past the smallest copy, fade toward the average colour rather than
  // let the last copy shimmer.
  colour = mix(colour, uMean, smoothstep(levels - 1.0, levels + 0.5, lod) * 0.7);

  colour = clamp(colour, 0.0, 1.0);

  // Edge mask mode: instead of colour, how far this spot of ground
  // reaches past a patch's outline. Bright detail (grass blades, clods)
  // reaches furthest, so the edge follows the texture, like game terrain
  // height blending; noise keeps it from tracing the texture's cells.
  if (uEdge.x > 0.0) {
    float height = clamp((luma(colour) - luma(uMean)) * 3.0 + 0.5, 0.0, 1.0);
    // Broad wobble plus a finer breakup a quarter the size, so the edge
    // frays in small tufts instead of reading as a smooth blob.
    float rough = 0.65 * fbm(world / uEdge.y + uSeed * 5.1) +
        0.35 * valueNoise(world / (uEdge.y * 0.25) + uSeed * 9.7);
    // Stretch the mix to use the whole 0..1 range: raw fbm and detail
    // cluster round 0.5, which would move the edge only a few pixels.
    float mixed = 0.5 * height + 0.5 * rough;
    float reach = uEdge.x * clamp((mixed - 0.5) * 2.6 + 0.5, 0.0, 1.0);
    fragColor = vec4(reach);
    return;
  }

  fragColor = vec4(colour, 1.0);
}
