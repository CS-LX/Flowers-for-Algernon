shader_type spatial;
render_mode shading_model_unlit, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.23, 0.67, 0.68, 1.0);
uniform float cloak_angle = 0.0;
uniform vec3 cloak_pivot = vec3(0.0, 1.02, 0.0);

void vertex() {
    float c = cos(cloak_angle);
    float s = sin(cloak_angle);
    vec3 p = VERTEX - cloak_pivot;
    VERTEX = cloak_pivot + vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
    NORMAL = vec3(NORMAL.x, NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
}

void fragment() {
    ALBEDO = base_color.rgb;
    ALPHA = base_color.a;
}
