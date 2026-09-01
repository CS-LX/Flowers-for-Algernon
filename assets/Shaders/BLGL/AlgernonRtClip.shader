shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform sampler2D screen_src : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform float clip_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
    vec2 uv = SCREEN_UV;
    float _probe = texture(screen_src, uv).a * 0.0;
    vec2 maskUv = vec2(uv.x, 1.0 - uv.y);
    float mask = texture(mask_rt, maskUv).r + _probe;
    ALBEDO = base_color.rgb;
    ALPHA = step(clip_threshold, mask);
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
