shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform sampler2D albedo_map : source_color, filter_linear, repeat_disable;
uniform float use_albedo_map = 0.0;

varying vec2 mesh_uv;

void vertex() {
    // 片元 UV 对导入网格不可靠，从 vertex 传入。
    mesh_uv = UV;
}

void fragment() {
    vec3 mapped = texture(albedo_map, mesh_uv).rgb;
    ALBEDO = mix(base_color.rgb, mapped, clamp(use_albedo_map, 0.0, 1.0));
    ALPHA = 1.0;
}
