package geo_layers

import geo_core "../geo_core"

// Scene is the live, mutable world state.
Scene :: struct {
	layers:   [dynamic]Layer,
	imagery_layers: [dynamic]ImageryLayer,
	feature_layers: [dynamic]FeatureLayer,
	routes:   [dynamic]Route,
}

// Feature_Point is the GPU-ready vertex for feature rendering: world xyz + color.
Feature_Point :: struct {
	position: [3]f32,
	color:    [4]f32,
}

scene_destroy :: proc(s: ^Scene) {
	for &fl in s.feature_layers {
		delete(fl.features)
	}
	delete(s.layers)
	delete(s.imagery_layers)
	delete(s.feature_layers)
	delete(s.routes)
}

scene_add_layer :: proc(s: ^Scene, l: Layer) {
	append(&s.layers, l)
}

scene_add_imagery_layer :: proc(s: ^Scene, l: ImageryLayer) {
	append(&s.imagery_layers, l)
}

scene_add_feature_layer :: proc(s: ^Scene, l: FeatureLayer) {
	append(&s.feature_layers, l)
}

scene_add_route :: proc(s: ^Scene, r: Route) {
	append(&s.routes, r)
}

// scene_feature_count returns the total feature count across all layers,
// visible or not.
scene_feature_count :: proc(s: ^Scene) -> int {
	n := 0
	for &fl in s.feature_layers {
		n += len(fl.features)
	}
	return n
}

// scene_visible_features flattens the features of visible layers in stable
// order (layer order, then feature order). This order matches the GPU
// buffers, so an index into this slice doubles as a pick/highlight index.
// Caller owns the returned slice.
scene_visible_features :: proc(s: ^Scene) -> []Feature {
	feats := make([dynamic]Feature)
	for &fl in s.feature_layers {
		if !fl.base.visible { continue }
		append(&feats, ..fl.features[:])
	}
	return feats[:]
}

// scene_feature_points projects each visible feature onto the unit sphere at
// radius 1.01.
scene_feature_points :: proc(s: ^Scene) -> []Feature_Point {
	feats := scene_visible_features(s)
	defer delete(feats)

	pts := make([dynamic]Feature_Point)
	for &f in feats {
		xyz := geo_core.lat_lon_to_xyz(
			geo_core.LatLon{lat = f.position.lat, lon = f.position.lon}, 1.01)
		append(&pts, Feature_Point{
			position = {f32(xyz.x), f32(xyz.y), f32(xyz.z)},
			color    = f.color,
		})
	}
	return pts[:]
}
