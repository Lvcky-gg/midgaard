package geo_core

import "core:math"
import "core:testing"

VIEW_W :: f32(1920)
VIEW_H :: f32(1080)

// _globe_on_screen reports whether any part of the globe surface projects into
// the viewport, sampling the sphere on a lat/lon grid.
_globe_on_screen :: proc(c: Camera) -> bool {
	for lat := -90.0; lat <= 90.0; lat += 5.0 {
		for lon := -180.0; lon < 180.0; lon += 5.0 {
			p := lat_lon_to_xyz(LatLon{lat = lat, lon = lon}, 1.0)
			sx, sy, ok := camera_world_to_screen(c, {f32(p.x), f32(p.y), f32(p.z)}, VIEW_W, VIEW_H)
			if ok && sx >= 0 && sx <= VIEW_W && sy >= 0 && sy <= VIEW_H {
				return true
			}
		}
	}
	return false
}

// Right-drag pitch must never tilt the globe off screen, at any zoom level.
// The pitch that loses it depends on distance (the globe shrinks as the camera
// pulls back), so a constant clamp cannot hold this.
@(test)
test_pitch_drag_keeps_globe_on_screen :: proc(t: ^testing.T) {
	for d in ([]f32{1.03, 1.15, 1.5, 2.2, 3.5, 6.0, 10.0, 18.0}) {
		c := camera_create(u32(VIEW_W), u32(VIEW_H))
		c.distance = d

		// A long right-drag downward: 400 events of 8px, far past any clamp.
		for _ in 0..<400 {
			camera_on_pitch(&c, 8)
			testing.expectf(t, _globe_on_screen(c),
				"globe left the screen at distance %v, pitch %v", d, c.pitch)
		}
		// And dragging back up returns to looking at the globe center.
		for _ in 0..<400 {
			camera_on_pitch(&c, -8)
		}
		testing.expectf(t, c.pitch == 0, "pitch did not return to 0 at distance %v", d)
	}
}

// Tilt that is legal up close must be re-clamped when the camera pulls back,
// or zooming out after a full tilt drops the globe off screen.
@(test)
test_zoom_out_after_tilt_keeps_globe_on_screen :: proc(t: ^testing.T) {
	c := camera_create(u32(VIEW_W), u32(VIEW_H))
	c.distance = 1.03
	for _ in 0..<400 { camera_on_pitch(&c, 8) }
	testing.expect(t, c.pitch > 1.0, "expected a large tilt at closest zoom")

	for _ in 0..<200 {
		camera_on_scroll(&c, -1) // wheel down = pull back
		testing.expectf(t, _globe_on_screen(c),
			"globe left the screen after zooming out to %v at pitch %v", c.distance, c.pitch)
	}
	testing.expect(t, c.distance == 18.0, "expected to reach max distance")
}

// Right-drag pitch sweeps the view direction through world up when the camera
// orbits below the equator (singularity at pitch = 90deg + elevation). The view
// basis must stay orthonormal and must not flip its right axis across it.
@(test)
test_pitch_basis_stays_stable_through_world_up :: proc(t: ^testing.T) {
	c := camera_create(1920, 1080)
	c.azimuth   = 0.349
	c.elevation = -0.349 // 90deg + elevation = 70deg = 1.222 rad of pitch
	c.distance  = 1.15

	prev_right: [3]f32
	for step in 0..=135 {
		c.pitch = f32(step) * 0.01
		fwd, up := camera_basis(c)

		testing.expectf(t, abs(v3_dot(fwd, fwd) - 1) < 1e-4, "forward not unit at pitch %v", c.pitch)
		testing.expectf(t, abs(v3_dot(up, up) - 1) < 1e-4, "up not unit at pitch %v", c.pitch)
		testing.expectf(t, abs(v3_dot(fwd, up)) < 1e-4, "basis not orthogonal at pitch %v", c.pitch)

		right := v3_norm(v3_cross(fwd, up))
		if step > 0 {
			testing.expectf(t, v3_dot(right, prev_right) > 0.99,
				"right axis flipped at pitch %v (dot %v)", c.pitch, v3_dot(right, prev_right))
		}
		prev_right = right
	}
}

// Pitch rotates the view off the globe center by exactly c.pitch radians.
@(test)
test_pitch_angle_matches_forward :: proc(t: ^testing.T) {
	c := camera_create(1920, 1080)
	c.elevation = 0.4

	eye := camera_eye(c)
	f0  := v3_norm({-eye[0], -eye[1], -eye[2]})
	for p in ([]f32{0, 0.3, 0.9, 1.35}) {
		c.pitch = p
		fwd := camera_forward(c)
		ang := math.acos(clamp(v3_dot(fwd, f0), -1, 1))
		testing.expectf(t, abs(ang - p) < 1e-3, "pitch %v produced %v rad off center", p, ang)
	}
}
