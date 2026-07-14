package geo_app

import "base:runtime"
import "core:c"
import glfw "vendor:glfw"
import geo_core "../geo_core"

Window :: struct {
	handle:   glfw.WindowHandle,
	drag_x:   f64,
	drag_y:   f64,
	dragging: bool,
}

window_create :: proc(width, height: i32, title: cstring) -> Window {
	if !glfw.Init() { panic("GLFW init failed") }
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, false)
	h := glfw.CreateWindow(width, height, title, nil, nil)
	if h == nil { panic("GLFW window creation failed") }
	glfw.SetKeyCallback(h, _on_key)
	glfw.SetMouseButtonCallback(h, _on_mouse_btn)
	glfw.SetCursorPosCallback(h, _on_cursor)
	glfw.SetScrollCallback(h, _on_scroll)
	return Window{handle = h}
}

window_destroy :: proc(w: ^Window) {
	if w.handle != nil { glfw.DestroyWindow(w.handle) }
	glfw.Terminate()
}

window_should_close :: proc(w: ^Window) -> bool {
	return bool(glfw.WindowShouldClose(w.handle))
}

// ── GLFW callbacks ────────────────────────────────────────────────────────────

_on_key :: proc "c" (win: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(win, true)
	}
}

_on_mouse_btn :: proc "c" (win: glfw.WindowHandle, button, action, mods: c.int) {
	context = runtime.default_context()
	if g_app == nil { return }
	if button == glfw.MOUSE_BUTTON_LEFT {
		g_app.window.dragging = action == glfw.PRESS
	}
}

_on_cursor :: proc "c" (win: glfw.WindowHandle, x, y: f64) {
	context = runtime.default_context()
	if g_app == nil { return }
	w := &g_app.window
	if w.dragging {
		dx := f32(x - w.drag_x)
		dy := f32(y - w.drag_y)
		geo_core.camera_on_drag(&g_app.camera, dx, dy)
	}
	w.drag_x = x
	w.drag_y = y
}

_on_scroll :: proc "c" (win: glfw.WindowHandle, xoff, yoff: f64) {
	context = runtime.default_context()
	if g_app == nil { return }
	geo_core.camera_on_scroll(&g_app.camera, f32(yoff))
}
