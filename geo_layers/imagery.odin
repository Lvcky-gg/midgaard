package geo_layers

import "core:fmt"
import "core:os"
import "core:strings"

Tile_Key :: struct {
	z: u32,
	x: u32,
	y: u32,
}

Imagery_Tile_Source :: enum {
	None,
	Cache,
	Bundle,
	Remote,
}

Imagery_Tile_Result :: struct {
	ok: bool,
	bytes: []byte,
	source: Imagery_Tile_Source,
	cache_path: string,
	fetch_url: string,
}

imagery_max_latitude :: proc() -> f64 {
	return 85.0511
}

imagery_lon_lat_to_tile_key :: proc(layer: ^ImageryLayer, pos: [2]f64, zoom: u32) -> Tile_Key {
	z := zoom
	if layer.min_zoom > 0 && z < u32(layer.min_zoom) {
		z = u32(layer.min_zoom)
	}
	if layer.max_zoom > 0 && z > u32(layer.max_zoom) {
		z = u32(layer.max_zoom)
	}

	tiles := u32(1) << z
	if tiles == 0 {
		return Tile_Key{}
	}

	lon := pos[1]
	for lon < -180.0 { lon += 360.0 }
	for lon >= 180.0 { lon -= 360.0 }

	max_lat := imagery_max_latitude()
	lat := clamp(pos[0], -max_lat, max_lat)

	nx := (lon + 180.0) / 360.0
	ny := (max_lat - lat) / (max_lat * 2.0)
	ny = clamp(ny, 0.0, 0.999999999)

	x := u32(nx * f64(tiles))
	y := u32(ny * f64(tiles))
	if x >= tiles { x = tiles - 1 }
	if y >= tiles { y = tiles - 1 }

	return Tile_Key{z = z, x = x, y = y}
}

imagery_tile_bounds_epsg4326 :: proc(key: Tile_Key) -> [4]f64 {
	tiles := u32(1) << key.z
	if tiles == 0 {
		return {-180.0, -85.0511, 180.0, 85.0511}
	}

	max_lat := imagery_max_latitude()
	span_lon := 360.0 / f64(tiles)
	span_lat := (max_lat * 2.0) / f64(tiles)

	west := -180.0 + f64(key.x) * span_lon
	east := west + span_lon
	north := max_lat - f64(key.y) * span_lat
	south := north - span_lat

	return [4]f64{west, south, east, north}
}

imagery_tile_cache_path :: proc(layer: ^ImageryLayer, key: Tile_Key) -> string {
	ext := layer.file_ext
	if ext == "" { ext = "jpg" }
	return fmt.tprintf("%s/%d/%d/%d.%s", layer.cache_root, key.z, key.x, key.y, ext)
}

imagery_tile_bundle_path :: proc(layer: ^ImageryLayer, key: Tile_Key) -> string {
	ext := layer.file_ext
	if ext == "" { ext = "jpg" }
	return fmt.tprintf("%s/%d/%d/%d.%s", layer.bundle_root, key.z, key.x, key.y, ext)
}

imagery_tile_remote_url :: proc(layer: ^ImageryLayer, key: Tile_Key) -> string {
	tpl := layer.url_template
	if layer.source == .Gjallarhorn_Proxy && layer.gjallarhorn_endpoint != "" {
		tpl = layer.gjallarhorn_endpoint
	}
	if tpl == "" { return "" }

	y := key.y
	if layer.tms_y {
		if key.z < 31 {
			tiles_per_axis := u32(1) << key.z
			y = (tiles_per_axis - 1) - key.y
		}
	}

	out, _ := strings.replace_all(tpl, "{z}", fmt.tprintf("%d", key.z), context.temp_allocator)
	out, _ = strings.replace_all(out, "{x}", fmt.tprintf("%d", key.x), context.temp_allocator)
	out, _ = strings.replace_all(out, "{y}", fmt.tprintf("%d", y), context.temp_allocator)

	if strings.contains(out, "{west}") || strings.contains(out, "{south}") || strings.contains(out, "{east}") || strings.contains(out, "{north}") {
		bounds := imagery_tile_bounds_epsg4326(key)
		out, _ = strings.replace_all(out, "{west}", fmt.tprintf("%.7f", bounds[0]), context.temp_allocator)
		out, _ = strings.replace_all(out, "{south}", fmt.tprintf("%.7f", bounds[1]), context.temp_allocator)
		out, _ = strings.replace_all(out, "{east}", fmt.tprintf("%.7f", bounds[2]), context.temp_allocator)
		out, _ = strings.replace_all(out, "{north}", fmt.tprintf("%.7f", bounds[3]), context.temp_allocator)
	}

	if strings.contains(out, "{size}") {
		sz := layer.tile_size
		if sz <= 0 { sz = 512 }
		out, _ = strings.replace_all(out, "{size}", fmt.tprintf("%d", sz), context.temp_allocator)
	}

	if strings.contains(out, "{ext}") {
		ext := layer.file_ext
		if ext == "" { ext = "jpg" }
		out, _ = strings.replace_all(out, "{ext}", ext, context.temp_allocator)
	}
	return out
}

_ensure_parent_dir :: proc(path: string) {
	dir, _ := os.split_path(path)
	if dir != "" {
		_ = os.make_directory_all(dir)
	}
}

// imagery_probe_tile_edge_first checks tile availability without loading bytes.
// Use this in render-time streaming loops to avoid disk-read stalls.
imagery_probe_tile_edge_first :: proc(layer: ^ImageryLayer, key: Tile_Key) -> Imagery_Tile_Result {
	res: Imagery_Tile_Result
	res.cache_path = imagery_tile_cache_path(layer, key)

	if res.cache_path != "" && os.exists(res.cache_path) {
		res.ok = true
		res.source = .Cache
		return res
	}

	if layer.bundle_root != "" {
		bundle_path := imagery_tile_bundle_path(layer, key)
		if os.exists(bundle_path) {
			res.ok = true
			res.source = .Bundle
			if res.cache_path != "" && bundle_path != res.cache_path {
				_ensure_parent_dir(res.cache_path)
				_ = os.copy_file(res.cache_path, bundle_path)
			}
			return res
		}
	}

	res.fetch_url = imagery_tile_remote_url(layer, key)
	if res.fetch_url != "" {
		res.source = .Remote
	}
	return res
}

// imagery_read_tile_edge_first tries cache first, then local bundle, then builds a remote URL.
imagery_read_tile_edge_first :: proc(layer: ^ImageryLayer, key: Tile_Key, allocator := context.allocator) -> Imagery_Tile_Result {
	res := imagery_probe_tile_edge_first(layer, key)
	if !res.ok {
		return res
	}

	if res.source == .Cache {
		bytes, err := os.read_entire_file_from_path(res.cache_path, allocator)
		if err == nil {
			res.bytes = bytes
			return res
		}
		res.ok = false
		res.source = .None
		res.fetch_url = imagery_tile_remote_url(layer, key)
		if res.fetch_url != "" { res.source = .Remote }
		return res
	}

	bundle_path := imagery_tile_bundle_path(layer, key)
	bytes, err := os.read_entire_file_from_path(bundle_path, allocator)
	if err == nil {
		res.bytes = bytes
		return res
	}
	res.ok = false
	res.source = .None
	res.fetch_url = imagery_tile_remote_url(layer, key)
	if res.fetch_url != "" { res.source = .Remote }
	return res
}
