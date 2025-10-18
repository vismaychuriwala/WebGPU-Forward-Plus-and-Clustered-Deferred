// TODO-3: implement the Clustered Deferred fullscreen vertex shader

// This shader should be very simple as it does not need all of the information passed by the the naive vertex shader.

struct VertexOutput {
    @builtin(position) fragPos: vec4f,
    @location(0) uv: vec2f,
    @location(2) position: vec4f,
};

@vertex
fn main(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    var out: VertexOutput;

    // Generate a full-screen triangle directly on the GPU without buffers:
    // Positions in clip space
    let positions = array<vec2f, 3>(
        vec2f(-1.0, -3.0),
        vec2f(3.0, 1.0),
        vec2f(-1.0, 1.0)
    );

    let uvs = array<vec2f, 3>(
        vec2f(0.0, 2.0),
        vec2f(2.0, 0.0),
        vec2f(0.0, 0.0)
    );

    out.fragPos = vec4f(positions[vertexIndex], 0.0, 1.0);
    out.uv = uvs[vertexIndex];
    return out;
}