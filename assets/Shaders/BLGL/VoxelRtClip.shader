shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(0.561, 0.518, 0.471, 1.0);
uniform vec4 color_mid : source_color = vec4(0.769, 0.714, 0.651, 1.0);
uniform vec4 color_pos : source_color = vec4(0.945, 0.902, 0.835, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform float clip_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

varying vec3 world_n;

void vertex() {
    // Original: transpose(mat3(MODEL_MATRIX)) * NORMAL
    // Not cross-platform: HLSL has no float3x3(float4x4).
    world_n = (transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    vec3 axis = normalize(light_axis);
    float t = clamp(dot(normalize(world_n), axis), -1.0, 1.0);
    vec3 color;
    if (t < 0.0) {
        color = mix(color_neg.rgb, color_mid.rgb, t + 1.0);
    } else {
        color = mix(color_mid.rgb, color_pos.rgb, t);
    }

    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    float mask = texture(mask_rt, maskUv).g;
    ALBEDO = color;
    ALPHA = step(clip_threshold, mask);
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
