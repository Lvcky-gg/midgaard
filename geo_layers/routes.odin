package geo_layers

import "core:math"
import geo_core "../geo_core"

// Route_Vertex is the GPU-ready vertex for route arc rendering.
// t runs 0..1 along the arc and drives the flow animation in route.frag.
Route_Vertex :: struct {
	position: [3]f32,
	t:        f32,
	color:    [4]f32,
}

ROUTE_RADIUS   :: 1.012 // just above feature points so arcs clear the surface
ROUTE_SEGMENTS :: 48

// scene_route_vertices samples each route as a great-circle arc and emits
// line-list pairs (two vertices per segment) so all routes draw in one call.
// Caller owns the returned slice.
scene_route_vertices :: proc(s: ^Scene) -> []Route_Vertex {
	verts := make([dynamic]Route_Vertex)

	for &r in s.routes {
		a := geo_core.lat_lon_to_xyz(r.start, 1.0)
		b := geo_core.lat_lon_to_xyz(r.finish, 1.0)

		dot := clamp(a.x*b.x + a.y*b.y + a.z*b.z, -1.0, 1.0)
		angle := math.acos(dot)
		if angle < 1e-6 { continue }
		inv_sin := 1.0 / math.sin(angle)

		prev: Route_Vertex
		for i in 0..=ROUTE_SEGMENTS {
			t := f64(i) / f64(ROUTE_SEGMENTS)
			wa := math.sin((1.0-t)*angle) * inv_sin
			wb := math.sin(t*angle) * inv_sin
			p := geo_core.Vec3{
				x = (wa*a.x + wb*b.x) * ROUTE_RADIUS,
				y = (wa*a.y + wb*b.y) * ROUTE_RADIUS,
				z = (wa*a.z + wb*b.z) * ROUTE_RADIUS,
			}
			v := Route_Vertex{
				position = {f32(p.x), f32(p.y), f32(p.z)},
				t        = f32(t),
				color    = r.color,
			}
			if i > 0 {
				append(&verts, prev, v)
			}
			prev = v
		}
	}
	return verts[:]
}
