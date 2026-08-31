shader_type spatial;
render_mode shading_model_unlit, cull_disabled, depth_test_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(0.96, 0.90, 0.82, 1.0);

void fragment() {
    ALBEDO = pow(max(base_color.rgb, vec3(0.0)), vec3(2.2));
}
