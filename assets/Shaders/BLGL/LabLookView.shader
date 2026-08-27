shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(1.0, 0.12, 0.12, 1.0);
uniform vec4 color_mid : source_color = vec4(0.12, 0.86, 0.22, 1.0);
uniform vec4 color_pos : source_color = vec4(0.18, 0.42, 1.0, 1.0);
uniform vec3 light_axis = vec3(0.0, 1.0, 0.0);

void fragment() {
    vec3 axis = normalize(light_axis);
    float t = clamp(dot(normalize(NORMAL), axis), -1.0, 1.0);
    vec3 color;
    if (t < 0.0) {
        color = mix(color_neg.rgb, color_mid.rgb, t + 1.0);
    } else {
        color = mix(color_mid.rgb, color_pos.rgb, t);
    }
    ALBEDO = color;
}
