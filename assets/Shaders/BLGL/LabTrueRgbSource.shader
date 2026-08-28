shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.956, 0.262, 0.211, 1.0);

void fragment() {
    ALBEDO = base_color.rgb;
}
