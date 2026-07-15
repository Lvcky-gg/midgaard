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

// displace_globe_mesh scales each vertex of a build_globe_mesh result to the
// given per-vertex radius (same stack-major order) and recomputes normals
// from the displaced grid so terrain relief shades correctly.
displace_globe_mesh :: proc(mesh: ^Globe_Mesh, stacks, slices: int, radii: []f32) {
	stride := slices + 1
	if len(radii) != len(mesh.vertices) { return }

	for &v, i in mesh.vertices {
		n := v.normal // unit sphere direction from build_globe_mesh
		v.position = {n[0]*radii[i], n[1]*radii[i], n[2]*radii[i]}
	}

	for stack in 0..=stacks {
		for slice in 0..=slices {
			i := stack*stride + slice

			// Longitude neighbors wrap; the seam column duplicates column 0.
			s  := slice % slices
			sm := (s - 1 + slices) % slices
			sp := (s + 1) % slices
			im := stack*stride + sm
			ip := stack*stride + sp
			jm := max(stack-1, 0)*stride + s
			jp := min(stack+1, stacks)*stride + s

			du := v3_sub(mesh.vertices[ip].position, mesh.vertices[im].position)
			dv := v3_sub(mesh.vertices[jp].position, mesh.vertices[jm].position)
			n  := v3_cross(dv, du)

			pos := mesh.vertices[i].position
			if v3_dot(n, pos) < 0 {
				n = {-n[0], -n[1], -n[2]}
			}
			if v3_dot(n, n) < 1e-12 {
				n = pos // degenerate at poles: fall back to radial normal
			}
			mesh.vertices[i].normal = v3_norm(n)
		}
	}
}
