shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color = vec4(0.956, 0.262, 0.211, 1.0);

void fragment() {
    ALBEDO = pow(max(base_color.rgb, vec3(0.0)), vec3(1.0 / 2.2));
}
