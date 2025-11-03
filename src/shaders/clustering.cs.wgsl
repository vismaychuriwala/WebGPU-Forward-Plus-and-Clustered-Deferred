// TODO-2: implement the light clustering compute shader

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.

//     For each light:
//         - Check if the light intersects with the cluster’s bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.

//     - Store the number of lights assigned to this cluster.

const X_SLICES: u32 = ${xSlices};
const Y_SLICES: u32 = ${ySlices};
const Z_SLICES: u32 = ${zSlices};
const MAX_LIGHTS_PER_CLUSTER: u32 = ${maxLightsPerCluster};

// Workgroup size
const WG_SIZE_X: u32 = ${clusterWorkgroupSizeX};
const WG_SIZE_Y: u32 = ${clusterWorkgroupSizeY};

const LIGHT_RADIUS: f32 = f32(${lightRadius});
const LIGHT_RADIUS2: f32 = LIGHT_RADIUS * LIGHT_RADIUS;

struct AABB {
  min: vec3f,
  max: vec3f,
};

@group(0) @binding(0) var<uniform> camera_uniforms: CameraUniforms;
@group(0) @binding(1) var<storage, read> lightSet: LightSet;
@group(0) @binding(2) var<storage, read_write> clusterGrid: array<ClusterRecord>;
@group(0) @binding(3) var<storage, read_write> clusterLightIndices: array<u32>;

fn lerp(a: f32, b: f32, t: f32) -> f32 {
  return a + (b - a) * t;
}

fn edge_to_ndc(idx: u32, total: u32) -> f32 {
  return -1.0 + 2.0 * (f32(idx) / f32(total));
}

fn cluster_index(ix: u32, iy: u32, iz: u32) -> u32 {
  return ix + iy * X_SLICES + iz * X_SLICES * Y_SLICES;
}

fn dist2_point_aabb(p: vec3f, bmin: vec3f, bmax: vec3f) -> f32 {
  var dx = 0.0;
  if (p.x < bmin.x) {
    dx = bmin.x - p.x;
  } else if (p.x > bmax.x) {
    dx = p.x - bmax.x;
  }

  var dy = 0.0;
  if (p.y < bmin.y) {
    dy = bmin.y - p.y;
  } else if (p.y > bmax.y) {
    dy = p.y - bmax.y;
  }

  var dz = 0.0;
  if (p.z < bmin.z) {
    dz = bmin.z - p.z;
  } else if (p.z > bmax.z) {
    dz = p.z - bmax.z;
  }

  return dx * dx + dy * dy + dz * dz;
}

fn compute_cluster_bounds(ix: u32, iy: u32, iz: u32) -> AABB {
  let tanY = camera_uniforms.tanHalfFovY;
  let tanX = camera_uniforms.tanHalfFovX;

  // Logarithmic Z slicing
  let nearP = camera_uniforms.nearPlane;
  let farP = camera_uniforms.farPlane;
  let t0 = f32(iz) / f32(Z_SLICES);
  let t1 = f32(iz + 1u) / f32(Z_SLICES);
  let z_near_d = nearP * pow(farP / nearP, t0);
  let z_far_d  = nearP * pow(farP / nearP, t1);

  let z0 = -z_near_d;
  let z1 = -z_far_d;

  let x0_ndc = edge_to_ndc(ix, X_SLICES);
  let x1_ndc = edge_to_ndc(ix + 1u, X_SLICES);
  let y0_ndc = edge_to_ndc(iy, Y_SLICES);
  let y1_ndc = edge_to_ndc(iy + 1u, Y_SLICES);

  let depth_pos_near = z_near_d;
  let depth_pos_far = z_far_d; // = -z1
  let x0_near = x0_ndc * depth_pos_near * tanX;
  let x1_near = x1_ndc * depth_pos_near * tanX;
  let x0_far = x0_ndc * depth_pos_far * tanX;
  let x1_far = x1_ndc * depth_pos_far * tanX;
  let y0_near = y0_ndc * depth_pos_near * tanY;
  let y1_near = y1_ndc * depth_pos_near * tanY;
  let y0_far = y0_ndc * depth_pos_far * tanY;
  let y1_far = y1_ndc * depth_pos_far * tanY;

  let x_min = min(min(x0_near, x1_near), min(x0_far, x1_far));
  let x_max = max(max(x0_near, x1_near), max(x0_far, x1_far));
  let y_min = min(min(y0_near, y1_near), min(y0_far, y1_far));
  let y_max = max(max(y0_near, y1_near), max(y0_far, y1_far));

  let z_min = min(z0, z1);
  let z_max = max(z0, z1);

  return AABB(vec3f(x_min, y_min, z_min), vec3f(x_max, y_max, z_max));
}

fn light_view_pos(world_pos: vec3f) -> vec3f {
  let viewPos4 = camera_uniforms.viewMat * vec4f(world_pos, 1.0);
    return viewPos4.xyz;
}

@compute @workgroup_size(WG_SIZE_X, WG_SIZE_Y, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  if (gid.x >= X_SLICES || gid.y >= Y_SLICES || gid.z >= Z_SLICES) {
    return;
  }

  let idx = cluster_index(gid.x, gid.y, gid.z);
  let base = idx * MAX_LIGHTS_PER_CLUSTER;

  // Compute cluster view-space AABB
  let bounds = compute_cluster_bounds(gid.x, gid.y, gid.z);
  let bmin = bounds.min;
  let bmax = bounds.max;

  // Fill list
  var count: u32 = 0u;

  for (var i: u32 = 0u; i < lightSet.numLights; i = i + 1u) {
    // World-space -> view-space
    let p_view = light_view_pos(lightSet.lights[i].pos);

    // Quick reject on Z (optional)
    if (p_view.z < bmin.z - LIGHT_RADIUS || p_view.z > bmax.z + LIGHT_RADIUS) {
      continue;
    }

    let d2 = dist2_point_aabb(p_view, bmin, bmax);
    if (d2 <= LIGHT_RADIUS2) {
      if (count < MAX_LIGHTS_PER_CLUSTER) {
        clusterLightIndices[base + count] = i;
        count = count + 1u;
      }
    }
  }

  // Store offset and count
  clusterGrid[idx].offset = base;
  clusterGrid[idx].count = count;
}
