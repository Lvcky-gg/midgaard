package geo_sync

import "core:fmt"
import "core:os"
import "core:strings"

Fetch_Batch_Result :: struct {
	processed: int,
	succeeded: int,
	failed: int,
}

// edge_fetch_queue_run_batch drains up to max_tasks queued remote imagery pulls.
// Fetching uses curl so Midgaard can pull from any endpoint (including Gjallarhorn)
// without hardwiring an HTTP client implementation into the render runtime.
edge_fetch_queue_run_batch :: proc(q: ^Edge_Fetch_Queue, max_tasks, timeout_seconds: int) -> Fetch_Batch_Result {
	res: Fetch_Batch_Result
	if max_tasks <= 0 { return res }

	for i := 0; i < max_tasks; i += 1 {
		task, ok := edge_fetch_queue_pop_next(q)
		if !ok { break }

		res.processed += 1
		success, err := _fetch_to_cache(task.url, task.cache_path, timeout_seconds)
		if success {
			edge_fetch_queue_mark_done(q, task.cache_path)
			res.succeeded += 1
		} else {
			edge_fetch_queue_mark_failed(q, task.cache_path, err)
			res.failed += 1
		}
	}

	return res
}

// edge_fetch_url_to_file fetches a single URL to a cache file and returns success + error string.
edge_fetch_url_to_file :: proc(url, cache_path: string, timeout_seconds: int) -> (bool, string) {
	return _fetch_to_cache(url, cache_path, timeout_seconds)
}

_fetch_to_cache :: proc(url, cache_path: string, timeout_seconds: int) -> (bool, string) {
	_ensure_parent_dir(cache_path)

	tout := fmt.tprintf("%d", timeout_seconds)
	cmd := [10]string{"curl", "-L", "--fail", "--silent", "--show-error", "--max-time", tout, "--output", cache_path, url}
	desc := os.Process_Desc{command = cmd[:]}
	state, stdout, stderr, err := os.process_exec(desc, context.allocator)
	delete(stdout)
	defer delete(stderr)

	if err != nil {
		return false, fmt.tprintf("fetch launch error: %v", err)
	}
	if len(stderr) > 0 {
		msg := strings.trim_space(string(stderr))
		if msg != "" {
			return false, msg
		}
	}
	if !state.exited {
		return false, "fetch timed out"
	}
	if !state.success || state.exit_code != 0 {
		return false, fmt.tprintf("fetch exit code %d", state.exit_code)
	}
	if !os.exists(cache_path) {
		return false, "fetch finished but cache file was not created"
	}
	return true, ""
}

_ensure_parent_dir :: proc(path: string) {
	dir, _ := os.split_path(path)
	if dir != "" {
		_ = os.make_directory_all(dir)
	}
}
