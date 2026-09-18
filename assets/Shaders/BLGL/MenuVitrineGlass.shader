shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 glass_tint : source_color = vec4(0.68, 0.82, 0.84, 1.0);
uniform vec4 fresnel_tint : source_color = vec4(0.94, 0.99, 0.97, 1.0);
uniform float face_alpha : hint_range(0.0, 1.0, 0.01) = 0.025;
uniform float fresnel_alpha : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float fresnel_power : hint_range(0.5, 8.0, 0.1) = 3.0;

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
    world_n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_p);
    float fresnel = pow(clamp(1.0 - abs(dot(normalize(world_n), view_dir)), 0.0, 1.0), fresnel_power);
    ALBEDO = mix(glass_tint.rgb, fresnel_tint.rgb, fresnel);
    ALPHA = mix(face_alpha, fresnel_alpha, fresnel);
}
