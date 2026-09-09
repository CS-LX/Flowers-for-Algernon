shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(0.664, 0.562, 0.501, 1.0);
uniform vec4 color_mid : source_color = vec4(0.804, 0.733, 0.639, 1.0);
uniform vec4 color_pos : source_color = vec4(0.944, 0.902, 0.762, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);
uniform vec4 stencil_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;

varying vec3 world_n;

void vertex() {
    // Original: transpose(mat3(MODEL_MATRIX)) * NORMAL
    // Not cross-platform: HLSL has no float3x3(float4x4).
    world_n = (transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec3 mask = texture(mask_rt, maskUv).rgb;
    ivec3 maskBytes = ivec3(round(mask * 255.0));
    ivec3 expectedBytes = ivec3(round(stencil_color.rgb * 255.0));
    float match = float(
        maskBytes.x == expectedBytes.x
        && maskBytes.y == expectedBytes.y
        && maskBytes.z == expectedBytes.z
    );
    vec3 axis = normalize(light_axis);
    float t = clamp(dot(normalize(world_n), axis), -1.0, 1.0);
    vec3 color;
    if (t < 0.0) {
        color = mix(color_neg.rgb, color_mid.rgb, t + 1.0);
    } else {
        color = mix(color_mid.rgb, color_pos.rgb, t);
    }
    ALBEDO = pow(max(color, vec3(0.0)), vec3(2.2));
    ALPHA = match;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
