package geo_core

import "core:math"

Camera :: struct {
	azimuth:   f32, // horizontal orbit angle (radians)
	elevation: f32, // vertical orbit angle  (radians)
	distance:  f32, // distance from origin
	aspect:    f32, // viewport width / height
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

camera_on_tilt :: proc(c: ^Camera, dy: f32) {
	c.elevation = clamp(c.elevation - dy * 0.008,
		f32(-math.PI/2.0) + 0.06,
		f32( math.PI/2.0) - 0.06)
}

camera_on_scroll :: proc(c: ^Camera, delta: f32) {
	step := max(f32(0.06), c.distance * 0.14)
	c.distance = clamp(c.distance - delta * step, 1.03, 18.0)
}

camera_mvp :: proc(c: Camera) -> [16]f32 {
	eye := [3]f32{
		c.distance * math.sin(c.azimuth)  * math.cos(c.elevation),
		c.distance * math.sin(c.elevation),
		c.distance * math.cos(c.azimuth)  * math.cos(c.elevation),
	}
	view := m4_look_at(eye, {0, 0, 0}, {0, 1, 0})
	near := clamp(c.distance * 0.01, 0.0005, 0.1)
	proj := m4_perspective(0.9, c.aspect, near, 100.0)
	return m4_mul(proj, view)
}

camera_focus_lat_lon :: proc(c: Camera) -> LatLon {
	eye_x := f64(c.distance * math.sin(c.azimuth) * math.cos(c.elevation))
	eye_y := f64(c.distance * math.sin(c.elevation))
	eye_z := f64(c.distance * math.cos(c.azimuth) * math.cos(c.elevation))

	fx := -eye_x
	fy := -eye_y
	fz := -eye_z
	len := math.sqrt(fx*fx + fy*fy + fz*fz)
	if len == 0 {
		return LatLon{}
	}

	fx /= len
	fy /= len
	fz /= len

	lat := math.asin(fy) * (180.0 / PI)
	lon := math.atan2(fz, fx) * (180.0 / PI)
	return LatLon{lat = lat, lon = lon}
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
