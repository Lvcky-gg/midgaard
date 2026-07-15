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
	feats := geo_layers.scene_visible_features(&app.scene)
	defer delete(feats)

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
			i, feats[i].name, sx, sy, got)
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

	feats := geo_layers.scene_visible_features(&app.scene)
	defer delete(feats)

	eye := geo_core.camera_eye(app.camera)
	for p, i in pts {
		to_eye := geo_core.v3_sub(eye, p.position)
		if geo_core.v3_dot(p.position, to_eye) > 0 { continue }

		// Back-side feature: even clicking its projected position must miss it.
		sx, sy, ok := geo_core.camera_world_to_screen(app.camera, p.position, 1920, 1080)
		if !ok { continue }
		got := pick_feature(&app, f64(sx), f64(sy))
		testing.expectf(t, got != i,
			"picked back-side feature %d (%s)", i, feats[i].name)
	}
}

@(test)
test_hidden_layer_features_not_pickable :: proc(t: ^testing.T) {
	app := _test_app(1920, 1080)
	defer geo_layers.scene_destroy(&app.scene)

	all := geo_layers.scene_visible_features(&app.scene)
	total := len(all)
	delete(all)

	// Hide every layer: nothing should be pickable anywhere on screen.
	for &fl in app.scene.feature_layers {
		fl.base.visible = false
	}
	empty := geo_layers.scene_visible_features(&app.scene)
	testing.expectf(t, len(empty) == 0, "expected no visible features, got %d", len(empty))
	delete(empty)

	pts := geo_layers.scene_feature_points(&app.scene)
	testing.expectf(t, len(pts) == 0, "expected no feature points, got %d", len(pts))
	delete(pts)

	// Show only the second layer: the flattened order must re-index from 0
	// and only contain that layer's features.
	app.scene.feature_layers[1].base.visible = true
	partial := geo_layers.scene_visible_features(&app.scene)
	defer delete(partial)
	testing.expectf(t, len(partial) > 0 && len(partial) < total,
		"expected a strict subset of %d features, got %d", total, len(partial))
	for &f in partial {
		testing.expectf(t, f.category == .Sensor,
			"expected only Sensor Net features, got %v (%s)", f.category, f.name)
	}
}
