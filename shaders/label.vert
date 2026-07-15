#version 450

layout(location = 0) in vec3 in_anchor;
layout(location = 1) in vec2 in_offset_px;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec4 in_color;

layout(push_constant) uniform PC {
    mat4  mvp;
    float time_sec;
    int   selected_index;
    vec2  viewport;
    vec4  eye;
} pc;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;

void main() {
    vec4 clip = pc.mvp * vec4(in_anchor, 1.0);

    // Billboard: apply the pixel offset in NDC after projection so the text
    // stays a fixed on-screen size regardless of camera distance.
    clip.xy += (in_offset_px * 2.0 / pc.viewport) * clip.w;
    gl_Position = clip;

    // Fade labels out as their anchor rolls past the globe horizon.
    float facing = dot(normalize(in_anchor), normalize(pc.eye.xyz - in_anchor));
    float vis    = smoothstep(0.0, 0.18, facing);

    v_uv    = in_uv;
    v_color = vec4(in_color.rgb, in_color.a * vis);
}
