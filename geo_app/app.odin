package geo_app

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import glfw "vendor:glfw"
import geo_core    "../geo_core"
import geo_ingest  "../geo_ingest"
import geo_layers  "../geo_layers"
import geo_sync    "../geo_sync"
import geo_cvulkan "../geo_cvulkan"

// g_app is the single global that GLFW C callbacks can reach.
g_app: ^App

App :: struct {
	window:        Window,
	ctx:           geo_cvulkan.Vk_Context,
	swapchain:     geo_cvulkan.Vk_Swapchain,
	pipeline:      geo_cvulkan.Vk_Pipeline,
	frame:         geo_cvulkan.Vk_Frame_Data,
	globe_vb:      geo_cvulkan.Vk_Buffer,
	globe_ib:      geo_cvulkan.Vk_Buffer,
	globe_ic:      u32,
	feature_vb:    geo_cvulkan.Vk_Buffer,
	feature_count: u32,
	label_vb:      geo_cvulkan.Vk_Buffer,
	label_count:   u32,
	route_vb:      geo_cvulkan.Vk_Buffer,
	route_count:   u32,
	routes_visible: bool,
	font_tex:      geo_cvulkan.Vk_Texture,
	selected_feature: i32,
	globe_tex:     geo_cvulkan.Vk_Texture,
	globe_tex_path: string,
	imagery_frame: u64,
	imagery_scroll_cooldown: u32,
	camera_interaction_cooldown: u32,
	world_lod_switch_cooldown: u32,
	have_last_prefetch: bool,
	last_prefetch_zoom: u32,
	last_prefetch_x: u32,
	last_prefetch_y: u32,
	active_world_lod: i32,
	camera:        geo_core.Camera,
	scene:         geo_layers.Scene,
	imagery_fetch_queue: geo_sync.Edge_Fetch_Queue,
}

app_run :: proc() {
	app: App
	g_app = &app

	app.scene = demo_scene()
	app.selected_feature = -1
	app.routes_visible = true
	fmt.printf("Midgaard — layers:%d  imagery:%d  feature layers:%d  features:%d  routes:%d\n",
		len(app.scene.layers), len(app.scene.imagery_layers), len(app.scene.feature_layers),
		geo_layers.scene_feature_count(&app.scene), len(app.scene.routes))
	_warm_edge_imagery(&app)

	app.window = window_create(0, 0, "Midgaard") // size to the primary monitor

	loader := geo_cvulkan.vk_load_library()
	app.ctx      = geo_cvulkan.vk_context_create(app.window.handle, loader)
	app.swapchain = geo_cvulkan.vk_swapchain_create(&app.ctx, app.window.handle)
	app.pipeline  = geo_cvulkan.vk_pipeline_create(&app.ctx, &app.swapchain)
	app.frame     = geo_cvulkan.vk_frame_create(&app.ctx, &app.swapchain)
	app.camera    = geo_core.camera_create(app.swapchain.extent.width, app.swapchain.extent.height)
	// TEMP verification: start low over the Andes, pitched toward the horizon.
	app.camera.azimuth = 0.349
	app.camera.elevation = -0.349
	app.camera.distance = 1.15
	app.camera.pitch = 0.9

	_upload_geo(&app)
	_upload_font_atlas(&app)
	_load_globe_imagery(&app)

	for !window_should_close(&app.window) {
		glfw.PollEvents()
		_tick_imagery_streaming(&app)
		time_sec := f32(app.imagery_frame) * (1.0 / 60.0)
		ds := geo_cvulkan.Vk_Draw_State{
			ctx           = &app.ctx,
			swapchain     = &app.swapchain,
			pipeline      = &app.pipeline,
			frame         = &app.frame,
			globe_vb      = app.globe_vb,
			globe_ib      = app.globe_ib,
			globe_ic      = app.globe_ic,
			feature_vb    = app.feature_vb,
			feature_count = app.feature_count,
			label_vb      = app.label_vb,
			label_count   = app.label_count,
			route_vb      = app.route_vb,
			route_count   = app.routes_visible ? app.route_count : 0,
			mvp           = geo_core.camera_mvp(app.camera),
			time_sec      = time_sec,
			selected_index = app.selected_feature,
			viewport      = {f32(app.swapchain.extent.width), f32(app.swapchain.extent.height)},
			eye           = geo_core.camera_eye(app.camera),
		}
		geo_cvulkan.vk_draw_frame(&ds)
	}
	vk.DeviceWaitIdle(app.ctx.device)

	_destroy(&app)
}

_upload_geo :: proc(app: ^App) {
	// High enough resolution for terrain relief (~0.9deg per vertex).
	stacks, slices := 192, 384
	mesh := geo_core.build_globe_mesh(stacks, slices)
	_apply_terrain(app, &mesh, stacks, slices)
	app.globe_ic = u32(len(mesh.indices))
	app.globe_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
		vk.DeviceSize(len(mesh.vertices)*size_of(geo_core.Vertex)),
		{.VERTEX_BUFFER}, raw_data(mesh.vertices))
	app.globe_ib = geo_cvulkan.vk_buffer_upload(&app.ctx,
		vk.DeviceSize(len(mesh.indices)*size_of(u32)),
		{.INDEX_BUFFER}, raw_data(mesh.indices))
	delete(mesh.vertices)
	delete(mesh.indices)

	_upload_features(app)

	route_verts := geo_layers.scene_route_vertices(&app.scene)
	defer delete(route_verts)
	app.route_count = u32(len(route_verts))
	if len(route_verts) > 0 {
		app.route_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
			vk.DeviceSize(len(route_verts)*size_of(geo_layers.Route_Vertex)),
			{.VERTEX_BUFFER}, raw_data(route_verts))
	}
}

// _upload_features (re)builds the feature point and label buffers from the
// currently visible feature layers.
_upload_features :: proc(app: ^App) {
	pts := geo_layers.scene_feature_points(&app.scene)
	defer delete(pts)
	app.feature_count = u32(len(pts))
	if len(pts) > 0 {
		app.feature_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
			vk.DeviceSize(len(pts)*size_of(geo_layers.Feature_Point)),
			{.VERTEX_BUFFER}, raw_data(pts))
	}

	labels := geo_layers.scene_label_vertices(&app.scene)
	defer delete(labels)
	app.label_count = u32(len(labels))
	if len(labels) > 0 {
		app.label_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
			vk.DeviceSize(len(labels)*size_of(geo_layers.Label_Vertex)),
			{.VERTEX_BUFFER}, raw_data(labels))
	}
}

// app_toggle_feature_layer flips a feature layer's visibility and rebuilds
// the GPU buffers. Selection is cleared because pick indices refer to the
// flattened visible-feature order, which just changed.
app_toggle_feature_layer :: proc(app: ^App, index: int) {
	if index < 0 || index >= len(app.scene.feature_layers) { return }
	layer := &app.scene.feature_layers[index]
	layer.base.visible = !layer.base.visible
	app.selected_feature = -1

	vk.DeviceWaitIdle(app.ctx.device)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.feature_vb)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.label_vb)
	app.feature_count = 0
	app.label_count = 0
	_upload_features(app)

	fmt.printf("Layer %d — %s: %s\n", index+1, layer.base.name,
		layer.base.visible ? "visible" : "hidden")
}

app_toggle_routes :: proc(app: ^App) {
	app.routes_visible = !app.routes_visible
	fmt.printf("Routes: %s\n", app.routes_visible ? "visible" : "hidden")
}

_upload_font_atlas :: proc(app: ^App) {
	atlas := geo_layers.font_atlas_rgba8()
	defer delete(atlas)
	app.font_tex = geo_cvulkan.vk_texture_create_from_rgba8(&app.ctx,
		geo_layers.FONT_ATLAS_W, geo_layers.FONT_ATLAS_H, atlas)
	geo_cvulkan.vk_pipeline_set_label_texture(&app.ctx, &app.pipeline, &app.font_tex)
}

_destroy :: proc(app: ^App) {
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.route_vb)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.label_vb)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.feature_vb)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.globe_ib)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.globe_vb)
	geo_cvulkan.vk_texture_destroy(&app.ctx, &app.font_tex)
	geo_cvulkan.vk_texture_destroy(&app.ctx, &app.globe_tex)
	geo_cvulkan.vk_frame_destroy(&app.ctx, &app.frame)
	geo_cvulkan.vk_pipeline_destroy(&app.ctx, &app.pipeline)
	geo_cvulkan.vk_swapchain_destroy(&app.ctx, &app.swapchain)
	geo_cvulkan.vk_context_destroy(&app.ctx)
	window_destroy(&app.window)
	geo_sync.edge_fetch_queue_destroy(&app.imagery_fetch_queue)
	geo_layers.scene_destroy(&app.scene)
}

_warm_edge_imagery :: proc(app: ^App) {
	seed_keys := [4]geo_layers.Tile_Key{{z = 0, x = 0, y = 0}, {z = 1, x = 0, y = 0}, {z = 1, x = 1, y = 0}, {z = 1, x = 1, y = 1}}
	hits := 0
	queued := 0

	for i in 0..<len(app.scene.imagery_layers) {
		layer := &app.scene.imagery_layers[i]
		_ = geo_ingest.ingest_prepare_imagery_cache(layer)
		for key in seed_keys {
			tile := geo_layers.imagery_probe_tile_edge_first(layer, key)
			if tile.ok {
				hits += 1
				continue
			}
			if tile.fetch_url != "" {
				if geo_sync.edge_fetch_queue_add_unique(&app.imagery_fetch_queue, geo_sync.Imagery_Fetch_Task{
					layer_name = layer.base.name,
					cache_path = tile.cache_path,
					url = tile.fetch_url,
					status = .Queued,
				}) {
					queued += 1
				}
			}
		}
	}

	fmt.printf("Imagery edge warmup — cache hits:%d queued fetches:%d\n", hits, queued)
	if queued > 0 {
		batch := geo_sync.edge_fetch_queue_run_batch(&app.imagery_fetch_queue, 8, 8)
		fmt.printf("Imagery fetch batch — processed:%d succeeded:%d failed:%d\n",
			batch.processed, batch.succeeded, batch.failed)
	}
}

_load_globe_imagery :: proc(app: ^App) {
	_refresh_world_imagery_lod(app, 3, true)
	if app.globe_tex_path == "" {
		// Fallback to z0 tile if export endpoint is unavailable.
		_set_globe_texture_path(app, "./.cache/imagery/base/0/0/0.jpg")
	}
}

_tick_imagery_streaming :: proc(app: ^App) {
	if len(app.scene.imagery_layers) == 0 { return }

	app.imagery_frame += 1
	if app.world_lod_switch_cooldown > 0 {
		app.world_lod_switch_cooldown -= 1
	}

	// Keep this subsystem on a tighter frame budget.
	if app.imagery_frame % 3 != 0 {
		return
	}

	focus := geo_core.camera_focus_lat_lon(app.camera)
	target_zoom := _target_imagery_zoom(app.camera)

	// Keep scroll interaction responsive by deferring heavier I/O work
	// until a short cooldown after wheel input ends.
	if app.imagery_scroll_cooldown > 0 {
		app.imagery_scroll_cooldown -= 1
		return
	}

	// Keep drag-orbit and tilt interaction responsive by deferring streaming
	// while the user is actively rotating the globe.
	if app.camera_interaction_cooldown > 0 {
		app.camera_interaction_cooldown -= 1
		return
	}

	primary := &app.scene.imagery_layers[0]
	focus_key := geo_layers.imagery_lon_lat_to_tile_key(primary, [2]f64{focus.lat, focus.lon}, target_zoom)
	focus_changed := !app.have_last_prefetch ||
		app.last_prefetch_zoom != target_zoom ||
		app.last_prefetch_x != focus_key.x ||
		app.last_prefetch_y != focus_key.y

	// If camera focus hasn't changed tile/zoom, only occasionally sweep.
	if focus_changed || app.imagery_frame % 30 == 0 {
		for i in 0..<len(app.scene.imagery_layers) {
			layer := &app.scene.imagery_layers[i]
			_prefetch_focus_tiles(app, layer, focus, target_zoom)
		}
		app.have_last_prefetch = true
		app.last_prefetch_zoom = target_zoom
		app.last_prefetch_x = focus_key.x
		app.last_prefetch_y = focus_key.y
	}

	if app.imagery_frame % 30 == 0 {
		_ = geo_sync.edge_fetch_queue_run_batch(&app.imagery_fetch_queue, 1, 3)
	}

	if app.imagery_frame % 240 == 0 {
		geo_sync.edge_fetch_queue_trim_finished(&app.imagery_fetch_queue, 1024)
	}

	if app.world_lod_switch_cooldown == 0 && app.imagery_frame % 120 == 0 {
		_refresh_world_imagery_lod(app, target_zoom, false)
	}
}

_target_imagery_zoom :: proc(cam: geo_core.Camera) -> u32 {
	d := cam.distance
	if d <= 1.05 { return 10 }
	if d <= 1.10 { return 9 }
	if d <= 1.18 { return 8 }
	if d <= 1.30 { return 7 }
	if d <= 1.55 { return 6 }
	if d <= 2.20 { return 5 }
	if d <= 3.20 { return 4 }
	return 3
}

_prefetch_focus_tiles :: proc(app: ^App, layer: ^geo_layers.ImageryLayer, focus: geo_core.LatLon, target_zoom: u32) {
	if !layer.edge_first { return }
	z := target_zoom
	if layer.max_zoom > 0 && z > u32(layer.max_zoom) {
		z = u32(layer.max_zoom)
	}

	for dz := u32(0); dz <= 2; dz += 1 {
		if dz > z { break }
		tile_z := z - dz
		base := geo_layers.imagery_lon_lat_to_tile_key(layer, [2]f64{focus.lat, focus.lon}, tile_z)

		radius := 2 - int(dz)
			tiles_per_axis := int(u32(1) << tile_z)
		if tiles_per_axis <= 0 { continue }

		for oy := -radius; oy <= radius; oy += 1 {
			ny := int(base.y) + oy
			if ny < 0 || ny >= tiles_per_axis { continue }

			for ox := -radius; ox <= radius; ox += 1 {
				nx := (int(base.x) + ox) % tiles_per_axis
				if nx < 0 { nx += tiles_per_axis }

				key := geo_layers.Tile_Key{z = tile_z, x = u32(nx), y = u32(ny)}
				tile := geo_layers.imagery_probe_tile_edge_first(layer, key)
				if tile.ok {
					continue
				}
				if tile.fetch_url == "" { continue }

				_ = geo_sync.edge_fetch_queue_add_unique(&app.imagery_fetch_queue, geo_sync.Imagery_Fetch_Task{
					layer_name = layer.base.name,
					cache_path = tile.cache_path,
					url = tile.fetch_url,
					status = .Queued,
				})
			}
		}
	}
}

// Export sizes match the bbox aspect (360 x 170.1022 degrees) so ArcGIS does
// not letterbox the image with black bars; globe.frag maps the +-85.0511
// coverage back onto the full sphere.
_select_world_imagery_lod :: proc(target_zoom: u32) -> (string, string, i32) {
	if target_zoom >= 8 {
		return "./.cache/imagery/base/world_8192x3872.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=8192,3872&format=jpg&f=image",
			2
	}
	if target_zoom >= 5 {
		return "./.cache/imagery/base/world_6144x2904.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=6144,2904&format=jpg&f=image",
			1
	}
	if target_zoom >= 3 {
		return "./.cache/imagery/base/world_4096x1936.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=4096,1936&format=jpg&f=image",
			0
	}
	return "./.cache/imagery/base/world_3072x1452.jpg",
		"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=3072,1452&format=jpg&f=image",
		0
}

_refresh_world_imagery_lod :: proc(app: ^App, target_zoom: u32, allow_blocking_fetch: bool) {
	path, url, lod := _select_world_imagery_lod(target_zoom)
	if app.active_world_lod == lod && app.globe_tex_path == path {
		return
	}

	if os.exists(path) {
		_set_globe_texture_path(app, path)
		app.active_world_lod = lod
		app.world_lod_switch_cooldown = 240
		return
	}

	if allow_blocking_fetch {
		ok, err := geo_sync.edge_fetch_url_to_file(url, path, 25)
		if !ok {
			fmt.printf("Imagery world fetch failed: %s\n", err)
			return
		}
		if os.exists(path) {
			_set_globe_texture_path(app, path)
			app.active_world_lod = lod
			app.world_lod_switch_cooldown = 240
		}
		return
	}

	_ = geo_sync.edge_fetch_queue_add_unique(&app.imagery_fetch_queue, geo_sync.Imagery_Fetch_Task{
		layer_name = "world_export",
		cache_path = path,
		url = url,
		status = .Queued,
	})
}

_set_globe_texture_path :: proc(app: ^App, path: string) {
	if path == "" || !os.exists(path) { return }
	if app.globe_tex_path == path && app.globe_tex.ready { return }

	if app.globe_tex.ready {
		geo_cvulkan.vk_texture_destroy(&app.ctx, &app.globe_tex)
	}

	app.globe_tex = geo_cvulkan.vk_texture_create_from_file(&app.ctx, path)
	if !app.globe_tex.ready {
		return
	}

	app.globe_tex_path = path
	geo_cvulkan.vk_pipeline_set_globe_texture(&app.ctx, &app.pipeline, &app.globe_tex)
}
