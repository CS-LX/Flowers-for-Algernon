shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_pos : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);
uniform vec4 mesh_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 fog_color : source_color = vec4(0.204, 0.541, 0.639, 1.0);
uniform vec4 stencil_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;

uniform float grade_saturation = 0.55;
uniform float grade_value = 1.08;
uniform float grade_contrast = 0.72;
uniform float grade_haze = 0.22;

varying vec3 world_n;

vec3 rgb_to_hsv(vec3 c) {
    vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-5;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
    // Original: mat3(MODEL_MATRIX) * NORMAL
    // Not cross-platform: HLSL has no float3x3(float4x4).
    world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec3 mask = texture(mask_rt, maskUv).rgb;
    ivec3 maskBytes = ivec3(round(mask * 255.0));
    ivec3 expectedBytes = ivec3(round(stencil_color.rgb * 255.0));
    float match = float(
        maskBytes.x == expectedBytes.x
        && maskBytes.y == expectedBytes.y
        && maskBytes.z == expectedBytes.z
    );

    vec3 axis = normalize(light_axis);
    float t = clamp(dot(normalize(world_n), axis), -1.0, 1.0);
    vec3 ramp;
    if (t < 0.0) {
        ramp = mix(color_neg.rgb, color_mid.rgb, t + 1.0);
    } else {
        ramp = mix(color_mid.rgb, color_pos.rgb, t);
    }
    vec3 color = mesh_color.rgb * ramp;

    vec3 hsv = rgb_to_hsv(max(color, vec3(0.0)));
    hsv.y = clamp(hsv.y * grade_saturation, 0.0, 1.0);
    hsv.z = clamp(hsv.z * grade_value, 0.0, 1.0);
    color = hsv_to_rgb(hsv);
    color = mix(vec3(dot(color, vec3(0.299, 0.587, 0.114))), color, grade_contrast);
    color = mix(color, fog_color.rgb, clamp(grade_haze, 0.0, 1.0));

    ALBEDO = color;
    ALPHA = match;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
