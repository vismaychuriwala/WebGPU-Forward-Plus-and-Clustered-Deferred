// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

// forward_plus.fs.wgsl

// Constants injected from shaders/constants
const X_SLICES: u32 = ${xSlices};
const Y_SLICES: u32 = ${ySlices};
const Z_SLICES: u32 = ${zSlices};
const MAX_LIGHTS_PER_CLUSTER: u32 = ${maxLightsPerCluster};

// Match the format written by the clustering compute pass


@group(${bindGroup_material}) @binding(0)
var diffuseTex: texture_2d<f32>;

@group(${bindGroup_material}) @binding(1)
var diffuseTexSampler: sampler;


@group(${bindGroup_scene}) @binding(0)
var<uniform> camera_uniforms: CameraUniforms;

@group(${bindGroup_scene}) @binding(1)
var<storage, read> lightSet: LightSet;

@group(${bindGroup_scene}) @binding(2)
var<storage, read> clusterGrid: array<ClusterRecord>;

@group(${bindGroup_scene}) @binding(3)
var<storage, read> clusterLightIndices: array<u32>;


struct FragmentInput {
  @location(0) pos: vec3f, // world space position (from VS)
  @location(1) nor: vec3f,
  @location(2) uv: vec2f,
}

fn clusterIndex(ix: u32, iy: u32, iz: u32) -> u32 {
  return ix + iy * X_SLICES + iz * X_SLICES * Y_SLICES;
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
  let baseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
  if (baseColor.a < 0.5) {
    discard;
  }

  let viewPos = (camera_uniforms.viewMat * vec4f(in.pos, 1.0)).xyz;
  let d = -viewPos.z; // positive distance forward from camera

  let tanHalfFovY = camera_uniforms.tanHalfFovY;
  let tanHalfFovX = camera_uniforms.tanHalfFovX;

  // ndc
  let nx = viewPos.x / (d * tanHalfFovX);
  let ny = viewPos.y / (d * tanHalfFovY);

  // Convert to tile-space
  let xTile = u32(clamp((nx * 0.5 + 0.5) * f32(X_SLICES),
                        0.0, f32(X_SLICES - 1u)));
  let yTile = u32(clamp((ny * 0.5 + 0.5) * f32(Y_SLICES),
                        0.0, f32(Y_SLICES - 1u)));

  // Z slice (linear)
  let nearP = camera_uniforms.nearPlane;
  let farP  = camera_uniforms.farPlane;
  let t = clamp((d - nearP) / (farP - nearP), 0.0, 1.0);
  let zTile = u32(clamp(t * f32(Z_SLICES), 0.0, f32(Z_SLICES - 1u)));

  let cIdx = clusterIndex(xTile, yTile, zTile);
  let rec = clusterGrid[cIdx];
  let base = rec.offset;
  let count = rec.count;

  var totalLight = vec3f(0.0, 0.0, 0.0);
  let N = normalize(in.nor);

  // Safety: clamp count to MAX_LIGHTS_PER_CLUSTER to avoid OOB
  let safeCount = min(count, MAX_LIGHTS_PER_CLUSTER);

  for (var i: u32 = 0u; i < safeCount; i = i + 1u) {
    let li = clusterLightIndices[base + i];
    let light = lightSet.lights[li];
    totalLight += calculateLightContrib(light, in.pos, N);
  }

  let litColor = baseColor.rgb * totalLight;
  return vec4f(litColor, 1.0);
}