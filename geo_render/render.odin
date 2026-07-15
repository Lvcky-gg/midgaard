package geo_render

// Push_Constants is the block shared by all shaders across backends.
// Field order matches GLSL std430 push_constant offsets:
// mat4 @0, float @64, int @68, vec2 @72, vec4 @80 — total 96 bytes.
Push_Constants :: struct {
	mvp: [16]f32,
	time_sec: f32,
	selected_index: i32, // vertex index of the picked feature, -1 for none
	viewport: [2]f32,    // framebuffer size in pixels
	eye: [4]f32,         // camera eye position (w unused)
}

// Draw_Command is a backend-agnostic draw instruction produced by the scene graph.
// Backends (geo_cvulkan, geo_webgl) translate these into GPU calls.
Draw_Command :: struct {
	vertex_offset: u32,
	index_offset:  u32,
	index_count:   u32,
	instance_count: u32,
	mvp:           [16]f32,
}
