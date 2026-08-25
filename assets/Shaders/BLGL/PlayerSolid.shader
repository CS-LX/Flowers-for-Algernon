shader_type spatial;
render_mode shading_model_unlit, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.96, 0.86, 0.36, 1.0);

void fragment() {
    ALBEDO = base_color.rgb;
    ALPHA = base_color.a;
}
