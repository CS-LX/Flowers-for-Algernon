shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color = vec4(1.0, 0.0, 0.0, 1.0);

void fragment() {
    ALBEDO = base_color.rgb;
    ALPHA = 1.0;
}
