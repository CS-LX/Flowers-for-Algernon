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

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
    world_n = mat3(MODEL_MATRIX) * NORMAL;
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
