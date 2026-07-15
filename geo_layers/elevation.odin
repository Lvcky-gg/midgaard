package geo_layers

import "core:fmt"
import "core:math"
import "core:strings"

// Elevation_Grid is a decoded square Web-Mercator mosaic of terrain heights
// (row-major, north at row 0, meters above sea level).
Elevation_Grid :: struct {
	size_px: int,
	heights: []f32,
}

elevation_grid_destroy :: proc(g: ^Elevation_Grid) {
	delete(g.heights)
	g.heights = nil
	g.size_px = 0
}

elevation_tile_cache_path :: proc(layer: ^ElevationLayer, z, x, y: u32) -> string {
	return fmt.tprintf("%s/%d/%d/%d.png", layer.cache_root, z, x, y)
}

elevation_tile_url :: proc(layer: ^ElevationLayer, z, x, y: u32) -> string {
	if layer.url_template == "" { return "" }
	out, _ := strings.replace_all(layer.url_template, "{z}", fmt.tprintf("%d", z), context.temp_allocator)
	out, _ = strings.replace_all(out, "{x}", fmt.tprintf("%d", x), context.temp_allocator)
	out, _ = strings.replace_all(out, "{y}", fmt.tprintf("%d", y), context.temp_allocator)
	return out
}

// elevation_decode_terrarium converts one terrarium RGB pixel to meters.
elevation_decode_terrarium :: proc(r, g, b: u8) -> f32 {
	return f32(r)*256.0 + f32(g) + f32(b)/256.0 - 32768.0
}

// elevation_sample bilinearly samples the grid at a geographic position.
// Latitudes beyond the Web-Mercator limit clamp to the edge rows; longitude
// wraps. Returns 0 when the grid is empty.
elevation_sample :: proc(g: ^Elevation_Grid, lat, lon: f64) -> f64 {
	if g.size_px <= 0 || len(g.heights) == 0 { return 0 }
	size := g.size_px

	la := clamp(lat, -imagery_max_latitude(), imagery_max_latitude())
	lo := lon
	for lo < -180.0 { lo += 360.0 }
	for lo >= 180.0 { lo -= 360.0 }

	fx := (lo + 180.0) / 360.0 * f64(size)
	lat_rad := la * math.PI / 180.0
	merc := math.ln(math.tan(lat_rad) + 1.0/math.cos(lat_rad))
	fy := (1.0 - merc/math.PI) * 0.5 * f64(size)
	fy = clamp(fy, 0, f64(size)-1)

	x0 := int(fx)
	y0 := int(fy)
	if x0 >= size { x0 = size - 1 }
	if y0 >= size - 1 { y0 = size - 2 }
	x1 := (x0 + 1) % size // longitude wraps
	y1 := y0 + 1

	tx := f32(fx - f64(x0))
	ty := f32(fy - f64(y0))

	h00 := g.heights[y0*size + x0]
	h10 := g.heights[y0*size + x1]
	h01 := g.heights[y1*size + x0]
	h11 := g.heights[y1*size + x1]

	top := h00 + (h10 - h00)*tx
	bot := h01 + (h11 - h01)*tx
	return f64(top + (bot - top)*ty)
}
