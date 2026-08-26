shader_type spatial;
render_mode shading_model_unlit, blend_mix, depth_test_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(0.96, 0.86, 0.36, 1.0);

void fragment() {
    ALBEDO = base_color.rgb;
    ALPHA = base_color.a;
}
