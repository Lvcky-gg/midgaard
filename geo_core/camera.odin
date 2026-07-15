package geo_core

import "core:math"

Camera :: struct {
	azimuth:   f32, // horizontal orbit angle (radians)
	elevation: f32, // vertical orbit angle  (radians)
	distance:  f32, // distance from origin
	aspect:    f32, // viewport width / height
	pitch:     f32, // view pitch away from globe center (radians, 0 = look at center)
}

camera_create :: proc(width, height: u32) -> Camera {
	return Camera{
		azimuth   = 0.3,
		elevation = 0.4,
		distance  = 3.5,
		aspect    = f32(width) / f32(height),
	}
}

camera_on_drag :: proc(c: ^Camera, dx, dy: f32) {
	c.azimuth  += dx * 0.0053
	c.elevation = clamp(c.elevation - dy * 0.0053,
		f32(-math.PI/2.0) + 0.06,
		f32( math.PI/2.0) - 0.06)
}

// camera_on_pitch tilts the view direction away from the globe center:
// dragging down (dy > 0) pitches toward the horizon, like map tilt gestures.
camera_on_pitch :: proc(c: ^Camera, dy: f32) {
	c.pitch = clamp(c.pitch + dy * 0.004, 0.0, 1.35)
}

camera_on_scroll :: proc(c: ^Camera, delta: f32) {
	step := max(f32(0.06), c.distance * 0.14)
	c.distance = clamp(c.distance - delta * step, 1.03, 18.0)
}

camera_eye :: proc(c: Camera) -> [3]f32 {
	return {
		c.distance * math.sin(c.azimuth)  * math.cos(c.elevation),
		c.distance * math.sin(c.elevation),
		c.distance * math.cos(c.azimuth)  * math.cos(c.elevation),
	}
}

// camera_forward is the view direction: toward the globe center, pitched up
// by c.pitch around the camera's right axis.
camera_forward :: proc(c: Camera) -> [3]f32 {
	eye := camera_eye(c)
	f0  := v3_norm({-eye[0], -eye[1], -eye[2]})
	r   := v3_norm(v3_cross(f0, {0, 1, 0}))
	u   := v3_cross(r, f0)
	cp  := math.cos(c.pitch)
	sp  := math.sin(c.pitch)
	return v3_norm({
		f0[0]*cp + u[0]*sp,
		f0[1]*cp + u[1]*sp,
		f0[2]*cp + u[2]*sp,
	})
}

camera_mvp :: proc(c: Camera) -> [16]f32 {
	eye := camera_eye(c)
	fwd := camera_forward(c)
	target := [3]f32{eye[0] + fwd[0], eye[1] + fwd[1], eye[2] + fwd[2]}
	view := m4_look_at(eye, target, {0, 1, 0})
	near := clamp(c.distance * 0.01, 0.0005, 0.1)
	proj := m4_perspective(0.9, c.aspect, near, 100.0)
	return m4_mul(proj, view)
}

// camera_focus_lat_lon returns the geographic point the camera is looking at:
// the first intersection of the view ray with the unit sphere, falling back
// to the sub-camera point when the ray misses the globe (looking at sky).
camera_focus_lat_lon :: proc(c: Camera) -> LatLon {
	eye := camera_eye(c)
	fwd := camera_forward(c)

	ef   := v3_dot(eye, fwd)
	disc := ef*ef - (v3_dot(eye, eye) - 1.0)

	p: [3]f32
	if t := -ef - math.sqrt(max(disc, 0)); disc >= 0 && t > 0 {
		p = {eye[0] + t*fwd[0], eye[1] + t*fwd[1], eye[2] + t*fwd[2]}
	} else {
		p = v3_norm(eye)
	}

	// Inverse of lat_lon_to_xyz (z is negated there).
	lat := math.asin(f64(clamp(p[1], -1, 1))) * (180.0 / PI)
	lon := math.atan2(f64(-p[2]), f64(p[0])) * (180.0 / PI)
	return LatLon{lat = lat, lon = lon}
}

// camera_world_to_screen projects a world point to framebuffer pixels
// (origin top-left, y down — matches GLFW cursor coordinates).
// ok is false when the point is behind the camera.
camera_world_to_screen :: proc(c: Camera, world: [3]f32, width, height: f32) -> (sx, sy: f32, ok: bool) {
	clip := m4_mul_v4(camera_mvp(c), {world[0], world[1], world[2], 1})
	if clip[3] <= 0 { return 0, 0, false }
	return (clip[0]/clip[3]*0.5 + 0.5) * width,
	       (clip[1]/clip[3]*0.5 + 0.5) * height,
	       true
}

// ── mat4 helpers (column-major, Vulkan clip space) ───────────────────────────

m4_mul :: proc(a, b: [16]f32) -> [16]f32 {
	out: [16]f32
	for col in 0..<4 {
		for row in 0..<4 {
			for k in 0..<4 {
				out[col*4+row] += a[k*4+row] * b[col*4+k]
			}
		}
	}
	return out
}

m4_mul_v4 :: proc(m: [16]f32, v: [4]f32) -> [4]f32 {
	out: [4]f32
	for row in 0..<4 {
		out[row] = m[0*4+row]*v[0] + m[1*4+row]*v[1] + m[2*4+row]*v[2] + m[3*4+row]*v[3]
	}
	return out
}

m4_look_at :: proc(eye, center, up: [3]f32) -> [16]f32 {
	f := v3_norm(v3_sub(center, eye))
	r := v3_norm(v3_cross(f, up))
	u := v3_cross(r, f)
	return [16]f32{
		 r[0],  u[0], -f[0], 0,
		 r[1],  u[1], -f[1], 0,
		 r[2],  u[2], -f[2], 0,
		-v3_dot(r, eye), -v3_dot(u, eye), v3_dot(f, eye), 1,
	}
}

m4_perspective :: proc(fovy, aspect, near, far: f32) -> [16]f32 {
	t := 1.0 / math.tan_f32(fovy * 0.5)
	d := near - far
	return [16]f32{
		t / aspect, 0, 0,  0,
		0, -t, 0, 0,          // flip Y for Vulkan
		0, 0, far / d, -1,
		0, 0, (near * far) / d, 0,
	}
}

// ── vec3 helpers ─────────────────────────────────────────────────────────────

v3_sub :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[0]-b[0], a[1]-b[1], a[2]-b[2]}
}
v3_dot :: proc(a, b: [3]f32) -> f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
}
v3_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]}
}
v3_norm :: proc(v: [3]f32) -> [3]f32 {
	l := math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
	if l == 0 { return v }
	return {v[0]/l, v[1]/l, v[2]/l}
}
