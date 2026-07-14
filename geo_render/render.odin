package geo_render

// Push_Constants is the 64-byte block shared by all shaders across backends.
Push_Constants :: struct {
	mvp: [16]f32,
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
