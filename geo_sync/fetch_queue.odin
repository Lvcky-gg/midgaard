package geo_sync

Fetch_Status :: enum {
	Queued,
	In_Flight,
	Done,
	Failed,
}

Imagery_Fetch_Task :: struct {
	layer_name: string,
	cache_path: string,
	url: string,
	status: Fetch_Status,
	last_error: string,
}

Edge_Fetch_Queue :: struct {
	tasks: [dynamic]Imagery_Fetch_Task,
}

edge_fetch_queue_destroy :: proc(q: ^Edge_Fetch_Queue) {
	delete(q.tasks)
}

edge_fetch_queue_add :: proc(q: ^Edge_Fetch_Queue, task: Imagery_Fetch_Task) {
	append(&q.tasks, task)
}

edge_fetch_queue_add_unique :: proc(q: ^Edge_Fetch_Queue, task: Imagery_Fetch_Task) -> bool {
	for i in 0..<len(q.tasks) {
		if q.tasks[i].cache_path != task.cache_path {
			continue
		}

		if q.tasks[i].status == .Failed {
			q.tasks[i].status = .Queued
			q.tasks[i].last_error = ""
			q.tasks[i].url = task.url
			q.tasks[i].layer_name = task.layer_name
			return true
		}

		return false
	}

	append(&q.tasks, task)
	return true
}

edge_fetch_queue_trim_finished :: proc(q: ^Edge_Fetch_Queue, keep_recent: int) {
	limit := keep_recent
	if limit < 0 { limit = 0 }
	if len(q.tasks) <= limit { return }

	trimmed := make([dynamic]Imagery_Fetch_Task, 0, len(q.tasks))
	for i in 0..<len(q.tasks) {
		if q.tasks[i].status == .Done {
			continue
		}
		append(&trimmed, q.tasks[i])
	}

	delete(q.tasks)
	q.tasks = trimmed
}

edge_fetch_queue_pop_next :: proc(q: ^Edge_Fetch_Queue) -> (Imagery_Fetch_Task, bool) {
	for i in 0..<len(q.tasks) {
		if q.tasks[i].status == .Queued {
			q.tasks[i].status = .In_Flight
			return q.tasks[i], true
		}
	}
	return {}, false
}

edge_fetch_queue_mark_done :: proc(q: ^Edge_Fetch_Queue, cache_path: string) {
	for i in 0..<len(q.tasks) {
		if q.tasks[i].cache_path == cache_path {
			q.tasks[i].status = .Done
			q.tasks[i].last_error = ""
			return
		}
	}
}

edge_fetch_queue_mark_failed :: proc(q: ^Edge_Fetch_Queue, cache_path, err: string) {
	for i in 0..<len(q.tasks) {
		if q.tasks[i].cache_path == cache_path {
			q.tasks[i].status = .Failed
			q.tasks[i].last_error = err
			return
		}
	}
}
