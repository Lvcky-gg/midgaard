package geo_app

import "core:testing"
import geo_core   "../geo_core"
import geo_layers "../geo_layers"

// _test_app builds an App with just enough state for picking: scene, camera,
// and a swapchain extent. No window or GPU is involved.
_test_app :: proc(width, height: u32) -> App {
	app: App
	app.scene = demo_scene()
	app.selected_feature = -1
	app.swapchain.extent.width = width
	app.swapchain.extent.height = height
	app.camera = geo_core.camera_create(width, height)
	return app
}

@(test)
test_pick_hits_projected_features :: proc(t: ^testing.T) {
	app := _test_app(1920, 1080)
	defer geo_layers.scene_destroy(&app.scene)

	pts := geo_layers.scene_feature_points(&app.scene)
	defer delete(pts)

	eye := geo_core.camera_eye(app.camera)
	front_facing := 0

	for p, i in pts {
		to_eye := geo_core.v3_sub(eye, p.position)
		if geo_core.v3_dot(p.position, to_eye) <= 0 { continue }

		sx, sy, ok := geo_core.camera_world_to_screen(app.camera, p.position, 1920, 1080)
		if !ok { continue }
		if sx < 0 || sx >= 1920 || sy < 0 || sy >= 1080 { continue }
		front_facing += 1

		got := pick_feature(&app, f64(sx), f64(sy))
		testing.expectf(t, got == i,
			"clicking feature %d (%s) at (%.1f, %.1f) picked %d",
			i, app.scene.features[i].name, sx, sy, got)
	}

	testing.expectf(t, front_facing > 0,
		"expected at least one front-facing feature with the default camera, got %d",
		front_facing)
}

@(test)
test_pick_empty_sky_returns_none :: proc(t: ^testing.T) {
	app := _test_app(1920, 1080)
	defer geo_layers.scene_destroy(&app.scene)

	// The globe is centered; the screen corner is sky at the default distance.
	got := pick_feature(&app, 5, 5)
	testing.expectf(t, got == -1, "picking empty sky returned feature %d", got)
}

@(test)
test_pick_ignores_back_side_features :: proc(t: ^testing.T) {
	app := _test_app(1920, 1080)
	defer geo_layers.scene_destroy(&app.scene)

	pts := geo_layers.scene_feature_points(&app.scene)
	defer delete(pts)

	eye := geo_core.camera_eye(app.camera)
	for p, i in pts {
		to_eye := geo_core.v3_sub(eye, p.position)
		if geo_core.v3_dot(p.position, to_eye) > 0 { continue }

		// Back-side feature: even clicking its projected position must miss it.
		sx, sy, ok := geo_core.camera_world_to_screen(app.camera, p.position, 1920, 1080)
		if !ok { continue }
		got := pick_feature(&app, f64(sx), f64(sy))
		testing.expectf(t, got != i,
			"picked back-side feature %d (%s)", i, app.scene.features[i].name)
	}
}
