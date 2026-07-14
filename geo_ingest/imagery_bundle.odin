package geo_ingest

import "core:os"
import geo_layers "../geo_layers"

// ingest_attach_imagery_bundle binds an offline bundle root to a layer.
ingest_attach_imagery_bundle :: proc(layer: ^geo_layers.ImageryLayer, bundle_root: string) {
	layer.bundle_root = bundle_root
	layer.edge_first = true
}

// ingest_prepare_imagery_cache ensures the cache root exists before runtime reads/writes.
ingest_prepare_imagery_cache :: proc(layer: ^geo_layers.ImageryLayer) -> bool {
	if layer.cache_root == "" { return false }
	if err := os.make_directory_all(layer.cache_root); err != nil {
		return false
	}
	return true
}
