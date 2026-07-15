#version 450

layout(location = 0) in vec3  in_position;
layout(location = 1) in float in_t;
layout(location = 2) in vec4  in_color;

layout(push_constant) uniform PC {
    mat4  mvp;
    float time_sec;
    int   selected_index;
    vec2  viewport;
    vec4  eye;
} pc;

layout(location = 0) out vec4  v_color;
layout(location = 1) out float v_t;

void main() {
    gl_Position = pc.mvp * vec4(in_position, 1.0);
    v_color = in_color;
    v_t     = in_t;
}
