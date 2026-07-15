#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec3 v_normal;

layout(set = 0, binding = 0) uniform sampler2D u_imagery;

layout(location = 0) out vec4 out_color;

void main() {
    vec3 n = normalize(v_normal);
    vec3 light_dir = normalize(vec3(-0.65, 0.5, 0.35));
    float shade = 0.35 + 0.65 * max(dot(n, light_dir), 0.0);

    // The loaded world image is exported in EPSG:4326 (equirectangular).
    // Mesh angle theta = u * 360deg; world longitude is -theta (see
    // geo_core.lat_lon_to_xyz), and the image's left edge is -180deg, so
    // u_tex = (lon + 180) / 360 = 0.5 - u. This keeps imagery, features,
    // and tile prefetch on the same longitudes.
    //
    // Vertically the export only covers +-85.0511deg (Web Mercator limit);
    // map that band onto the sphere and clamp so the polar caps stretch the
    // edge rows instead of sampling outside the data. The clamp is inset a
    // couple of texels because the service's aspect-fit rounding leaves the
    // outermost row black.
    float edge    = 0.0015;
    float lat_deg = v_uv.y * 180.0 - 90.0;
    float tex_v   = clamp((85.0511 - lat_deg) / 170.1022, edge, 1.0 - edge);
    vec2  tex_uv  = vec2(fract(0.5 - v_uv.x), tex_v);

    vec3 color = texture(u_imagery, tex_uv).rgb;

    color *= shade;
    out_color = vec4(color, 1.0);
}
