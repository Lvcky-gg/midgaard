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
	drag_button: c.int,
	press_x:  f64,
	press_y:  f64,
}

// CLICK_SLOP_PX separates a pick click from an orbit drag: a left button
// release counts as a click only if the cursor stayed within this distance.
CLICK_SLOP_PX :: 4.0

// window_create opens a non-resizable window. Pass width/height <= 0 to size
// it to the primary monitor (maximized).
window_create :: proc(width, height: i32, title: cstring) -> Window {
	if !glfw.Init() { panic("GLFW init failed") }
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, false)

	w, hgt := width, height
	if w <= 0 || hgt <= 0 {
		// Size to the largest monitor: the primary can be a small or portrait
		// display in multi-monitor setups.
		for monitor in glfw.GetMonitors() {
			mode := glfw.GetVideoMode(monitor)
			if mode == nil { continue }
			if int(mode.width) * int(mode.height) > int(w) * int(hgt) {
				w = mode.width
				hgt = mode.height
			}
		}
		if w <= 0 || hgt <= 0 {
			w, hgt = 1920, 1080
		}
		glfw.WindowHint(glfw.MAXIMIZED, true)
	}

	h := glfw.CreateWindow(w, hgt, title, nil, nil)
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
	w := &g_app.window
	if action == glfw.PRESS && (button == glfw.MOUSE_BUTTON_LEFT || button == glfw.MOUSE_BUTTON_RIGHT) {
		w.dragging = true
		w.drag_button = button
		w.press_x = w.drag_x
		w.press_y = w.drag_y
		g_app.camera_interaction_cooldown = 10
		return
	}
	if action == glfw.RELEASE && button == w.drag_button {
		w.dragging = false
		w.drag_button = 0
		if button == glfw.MOUSE_BUTTON_LEFT &&
			abs(w.drag_x - w.press_x) < CLICK_SLOP_PX &&
			abs(w.drag_y - w.press_y) < CLICK_SLOP_PX {
			app_handle_click(g_app, w.drag_x, w.drag_y)
		}
	}
}

_on_cursor :: proc "c" (win: glfw.WindowHandle, x, y: f64) {
	context = runtime.default_context()
	if g_app == nil { return }
	w := &g_app.window
	if w.dragging {
		dx := f32(x - w.drag_x)
		dy := f32(y - w.drag_y)
		g_app.camera_interaction_cooldown = 10
		if w.drag_button == glfw.MOUSE_BUTTON_RIGHT {
			geo_core.camera_on_tilt(&g_app.camera, dy)
		} else {
			geo_core.camera_on_drag(&g_app.camera, dx, dy)
		}
	}
	w.drag_x = x
	w.drag_y = y
}

_on_scroll :: proc "c" (win: glfw.WindowHandle, xoff, yoff: f64) {
	context = runtime.default_context()
	if g_app == nil { return }
	geo_core.camera_on_scroll(&g_app.camera, f32(yoff))
	g_app.imagery_scroll_cooldown = 24
}
