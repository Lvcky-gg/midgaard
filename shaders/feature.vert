#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

layout(push_constant) uniform PC {
    mat4  mvp;
    float time_sec;
    int   selected_index;
    vec2  viewport;
    vec4  eye;
} pc;

layout(location = 0) out vec4 v_color;

out gl_PerVertex {
    vec4 gl_Position;
    float gl_PointSize;
};

void main() {
    gl_Position = pc.mvp * vec4(in_position, 1.0);

    bool  selected = gl_VertexIndex == pc.selected_index;
    float pulse    = 0.5 + 0.5 * sin(pc.time_sec * 4.0);

    gl_PointSize = selected ? 22.0 + 6.0 * pulse : 14.0;
    v_color      = selected ? mix(in_color, vec4(1.0), 0.30 + 0.25 * pulse) : in_color;
}
