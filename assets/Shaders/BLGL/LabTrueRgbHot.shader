shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emit_gain = 3.0;

void fragment() {
    ALBEDO = pow(max(base_color.rgb, vec3(0.0)), vec3(2.2)) * emit_gain;
}
