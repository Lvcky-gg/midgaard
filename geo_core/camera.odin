package geo_core

import "core:math"

// Camera is an ArcGIS-SceneView-style globe camera: it orbits a target point on
// the surface, always looking at it, with a heading and tilt. Right-drag arcs
// the camera around that target (the globe stays put and level); left-drag pans
// the target; scroll changes range. The globe is the unit sphere.
Camera :: struct {
	target:   LatLon, // ground point at the center of the view; the orbit pivot
	distance: f32,    // eye-to-target range
	heading:  f32,    // compass facing (radians): 0 = north, +clockwise (east)
	tilt:     f32,    // view tilt from nadir (radians): 0 = straight down
	aspect:   f32,    // viewport width / height
}

// TILT_MAX stops the tilt just short of the horizon so the eye never dips below
// the local tangent plane (which would put the camera underground).
TILT_MAX :: f32(1.40) // ~80 degrees

FOVY :: f32(0.9)

camera_create :: proc(width, height: u32) -> Camera {
	// Plain global view: straight down at lat/lon 0, whole globe in frame.
	return Camera{
		target   = LatLon{lat = 0, lon = 0},
		distance = 2.5,
		heading  = 0,
		tilt     = 0,
		aspect   = f32(width) / f32(height),
	}
}

// _frame returns the east/north/up orthonormal tangent basis at a surface point.
// {east, north, up} is right-handed: east x north = up.
_frame :: proc(pos: LatLon) -> (east, north, up: [3]f32) {
	lat := f32(deg_to_rad(pos.lat))
	lon := f32(deg_to_rad(pos.lon))
	cl := math.cos(lat); sl := math.sin(lat)
	co := math.cos(lon); so := math.sin(lon)
	up    = { cl*co, sl, -cl*so }
	north = { -sl*co, cl, sl*so }
	east  = { -so, 0, -co }
	return
}

// camera_axes returns the camera's world-space right/up/forward basis. Forward
// aims from the eye at the target; the basis is well-defined at every tilt
// including nadir (0) and the horizon, so there is no gimbal singularity.
camera_axes :: proc(c: Camera) -> (right, up, fwd: [3]f32) {
	east, north, radial := _frame(c.target)
	ch := math.cos(c.heading); sh := math.sin(c.heading)
	ct := math.cos(c.tilt);    st := math.sin(c.tilt)
	horiz := [3]f32{ ch*north[0] + sh*east[0], ch*north[1] + sh*east[1], ch*north[2] + sh*east[2] }
	fwd = v3_norm({
		st*horiz[0] - ct*radial[0],
		st*horiz[1] - ct*radial[1],
		st*horiz[2] - ct*radial[2],
	})
	right = v3_norm({
		ch*east[0] - sh*north[0],
		ch*east[1] - sh*north[1],
		ch*east[2] - sh*north[2],
	})
	up = v3_cross(right, fwd)
	return
}

// camera_eye is the eye position: the target lifted along local up and pushed
// back along the heading by the tilt, at range c.distance from the target.
camera_eye :: proc(c: Camera) -> [3]f32 {
	east, north, radial := _frame(c.target)
	ch := math.cos(c.heading); sh := math.sin(c.heading)
	ct := math.cos(c.tilt);    st := math.sin(c.tilt)
	horiz := [3]f32{ ch*north[0] + sh*east[0], ch*north[1] + sh*east[1], ch*north[2] + sh*east[2] }
	// target (= radial, on the unit sphere) + distance*(cos t up - sin t horiz)
	return {
		radial[0] + c.distance*(ct*radial[0] - st*horiz[0]),
		radial[1] + c.distance*(ct*radial[1] - st*horiz[1]),
		radial[2] + c.distance*(ct*radial[2] - st*horiz[2]),
	}
}

// camera_center_distance is the eye's distance from the globe center, used to
// pick imagery level-of-detail (altitude), distinct from the eye-to-target range.
camera_center_distance :: proc(c: Camera) -> f32 {
	return v3_len(camera_eye(c))
}

camera_forward :: proc(c: Camera) -> [3]f32 {
	_, _, fwd := camera_axes(c)
	return fwd
}

// camera_on_drag pans the view across the surface (left-drag): the ground point
// under the cursor follows the drag, so the target translates over the globe
// instead of the globe rotating in place. Pan speed scales with range.
camera_on_drag :: proc(c: ^Camera, dx, dy: f32) {
	rate := 0.0012 * c.distance
	ch := math.cos(c.heading); sh := math.sin(c.heading)
	// Ground move opposite the cursor drag, expressed in the east/north tangent.
	east_move  := rate * (-dx*ch + dy*sh)
	north_move := rate * ( dx*sh + dy*ch)

	lat := c.target.lat + f64(north_move) * (180.0 / PI)
	lat = clamp(lat, -89.0, 89.0)
	cos_lat := math.cos(deg_to_rad(lat))
	if cos_lat < 1e-4 { cos_lat = 1e-4 }
	lon := c.target.lon + f64(east_move) / cos_lat * (180.0 / PI)
	for lon >  180.0 { lon -= 360.0 }
	for lon < -180.0 { lon += 360.0 }
	c.target = LatLon{lat = lat, lon = lon}
}

camera_on_scroll :: proc(c: ^Camera, delta: f32) {
	step := max(f32(0.06), c.distance * 0.14)
	c.distance = clamp(c.distance - delta * step, 0.05, 17.0)
}

// camera_orbit tilts and rotates the view around the target (ArcGIS right-drag):
// horizontal drag turns the heading, vertical drag tilts. The camera arcs around
// the target, which stays centered and level, so the globe never slides or
// spins under the cursor. Drag up leans toward the horizon.
camera_orbit :: proc(c: ^Camera, dx, dy: f32) {
	K_HEADING :: f32(0.0053)
	K_TILT    :: f32(0.0053)
	c.heading += dx * K_HEADING
	for c.heading >  f32(PI) { c.heading -= f32(2*PI) }
	for c.heading < f32(-PI) { c.heading += f32(2*PI) }
	c.tilt = clamp(c.tilt - dy*K_TILT, 0, TILT_MAX)
}

// camera_ground_ray_hit intersects the view ray through pixel (sx, sy) with the
// unit sphere and returns the world hit point. ok is false when the ray misses
// the globe (cursor over empty sky).
camera_ground_ray_hit :: proc(c: Camera, sx, sy, width, height: f32) -> (hit: [3]f32, ok: bool) {
	right, up, fwd := camera_axes(c)
	eye := camera_eye(c)

	t := math.tan(FOVY * 0.5)
	ndc_x := sx / width * 2 - 1
	ndc_y := 1 - sy / height * 2 // pixel y is top-down; ndc y is up
	dir := v3_norm({
		fwd[0] + ndc_x*c.aspect*t*right[0] + ndc_y*t*up[0],
		fwd[1] + ndc_x*c.aspect*t*right[1] + ndc_y*t*up[1],
		fwd[2] + ndc_x*c.aspect*t*right[2] + ndc_y*t*up[2],
	})

	ed := v3_dot(eye, dir)
	disc := ed*ed - (v3_dot(eye, eye) - 1)
	if disc < 0 { return {}, false }
	s := -ed - math.sqrt(disc)
	if s <= 0 { return {}, false }
	return {eye[0] + s*dir[0], eye[1] + s*dir[1], eye[2] + s*dir[2]}, true
}

camera_mvp :: proc(c: Camera) -> [16]f32 {
	right, up, fwd := camera_axes(c)
	eye := camera_eye(c)
	view := m4_view(eye, right, up, fwd)
	near := clamp(camera_center_distance(c) * 0.01, 0.0005, 0.1)
	proj := m4_perspective(FOVY, c.aspect, near, 100.0)
	return m4_mul(proj, view)
}

// camera_focus_lat_lon returns the geographic point at the center of the view —
// which in this orbit model is exactly the target.
camera_focus_lat_lon :: proc(c: Camera) -> LatLon {
	return c.target
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

// m4_view builds a view matrix from an orthonormal camera basis and eye. Rows
// mirror a look-at matrix, but take the basis directly so the caller controls roll.
m4_view :: proc(eye, right, up, fwd: [3]f32) -> [16]f32 {
	r, u, f := right, up, fwd
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

v3_add :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[0]+b[0], a[1]+b[1], a[2]+b[2]}
}
v3_sub :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[0]-b[0], a[1]-b[1], a[2]-b[2]}
}
v3_dot :: proc(a, b: [3]f32) -> f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
}
v3_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]}
}
v3_len :: proc(v: [3]f32) -> f32 {
	return math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
}
v3_norm :: proc(v: [3]f32) -> [3]f32 {
	l := math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
	if l == 0 { return v }
	return {v[0]/l, v[1]/l, v[2]/l}
}
