package geo_catalog

// Dataset describes a published layer's metadata entry in the catalog.
Dataset :: struct {
	id:          int,
	name:        string,
	kind:        string, // "imagery" | "elevation" | "feature" | ...
	source_url:  string,
	extent:      [4]f64, // west, south, east, north (WGS84 degrees)
	min_zoom:    int,
	max_zoom:    int,
	description: string,
}

// Catalog is the local in-memory view of available datasets.
Catalog :: struct {
	datasets: [dynamic]Dataset,
}

catalog_destroy :: proc(c: ^Catalog) {
	delete(c.datasets)
}

catalog_add :: proc(c: ^Catalog, d: Dataset) {
	append(&c.datasets, d)
}

// TODO: persist/load catalog from JSON or SQLite.
// TODO: sync catalog with platform backend.
