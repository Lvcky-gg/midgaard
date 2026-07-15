package geo_app

import "core:fmt"
import "core:math"
import geo_core   "../geo_core"
import geo_layers "../geo_layers"

PICK_RADIUS_PX :: 18.0

// pick_feature returns the index of the closest front-facing feature within
// PICK_RADIUS_PX of the cursor, or -1 when nothing is hit.
pick_feature :: proc(app: ^App, cursor_x, cursor_y: f64) -> int {
	pts := geo_layers.scene_feature_points(&app.scene)
	defer delete(pts)

	eye := geo_core.camera_eye(app.camera)
	w := f32(app.swapchain.extent.width)
	h := f32(app.swapchain.extent.height)

	best := -1
	best_d := f32(PICK_RADIUS_PX)
	for p, i in pts {
		// Hemisphere test: skip features on the far side of the globe.
		to_eye := geo_core.v3_sub(eye, p.position)
		if geo_core.v3_dot(p.position, to_eye) <= 0 { continue }

		sx, sy, ok := geo_core.camera_world_to_screen(app.camera, p.position, w, h)
		if !ok { continue }

		dx := sx - f32(cursor_x)
		dy := sy - f32(cursor_y)
		d := math.sqrt(dx*dx + dy*dy)
		if d < best_d {
			best_d = d
			best = i
		}
	}
	return best
}

// app_handle_click resolves a click into feature selection state.
// The flattened visible-feature order matches the feature vertex buffer, so
// the picked index doubles as the shader's selected_index.
app_handle_click :: proc(app: ^App, x, y: f64) {
	idx := pick_feature(app, x, y)
	app.selected_feature = i32(idx)

	feats := geo_layers.scene_visible_features(&app.scene)
	defer delete(feats)

	if idx >= 0 && idx < len(feats) {
		f := feats[idx]
		fmt.printf("Selected feature #%d — %s  [%v]  lat:%.4f lon:%.4f elev:%.0fm\n",
			f.id, f.name, f.category, f.position.lat, f.position.lon, f.elevation_m)
	} else {
		fmt.println("Selection cleared")
	}
}
