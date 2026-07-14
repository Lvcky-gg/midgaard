#version 450

layout(location = 0) out vec4 out_color;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 uv = gl_FragCoord.xy * 0.001;

    vec2 cell = floor(gl_FragCoord.xy / 4.0);
    vec2 f = fract(gl_FragCoord.xy / 4.0) - 0.5;

    float rnd = hash12(cell);
    float star_mask = step(0.9978, rnd);
    float star_core = smoothstep(0.35, 0.0, length(f));
    float star = star_mask * star_core;

    vec3 sky = vec3(0.0);

    // Subtle cool glow/nebula for depth and contrast.
    float band = exp(-pow((uv.y - 0.32) * 2.6, 2.0));
    sky += vec3(0.010, 0.018, 0.040) * band;

    // Slight center glow for the "wow" factor without washing out stars.
    vec2 c = uv - vec2(0.64, 0.40);
    float halo = exp(-dot(c, c) * 0.85);
    sky += vec3(0.012, 0.020, 0.045) * halo;

    vec3 stars = vec3(1.0, 0.97, 0.90) * star + vec3(0.35, 0.55, 1.0) * star * 0.55;
    out_color = vec4(sky + stars, 1.0);
}
