shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform sampler2D screen_src : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform float clip_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
    vec2 uv = SCREEN_UV;
    float _probe = texture(screen_src, uv).a * 0.0;
    // SCREEN_UV 原点在左上，RT 纹理原点在左下。只翻 Y 对齐模具。
    vec2 maskUv = vec2(uv.x, 1.0 - uv.y);
    vec3 maskColor = texture(mask_rt, maskUv).rgb;
    ALBEDO = maskColor + vec3(_probe);
    ALPHA = 1.0;
}
