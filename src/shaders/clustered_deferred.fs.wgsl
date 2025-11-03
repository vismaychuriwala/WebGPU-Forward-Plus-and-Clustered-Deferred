// TODO-3: implement the Clustered Deferred G-buffer fragment shader

// This shader should only store G-buffer information and should not do any shading.

@group(${bindGroup_material}) @binding(0)
var diffuseTex: texture_2d<f32>;

@group(${bindGroup_material}) @binding(1)
var diffuseTexSampler: sampler;

struct FragmentInput {
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f,
};

struct FragmentOutput {
    @location(0) packed: vec2<u32>,  // r: albedo.rgb packed, g: normal.xy packed
};

fn packAlbedo(color: vec3f) -> u32 {
    let r = u32(clamp(color.r, 0.0, 1.0) * 255.0);
    let g = u32(clamp(color.g, 0.0, 1.0) * 255.0);
    let b = u32(clamp(color.b, 0.0, 1.0) * 255.0);
    return (r << 16u) | (g << 8u) | b;
}

@fragment
fn main(in: FragmentInput) -> FragmentOutput {
    var out: FragmentOutput;
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }
    out.packed.r = packAlbedo(diffuseColor.rgb);
    let N = normalize(in.nor);
    out.packed.g = pack2x16snorm(N.xy);
    return out;
}