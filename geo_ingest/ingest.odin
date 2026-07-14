package geo_ingest

// Ingest_Job describes a single import task: read a source, normalize it,
// build pyramids or tile indexes, and publish into the platform catalog.
Ingest_Status :: enum { Pending, Running, Done, Failed }

Ingest_Job :: struct {
	id:          int,
	source_path: string,
	layer_name:  string,
	status:      Ingest_Status,
	progress:    f32, // 0..1
}

// TODO: implement GeoJSON, Shapefile, GeoPackage readers.
// TODO: implement raster pyramid builder.
// TODO: implement tile indexer.
