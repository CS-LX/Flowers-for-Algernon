shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform float clip_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    float mask = texture(mask_rt, maskUv).r;
    ALBEDO = base_color.rgb;
    ALPHA = step(clip_threshold, mask);
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
