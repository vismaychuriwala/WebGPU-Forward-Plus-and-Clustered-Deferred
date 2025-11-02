// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.

const X_SLICES: u32 = ${xSlices};
const Y_SLICES: u32 = ${ySlices};
const Z_SLICES: u32 = ${zSlices};
const MAX_LIGHTS_PER_CLUSTER: u32 = ${maxLightsPerCluster};

@group(${bindGroup_scene}) @binding(0)
var<uniform> camera_uniforms: CameraUniforms;

@group(${bindGroup_scene}) @binding(1)
var<storage, read> lightSet: LightSet;

@group(${bindGroup_scene}) @binding(2)
var<storage, read> clusterGrid: array<ClusterRecord>;

@group(${bindGroup_scene}) @binding(3)
var<storage, read> clusterLightIndices: array<u32>;

// G-buffer inputs
@group(${bindGroup_scene}) @binding(4)
var gAlbedo: texture_2d<f32>;

@group(${bindGroup_scene}) @binding(5)
var gNormal: texture_2d<f32>;

@group(${bindGroup_scene}) @binding(6)
var gDepth: texture_depth_2d;

@group(${bindGroup_scene}) @binding(7)
var gPosition: texture_2d<f32>;

struct FragmentInput {
  @builtin(position) fragCoord: vec4f,
};

fn clusterIndex(ix: u32, iy: u32, iz: u32) -> u32 {
  return ix + iy * X_SLICES + iz * X_SLICES * Y_SLICES;
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
  let ij: vec2u = vec2u(in.fragCoord.xy);

  // Read G-buffer
  let baseColor: vec4f = textureLoad(gAlbedo, ij, 0);
  if (baseColor.a < 0.5) {
    discard;
  }

  let nEnc: vec3f = textureLoad(gNormal, ij, 0).xyz;
  let N: vec3f = normalize(nEnc * 2.0 - vec3f(1.0));

  let worldPos: vec3f = textureLoad(gPosition, ij, 0).xyz;

  let viewPos: vec3f =
    (camera_uniforms.viewMat * vec4f(worldPos, 1.0)).xyz;
  let d: f32 = -viewPos.z;

  let tanHalfFovY = camera_uniforms.tanHalfFovY;
  let tanHalfFovX = camera_uniforms.tanHalfFovX;

  let nx: f32 = viewPos.x / (d * tanHalfFovX);
  let ny: f32 = viewPos.y / (d * tanHalfFovY);

  let xTile: u32 = u32(clamp(
    (nx * 0.5 + 0.5) * f32(X_SLICES), 0.0, f32(X_SLICES - 1u)
  ));
  let yTile: u32 = u32(clamp(
    (ny * 0.5 + 0.5) * f32(Y_SLICES), 0.0, f32(Y_SLICES - 1u)
  ));

  let nearP = camera_uniforms.nearPlane;
  let farP = camera_uniforms.farPlane;
  let t: f32 = clamp((d - nearP) / (farP - nearP), 0.0, 1.0);
  let zTile: u32 = u32(clamp(t * f32(Z_SLICES), 0.0, f32(Z_SLICES - 1u)));

  let cIdx: u32 = clusterIndex(xTile, yTile, zTile);
  let rec: ClusterRecord = clusterGrid[cIdx];
  let base: u32 = rec.offset;
  let count: u32 = min(rec.count, MAX_LIGHTS_PER_CLUSTER);

  var totalLight: vec3f = vec3f(0.0);
  for (var i: u32 = 0u; i < count; i = i + 1u) {
    let li: u32 = clusterLightIndices[base + i];
    let light = lightSet.lights[li];
    totalLight += calculateLightContrib(light, worldPos, N);
  }

  let lit: vec3f = baseColor.rgb * totalLight;
  return vec4f(lit, 1.0);
}