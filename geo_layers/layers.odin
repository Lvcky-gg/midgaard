package geo_layers

import geo_core "../geo_core"

// Layer_Kind is the canonical set of layer types.
Layer_Kind :: enum {
	Imagery,
	Elevation,
	Feature,
	Annotation,
	Sensor,
}

Feature_Category :: enum {
	City,
	Facility,
	Route_Point,
	Sensor,
	Note,
}

Layer :: struct {
	kind:    Layer_Kind,
	name:    string,
	visible: bool,
}

Feature :: struct {
	id:          int,
	name:        string,
	position:    geo_core.LatLon,
	elevation_m: f64,
	category:    Feature_Category,
	color:       [4]f32,
}

Route :: struct {
	name:   string,
	start:  geo_core.LatLon,
	finish: geo_core.LatLon,
	color:  [4]f32,
}

// ── Canonical layer type stubs ────────────────────────────────────────────────

ElevationLayer :: struct {
	base:       Layer,
	source_url: string,
}

FeatureLayer :: struct {
	base:     Layer,
	features: [dynamic]Feature,
}

AnnotationLayer :: struct {
	base:  Layer,
	items: [dynamic]Feature,
}

SensorLayer :: struct {
	base: Layer,
}

Imagery_Source_Kind :: enum {
	Bundle_Only,
	TMS_HTTP,
	Gjallarhorn_Proxy,
}

// ImageryLayer is edge-first by default: read local cache first, then network.
ImageryLayer :: struct {
	base: Layer,
	source: Imagery_Source_Kind,

	cache_root: string,
	bundle_root: string,

	url_template: string,
	gjallarhorn_endpoint: string,

	file_ext: string,
	tile_size: i32,
	min_zoom: i32,
	max_zoom: i32,
	tms_y: bool,
	edge_first: bool,
}
