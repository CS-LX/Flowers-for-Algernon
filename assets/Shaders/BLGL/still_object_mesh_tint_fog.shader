shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_pos : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);
uniform vec4 mesh_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec3 fog_up = vec3(0.0, 1.0, 0.0);
uniform vec4 fog_color : source_color = vec4(0.204, 0.541, 0.639, 1.0);
uniform float fog_height_a = 8.0;
uniform float fog_height_b = 0.0;

uniform float grade_saturation = 0.55;
uniform float grade_value = 1.08;
uniform float grade_contrast = 0.72;
uniform float grade_haze = 0.22;

varying vec3 world_n;
varying vec3 world_p;

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
    world_n = MODEL_NORMAL_MATRIX * NORMAL;
    world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
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

    vec3 up = fog_up;
    float upLength = length(up);
    if (upLength < 0.0001) {
        up = vec3(0.0, 1.0, 0.0);
        upLength = 1.0;
    }
    float height = dot(world_p, up / upLength);
    float span = fog_height_b - fog_height_a;
    float fog = 0.0;
    if (abs(span) > 0.0001) {
        fog = clamp((height - fog_height_a) / span, 0.0, 1.0);
    }
    color = mix(color, fog_color.rgb, fog);

    ALBEDO = color;
}
