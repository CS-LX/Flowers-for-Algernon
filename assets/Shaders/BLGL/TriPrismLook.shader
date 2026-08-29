shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 color_neg : source_color = vec4(0.561, 0.518, 0.471, 1.0);
uniform vec4 color_mid : source_color = vec4(0.769, 0.714, 0.651, 1.0);
uniform vec4 color_pos : source_color = vec4(0.945, 0.902, 0.835, 1.0);
uniform vec3 light_axis = vec3(0.35, 1.0, 0.25);

uniform float ao_enabled = 1.0;
uniform vec4 ao_color : source_color = vec4(0.16, 0.12, 0.10, 1.0);
uniform float ao_smooth = 0.18;
uniform float ao_blend = 1.0;

varying vec3 world_n;

float sd_segment(vec2 point, vec2 start, vec2 end) {
    vec2 toPoint = point - start;
    vec2 span = end - start;
    float t = clamp(dot(toPoint, span) / max(dot(span, span), 0.000001), 0.0, 1.0);
    return length(toPoint - span * t);
}

void vertex() {
    world_n = transpose(mat3(MODEL_MATRIX)) * NORMAL;
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

    if (ao_enabled > 0.5) {
        vec2 uv = vec2(UV.x, UV.y);
        vec3 edgeOpen = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
        float width = max(ao_smooth, 0.001);
        float dBC = sd_segment(uv, vec2(1.0, 0.0), vec2(0.0, 1.0));
        float dCA = sd_segment(uv, vec2(0.0, 1.0), vec2(0.0, 0.0));
        float dAB = sd_segment(uv, vec2(0.0, 0.0), vec2(1.0, 0.0));
        float dA = length(uv - vec2(0.0, 0.0));
        float dB = length(uv - vec2(1.0, 0.0));
        float dC = length(uv - vec2(0.0, 1.0));
        float bits = floor(COLOR.a * 7.0 + 0.5);
        float cavityA = step(0.5, mod(bits, 2.0));
        float cavityB = step(0.5, mod(floor(bits / 2.0), 2.0));
        float cavityC = step(0.5, mod(floor(bits / 4.0), 2.0));
        float ao = 1.0;
        ao *= mix(smoothstep(0.0, width, dBC), 1.0, edgeOpen.r);
        ao *= mix(smoothstep(0.0, width, dCA), 1.0, edgeOpen.g);
        ao *= mix(smoothstep(0.0, width, dAB), 1.0, edgeOpen.b);
        ao *= mix(1.0, smoothstep(0.0, width, dA), cavityA);
        ao *= mix(1.0, smoothstep(0.0, width, dB), cavityB);
        ao *= mix(1.0, smoothstep(0.0, width, dC), cavityC);
        float amount = clamp((1.0 - ao) * ao_blend, 0.0, 1.0);
        color = mix(color, ao_color.rgb, amount);
    }

    ALBEDO = pow(max(color, vec3(0.0)), vec3(2.2));
}
