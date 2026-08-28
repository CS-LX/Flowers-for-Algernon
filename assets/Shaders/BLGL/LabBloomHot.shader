shader_type spatial;
render_mode shading_model_unlit, cull_back;

void fragment() {
    ALBEDO = vec3(1.0, 0.92, 0.35);
    EMISSION = vec3(8.0, 7.0, 1.5);
}
