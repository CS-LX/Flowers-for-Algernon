# Surface Shader：不要用 `mat3(MODEL_MATRIX)` 变换法线

写或改 `assets/Shaders/BLGL/*.shader` 时遵守本规范。引擎教程副本在 `engine-docs/recipes/surface-shader.md`（该目录不进本仓库）。

`MODEL_MATRIX` 是 `mat4`。GLSL 允许 `mat3(mat4)`，但 Surface Shader 编译到 HLSL 时会变成非法的 `float3x3(float4x4)`，PC / Direct3D 编不过。WebGL 预览可能正常，不能当跨平台通过。

语义：`w = 0` 只转方向、不吃平移，和抽 3×3 一样。

```glsl
// ❌ Not cross-platform: HLSL has no float3x3(float4x4).
world_n = transpose(mat3(MODEL_MATRIX)) * NORMAL;
world_n = mat3(MODEL_MATRIX) * NORMAL;

// ✅ Inverse-transpose (non-uniform scale). Original: transpose(mat3(MODEL_MATRIX)) * NORMAL
world_n = (transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;

// ✅ Direct 3x3 (no inverse-transpose). Original: mat3(MODEL_MATRIX) * NORMAL
world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
```

改现有 shader 时保留原写法注释，并写明不跨平台原因。不要把「直接乘 3×3」顺手改成 inverse-transpose，那是既有明暗方向。
