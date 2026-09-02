shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform vec4 stencil_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D albedo_map : source_color, filter_linear, repeat_disable;
uniform float use_albedo_map = 0.0;

varying vec2 mesh_uv;

void vertex() {
    mesh_uv = UV;
}

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec3 mask = texture(mask_rt, maskUv).rgb;
    float match = float(mask.r == stencil_color.r && mask.g == stencil_color.g && mask.b == stencil_color.b);
    vec3 mapped = texture(albedo_map, mesh_uv).rgb;
    ALBEDO = mix(base_color.rgb, mapped, clamp(use_albedo_map, 0.0, 1.0));
    ALPHA = match;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
