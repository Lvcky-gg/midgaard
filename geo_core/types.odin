package geo_core

import "core:math"

PI :: 3.1415926535897932384626433832795

Vec3 :: struct {
	x, y, z: f64,
}

LatLon :: struct {
	lat, lon: f64,
}

deg_to_rad :: proc(degrees: f64) -> f64 {
	return degrees * PI / 180.0
}

// lat_lon_to_xyz maps geographic coordinates to Y-up world space.
// Negated z keeps the frame geographically right-handed: viewed from outside
// with north up, longitude increases to the east (screen right). The globe
// imagery UV mapping in globe.frag matches this convention.
lat_lon_to_xyz :: proc(position: LatLon, radius: f64) -> Vec3 {
	lat     := deg_to_rad(position.lat)
	lon     := deg_to_rad(position.lon)
	cos_lat := math.cos(lat)

	return Vec3{
		x =  radius * cos_lat * math.cos(lon),
		y =  radius * math.sin(lat),
		z = -radius * cos_lat * math.sin(lon),
	}
}
