package geo_core

import "core:math"

// Vertex is the per-vertex layout expected by globe.vert.
Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Globe_Mesh :: struct {
	vertices: []Vertex,
	indices:  []u32,
}

// build_globe_mesh generates a UV sphere.
// stacks = latitude divisions, slices = longitude divisions.
build_globe_mesh :: proc(stacks, slices: int) -> Globe_Mesh {
	verts := make([dynamic]Vertex, 0, (stacks+1)*(slices+1))
	idxs  := make([dynamic]u32,    0, stacks*slices*6)

	for stack in 0..=stacks {
		v   := f32(stack) / f32(stacks)
		phi := v * f32(math.PI)
		sp  := math.sin_f32(phi)
		cp  := math.cos_f32(phi)

		for slice in 0..=slices {
			u     := f32(slice) / f32(slices)
			theta := u * f32(math.TAU)
			st    := math.sin_f32(theta)
			ct    := math.cos_f32(theta)

			x := sp * ct
			y := cp
			z := sp * st

			append(&verts, Vertex{
				position = {x, y, z},
				normal   = {x, y, z},
				uv       = {u, 1 - v},
			})
		}
	}

	stride := slices + 1
	for stack in 0..<stacks {
		for slice in 0..<slices {
			a := u32(stack*stride + slice)
			b := a + u32(stride)
			append(&idxs, a, b, a+1, b, b+1, a+1)
		}
	}

	return Globe_Mesh{vertices = verts[:], indices = idxs[:]}
}
