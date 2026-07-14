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
	globe_tex:     geo_cvulkan.Vk_Texture,
	globe_tex_path: string,
	imagery_frame: u64,
	active_world_lod: i32,
	camera:        geo_core.Camera,
	scene:         geo_layers.Scene,
	imagery_fetch_queue: geo_sync.Edge_Fetch_Queue,
}

app_run :: proc() {
	app: App
	g_app = &app

	app.scene = demo_scene()
	fmt.printf("Midgaard — layers:%d  imagery:%d  features:%d  routes:%d\n",
		len(app.scene.layers), len(app.scene.imagery_layers), len(app.scene.features), len(app.scene.routes))
	_warm_edge_imagery(&app)

	app.window = window_create(1280, 800, "Midgaard")

	loader := geo_cvulkan.vk_load_library()
	app.ctx      = geo_cvulkan.vk_context_create(app.window.handle, loader)
	app.swapchain = geo_cvulkan.vk_swapchain_create(&app.ctx, app.window.handle)
	app.pipeline  = geo_cvulkan.vk_pipeline_create(&app.ctx, &app.swapchain)
	app.frame     = geo_cvulkan.vk_frame_create(&app.ctx, &app.swapchain)
	app.camera    = geo_core.camera_create(app.swapchain.extent.width, app.swapchain.extent.height)

	_upload_geo(&app)
	_load_globe_imagery(&app)

	for !window_should_close(&app.window) {
		glfw.PollEvents()
		_tick_imagery_streaming(&app)
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
			mvp           = geo_core.camera_mvp(app.camera),
		}
		geo_cvulkan.vk_draw_frame(&ds)
	}
	vk.DeviceWaitIdle(app.ctx.device)

	_destroy(&app)
}

_upload_geo :: proc(app: ^App) {
	mesh := geo_core.build_globe_mesh(48, 72)
	app.globe_ic = u32(len(mesh.indices))
	app.globe_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
		vk.DeviceSize(len(mesh.vertices)*size_of(geo_core.Vertex)),
		{.VERTEX_BUFFER}, raw_data(mesh.vertices))
	app.globe_ib = geo_cvulkan.vk_buffer_upload(&app.ctx,
		vk.DeviceSize(len(mesh.indices)*size_of(u32)),
		{.INDEX_BUFFER}, raw_data(mesh.indices))
	delete(mesh.vertices)
	delete(mesh.indices)

	pts := geo_layers.scene_feature_points(&app.scene)
	defer delete(pts)
	app.feature_count = u32(len(pts))
	if len(pts) > 0 {
		app.feature_vb = geo_cvulkan.vk_buffer_upload(&app.ctx,
			vk.DeviceSize(len(pts)*size_of(geo_layers.Feature_Point)),
			{.VERTEX_BUFFER}, raw_data(pts))
	}
}

_destroy :: proc(app: ^App) {
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.feature_vb)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.globe_ib)
	geo_cvulkan.vk_buffer_destroy(&app.ctx, &app.globe_vb)
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
			tile := geo_layers.imagery_read_tile_edge_first(layer, key)
			if tile.ok {
				hits += 1
				delete(tile.bytes)
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
	focus := geo_core.camera_focus_lat_lon(app.camera)
	target_zoom := _target_imagery_zoom(app.camera)

	for i in 0..<len(app.scene.imagery_layers) {
		layer := &app.scene.imagery_layers[i]
		_prefetch_focus_tiles(app, layer, focus, target_zoom)
	}

	if app.imagery_frame % 8 == 0 {
		_ = geo_sync.edge_fetch_queue_run_batch(&app.imagery_fetch_queue, 6, 6)
	}

	if app.imagery_frame % 240 == 0 {
		geo_sync.edge_fetch_queue_trim_finished(&app.imagery_fetch_queue, 1024)
	}

	_refresh_world_imagery_lod(app, target_zoom, false)
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
				tile := geo_layers.imagery_read_tile_edge_first(layer, key)
				if tile.ok {
					delete(tile.bytes)
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

_select_world_imagery_lod :: proc(target_zoom: u32) -> (string, string, i32) {
	if target_zoom >= 9 {
		return "./.cache/imagery/base/world_16384x8192.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=16384,8192&format=jpg&f=image",
			3
	}
	if target_zoom >= 7 {
		return "./.cache/imagery/base/world_12288x6144.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=12288,6144&format=jpg&f=image",
			2
	}
	if target_zoom >= 5 {
		return "./.cache/imagery/base/world_8192x4096.jpg",
			"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=8192,4096&format=jpg&f=image",
			1
	}
	return "./.cache/imagery/base/world_4096x2048.jpg",
		"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-180,-85.0511,180,85.0511&bboxSR=4326&imageSR=4326&size=4096,2048&format=jpg&f=image",
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
