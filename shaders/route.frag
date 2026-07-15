#version 450

layout(location = 0) in vec4  v_color;
layout(location = 1) in float v_t;

layout(push_constant) uniform PC {
    mat4  mvp;
    float time_sec;
    int   selected_index;
    vec2  viewport;
    vec4  eye;
} pc;

layout(location = 0) out vec4 out_color;

void main() {
    // Pulses of brightness travel start -> finish along the arc.
    float flow = 0.5 + 0.5 * sin(v_t * 28.0 - pc.time_sec * 3.0);
    vec3  col  = v_color.rgb * (0.75 + 0.75 * flow);
    out_color  = vec4(col, v_color.a * (0.55 + 0.45 * flow));
}
