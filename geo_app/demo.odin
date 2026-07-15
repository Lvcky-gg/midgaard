package geo_app

import geo_core   "../geo_core"
import geo_layers "../geo_layers"

// demo_scene builds the seed scene for local testing.
demo_scene :: proc() -> geo_layers.Scene {
	s: geo_layers.Scene

	geo_layers.scene_add_imagery_layer(&s, geo_layers.ImageryLayer{
		base = {kind = .Imagery, name = "Edge Base Imagery", visible = true},
		source = .TMS_HTTP,
		cache_root = "./.cache/imagery/base",
		bundle_root = "./edge_bundles/imagery/base",
		url_template = "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox={west},{south},{east},{north}&bboxSR=4326&imageSR=4326&size={size},{size}&format=jpg&f=image",
		gjallarhorn_endpoint = "",
		file_ext = "jpg",
		tile_size = 512,
		min_zoom = 0,
		max_zoom = 10,
		tms_y = false,
		edge_first = true,
	})

	geo_layers.scene_add_layer(&s, geo_layers.Layer{kind = .Imagery,    name = "Base Imagery", visible = true})
	geo_layers.scene_add_layer(&s, geo_layers.Layer{kind = .Elevation,  name = "Terrain",      visible = true})
	geo_layers.scene_add_layer(&s, geo_layers.Layer{kind = .Feature,    name = "Ops Features", visible = true})
	geo_layers.scene_add_layer(&s, geo_layers.Layer{kind = .Annotation, name = "Annotations",  visible = true})
	geo_layers.scene_add_layer(&s, geo_layers.Layer{kind = .Sensor,     name = "Sensor Feeds", visible = false})

	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 1, name = "North Harbor Node", position = geo_core.LatLon{lat =  37.7749, lon = -122.4194}, elevation_m =  18.0, category = .Facility,    color = {0.95, 0.76, 0.35, 1}})
	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 2, name = "Ridge Relay",       position = geo_core.LatLon{lat =  34.0522, lon = -118.2437}, elevation_m = 420.0, category = .Sensor,      color = {0.33, 0.85, 0.92, 1}})
	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 3, name = "Coastal Ops Cell",  position = geo_core.LatLon{lat =  47.6062, lon = -122.3321}, elevation_m =  60.0, category = .City,        color = {0.58, 0.95, 0.46, 1}})
	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 4, name = "Forward Cache",     position = geo_core.LatLon{lat =  35.6895, lon =  139.6917}, elevation_m =  40.0, category = .Route_Point, color = {0.98, 0.42, 0.28, 1}})
	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 5, name = "Imagery Index",     position = geo_core.LatLon{lat =  51.5074, lon =   -0.1278}, elevation_m =  35.0, category = .Note,        color = {0.85, 0.78, 0.98, 1}})
	geo_layers.scene_add_feature(&s, geo_layers.Feature{id = 6, name = "Southern Sensor",   position = geo_core.LatLon{lat = -33.8688, lon =  151.2093}, elevation_m =  22.0, category = .Sensor,      color = {0.72, 0.91, 1.00, 1}})

	geo_layers.scene_add_route(&s, geo_layers.Route{name = "Harbor to Cache", start = geo_core.LatLon{lat = 37.7749, lon = -122.4194}, finish = geo_core.LatLon{lat = 35.6895, lon = 139.6917}, color = {0.98, 0.62, 0.25, 0.9}})
	geo_layers.scene_add_route(&s, geo_layers.Route{name = "Ops Link",        start = geo_core.LatLon{lat = 47.6062, lon = -122.3321}, finish = geo_core.LatLon{lat = 51.5074, lon =  -0.1278}, color = {0.35, 0.75, 1.00, 0.9}})

	return s
}
