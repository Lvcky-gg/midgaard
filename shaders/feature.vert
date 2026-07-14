#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

layout(push_constant) uniform PC {
    mat4 mvp;
} pc;

layout(location = 0) out vec4 v_color;

out gl_PerVertex {
    vec4 gl_Position;
    float gl_PointSize;
};

void main() {
    gl_Position  = pc.mvp * vec4(in_position, 1.0);
    gl_PointSize = 14.0;
    v_color      = in_color;
}
