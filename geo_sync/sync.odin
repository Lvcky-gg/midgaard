package geo_sync

// Sync_Manifest lists what an edge node has and what it needs.
Sync_Manifest :: struct {
	node_id:   string,
	packages:  [dynamic]Sync_Package,
}

Sync_Package :: struct {
	dataset_id: int,
	version:    int,
	size_bytes: u64,
	status:     Sync_Status,
}

Sync_Status :: enum { Local, Pending, Downloading, Complete, Stale }

sync_manifest_destroy :: proc(m: ^Sync_Manifest) {
	delete(m.packages)
}

// TODO: implement delta bundle protocol.
// TODO: implement offline package export/import.
// TODO: integrate with geo_catalog for version tracking.
