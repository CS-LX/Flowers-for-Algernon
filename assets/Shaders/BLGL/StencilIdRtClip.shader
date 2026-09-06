shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform vec4 stencil_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D albedo_map : source_color, filter_linear, repeat_disable;
uniform float use_albedo_map = 0.0;
uniform float two_tone = 0.0;
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);
uniform float shade_saturation = 0.2;
uniform float shade_value = 0.1;

varying vec2 mesh_uv;
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

vec3 shade_by_light(vec3 color, vec3 normal) {
    float lit = step(0.0, dot(normalize(normal), normalize(light_axis)));
    vec3 hsv = rgb_to_hsv(max(color, vec3(0.0)));
    hsv.y = clamp(hsv.y + (1.0 - lit) * shade_saturation, 0.0, 1.0);
    hsv.z = max(hsv.z - (1.0 - lit) * shade_value, 0.0);
    return hsv_to_rgb(hsv);
}

void vertex() {
    mesh_uv = UV;
    world_n = transpose(mat3(MODEL_MATRIX)) * NORMAL;
}

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec3 mask = texture(mask_rt, maskUv).rgb;
    vec3 expected = stencil_color.rgb;
    ivec3 maskBytes = ivec3(round(mask * 255.0));
    ivec3 expectedBytes = ivec3(round(expected * 255.0));
    float match = float(
        maskBytes.x == expectedBytes.x
        && maskBytes.y == expectedBytes.y
        && maskBytes.z == expectedBytes.z
    );
    vec3 mapped = texture(albedo_map, mesh_uv).rgb;
    vec3 color = mix(base_color.rgb, mapped, clamp(use_albedo_map, 0.0, 1.0));
    if (two_tone > 0.5) {
        color = shade_by_light(color, world_n);
    }
    ALBEDO = color;
    ALPHA = match;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
