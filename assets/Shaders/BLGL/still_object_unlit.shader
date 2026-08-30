shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_back, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0, 0.882, 0.290, 1.0);
uniform float v_fade = 0.0;
uniform float fade_use_object_y = 0.0;

varying float fade_coord;

void vertex() {
    // 片元 UV 对导入网格不可靠。Light 导入后根部 Y=0 / V=1 实色，顶端 Y=1 / V=0 透明。
    float from_uv = UV.y;
    float from_y = 1.0 - VERTEX.y;
    fade_coord = mix(from_uv, from_y, clamp(fade_use_object_y, 0.0, 1.0));
}

void fragment() {
    float t = clamp(fade_coord, 0.0, 1.0);
    // Hermite S 曲线：两端不再像直尺切一刀。
    float s = t * t * (3.0 - 2.0 * t);
    // 人眼亮度近似 γ=2.2。线性 alpha 中段几乎不淡、末端才陡降；
    // pow(s, 2.2) 让感知上的衰减更匀，光柱也更接近 Beer–Lambert 尾迹。
    float perceptual = pow(max(s, 0.0), 2.2);
    float a = mix(1.0, perceptual, clamp(v_fade, 0.0, 1.0));
    ALBEDO = base_color.rgb;
    ALPHA = a;
}
