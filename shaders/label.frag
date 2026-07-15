#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;

layout(set = 0, binding = 0) uniform sampler2D font_atlas;

layout(location = 0) out vec4 out_color;

void main() {
    float mask  = texture(font_atlas, v_uv).r;
    float alpha = v_color.a * mask;
    if (alpha < 0.01) discard;
    out_color = vec4(v_color.rgb, alpha);
}
