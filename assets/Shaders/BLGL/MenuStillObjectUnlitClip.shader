shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_back, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0, 0.882, 0.290, 1.0);
uniform float v_fade = 0.0;
uniform float fade_use_object_y = 0.0;
uniform vec4 stencil_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;

varying float fade_coord;

void vertex() {
    float from_uv = UV.y;
    float from_y = 1.0 - VERTEX.y;
    fade_coord = mix(from_uv, from_y, clamp(fade_use_object_y, 0.0, 1.0));
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
    float t = clamp(fade_coord, 0.0, 1.0);
    float s = t * t * (3.0 - 2.0 * t);
    float perceptual = pow(max(s, 0.0), 2.2);
    float a = mix(1.0, perceptual, clamp(v_fade, 0.0, 1.0));
    ALBEDO = base_color.rgb;
    ALPHA = a * match;
}
