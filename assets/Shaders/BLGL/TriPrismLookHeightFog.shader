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

uniform float ao_enabled = 1.0;
uniform vec4 ao_color : source_color = vec4(0.16, 0.12, 0.10, 1.0);
uniform float ao_smooth = 0.18;
uniform float ao_blend = 1.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.957, 0.824, 1.0);
uniform float emission_strength = 0.25;
uniform float hover_amount = 0.0;

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
    // Original: transpose(mat3(MODEL_MATRIX)) * NORMAL
    // Not cross-platform: HLSL has no float3x3(float4x4).
    world_n = (transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;
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

    if (ao_enabled > 0.5) {
        vec3 bary = vec3(max(1.0 - UV.x - UV.y, 0.0), max(UV.x, 0.0), max(UV.y, 0.0));
        vec3 edgeOpen = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
        float width = max(ao_smooth, 0.001);
        float height = 0.8660254;
        float dBC = bary.x * height;
        float dCA = bary.y * height;
        float dAB = bary.z * height;
        float dA = sqrt(max(bary.y * bary.y + bary.z * bary.z + bary.y * bary.z, 0.0));
        float dB = sqrt(max(bary.z * bary.z + bary.x * bary.x + bary.z * bary.x, 0.0));
        float dC = sqrt(max(bary.x * bary.x + bary.y * bary.y + bary.x * bary.y, 0.0));
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

    float emit = clamp(hover_amount * emission_strength, 0.0, 1.0);
    color = mix(color, emission_color.rgb, emit);

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
