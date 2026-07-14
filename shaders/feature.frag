#version 450

layout(location = 0) in vec4 v_color;
layout(location = 0) out vec4 out_color;

void main() {
    vec2  coord = gl_PointCoord * 2.0 - 1.0;
    float d     = length(coord);
    if (d > 1.0) discard;

    float glow  = 1.0 - smoothstep(0.0, 0.8, d);
    float rim   = 1.0 - smoothstep(0.6, 1.0, d);
    float alpha = max(glow * 0.5, rim);

    vec3  col   = mix(v_color.rgb * 2.5, v_color.rgb, smoothstep(0.2, 0.7, d));
    out_color   = vec4(col, alpha * v_color.a);
}
