shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform vec4 stencil_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec3 mask = texture(mask_rt, maskUv).rgb;
    float match = float(mask.r == stencil_color.r && mask.g == stencil_color.g && mask.b == stencil_color.b);
    ALBEDO = base_color.rgb;
    ALPHA = match;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
