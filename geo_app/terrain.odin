package geo_app

import "core:bytes"
import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:os"
import geo_core   "../geo_core"
import geo_layers "../geo_layers"
import geo_sync   "../geo_sync"

EARTH_RADIUS_M :: 6_371_000.0
TERRAIN_TILE_PX :: 256

// _terrain_load_grid hydrates the terrarium mosaic edge-first: cached tiles
// are decoded directly, missing ones are fetched then decoded. Tiles that
// stay unavailable leave their region at sea level.
_terrain_load_grid :: proc(layer: ^geo_layers.ElevationLayer) -> (geo_layers.Elevation_Grid, bool) {
	n := int(u32(1) << layer.tile_zoom)
	size := n * TERRAIN_TILE_PX
	grid := geo_layers.Elevation_Grid{
		size_px = size,
		heights = make([]f32, size*size),
	}

	loaded := 0
	for ty in 0..<n {
		for tx in 0..<n {
			path := geo_layers.elevation_tile_cache_path(layer, layer.tile_zoom, u32(tx), u32(ty))
			if !os.exists(path) {
				url := geo_layers.elevation_tile_url(layer, layer.tile_zoom, u32(tx), u32(ty))
				if url == "" { continue }
				if ok, err := geo_sync.edge_fetch_url_to_file(url, path, 20); !ok {
					fmt.printf("Elevation tile %d/%d/%d fetch failed: %s\n", layer.tile_zoom, tx, ty, err)
					continue
				}
			}
			if _terrain_decode_tile_into(&grid, path, tx, ty) {
				loaded += 1
			}
		}
	}

	if loaded == 0 {
		geo_layers.elevation_grid_destroy(&grid)
		return {}, false
	}
	fmt.printf("Elevation grid — tiles:%d/%d  size:%dpx\n", loaded, n*n, size)
	return grid, true
}

_terrain_decode_tile_into :: proc(grid: ^geo_layers.Elevation_Grid, path: string, tx, ty: int) -> bool {
	img, err := image.load_from_file(path, allocator = context.allocator)
	if err != nil || img == nil { return false }
	defer image.destroy(img)

	if img.width != TERRAIN_TILE_PX || img.height != TERRAIN_TILE_PX || img.depth != 8 || img.channels < 3 {
		return false
	}

	src := bytes.buffer_to_bytes(&img.pixels)
	ch := img.channels
	for py in 0..<TERRAIN_TILE_PX {
		row := (ty*TERRAIN_TILE_PX + py) * grid.size_px + tx*TERRAIN_TILE_PX
		for px in 0..<TERRAIN_TILE_PX {
			s := (py*TERRAIN_TILE_PX + px) * ch
			grid.heights[row+px] = geo_layers.elevation_decode_terrarium(src[s+0], src[s+1], src[s+2])
		}
	}
	return true
}

// _apply_terrain displaces the globe mesh by sampled elevation. Bathymetry is
// clamped to sea level so the imagery's ocean surface stays spherical.
_apply_terrain :: proc(app: ^App, mesh: ^geo_core.Globe_Mesh, stacks, slices: int) {
	if len(app.scene.elevation_layers) == 0 { return }
	layer := &app.scene.elevation_layers[0]
	if !layer.base.visible { return }

	grid, ok := _terrain_load_grid(layer)
	if !ok {
		fmt.println("Elevation: no data available, rendering smooth globe")
		return
	}
	defer geo_layers.elevation_grid_destroy(&grid)

	exagg := layer.exaggeration
	if exagg <= 0 { exagg = 1 }

	stride := slices + 1
	radii := make([]f32, len(mesh.vertices))
	defer delete(radii)

	for stack in 0..=stacks {
		lat := 90.0 - f64(stack)/f64(stacks)*180.0
		for slice in 0..=slices {
			// Mesh angle theta = u*360; world longitude is -theta (see
			// geo_core.lat_lon_to_xyz).
			lon := -f64(slice) / f64(slices) * 360.0
			if lon < -180.0 { lon += 360.0 }

			h := geo_layers.elevation_sample(&grid, lat, lon)
			if h < 0 { h = 0 }
			radii[stack*stride+slice] = f32(1.0 + h/EARTH_RADIUS_M*exagg)
		}
	}

	geo_core.displace_globe_mesh(mesh, stacks, slices, radii)
	fmt.printf("Terrain applied — %s, exaggeration %.0fx\n", layer.base.name, exagg)
}
