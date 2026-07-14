package geo_layers

import geo_core "../geo_core"

// Scene is the live, mutable world state.
Scene :: struct {
	layers:   [dynamic]Layer,
	imagery_layers: [dynamic]ImageryLayer,
	features: [dynamic]Feature,
	routes:   [dynamic]Route,
}

// Feature_Point is the GPU-ready vertex for feature rendering: world xyz + color.
Feature_Point :: struct {
	position: [3]f32,
	color:    [4]f32,
}

scene_destroy :: proc(s: ^Scene) {
	delete(s.layers)
	delete(s.imagery_layers)
	delete(s.features)
	delete(s.routes)
}

scene_add_layer :: proc(s: ^Scene, l: Layer) {
	append(&s.layers, l)
}

scene_add_imagery_layer :: proc(s: ^Scene, l: ImageryLayer) {
	append(&s.imagery_layers, l)
}

scene_add_feature :: proc(s: ^Scene, f: Feature) {
	append(&s.features, f)
}

scene_add_route :: proc(s: ^Scene, r: Route) {
	append(&s.routes, r)
}

// scene_feature_points projects each feature onto the unit sphere at radius 1.01.
scene_feature_points :: proc(s: ^Scene) -> []Feature_Point {
	pts := make([dynamic]Feature_Point)
	for &f in s.features {
		xyz := geo_core.lat_lon_to_xyz(
			geo_core.LatLon{lat = f.position.lat, lon = f.position.lon}, 1.01)
		append(&pts, Feature_Point{
			position = {f32(xyz.x), f32(xyz.y), f32(xyz.z)},
			color    = f.color,
		})
	}
	return pts[:]
}
