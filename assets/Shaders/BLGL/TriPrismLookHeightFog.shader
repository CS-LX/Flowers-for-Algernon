shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(0.561, 0.518, 0.471, 1.0);
uniform vec4 color_mid : source_color = vec4(0.769, 0.714, 0.651, 1.0);
uniform vec4 color_pos : source_color = vec4(0.945, 0.902, 0.835, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);

uniform vec3 fog_up = vec3(0.0, 1.0, 0.0);
uniform vec4 fog_color : source_color = vec4(0.788, 0.761, 0.706, 1.0);
uniform float fog_height_a = 4.0;
uniform float fog_height_b = 0.0;

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
    world_n = transpose(mat3(MODEL_MATRIX)) * NORMAL;
    world_p = (transpose(MODEL_MATRIX) * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 axis = normalize(light_axis);
    float t = clamp(dot(normalize(world_n), axis), -1.0, 1.0);
    vec3 color;
    if (t < 0.0) {
        color = mix(color_neg.rgb, color_mid.rgb, t + 1.0);
    } else {
        color = mix(color_mid.rgb, color_pos.rgb, t);
    }

    vec3 up = fog_up;
    float upLength = length(up);
    if (upLength < 0.0001) {
        up = vec3(0.0, 1.0, 0.0);
        upLength = 1.0;
    }
    float height = dot(world_p, up / upLength);
    float span = fog_height_b - fog_height_a;
    float fog = 0.0;
    if (span > 0.0001 || span < -0.0001) {
        fog = clamp((height - fog_height_a) / span, 0.0, 1.0);
    }
    color = mix(color, fog_color.rgb, fog);

    ALBEDO = pow(max(color, vec3(0.0)), vec3(2.2));
}
