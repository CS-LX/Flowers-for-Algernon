# 三棱柱体素 × Surface Shader 实验记录

## 文档定位

这是实验分支 `experiment/voxel-surface-shader` 的**已验证结论**，不是关卡编辑器已经验收的产品状态。

目的有两个：

1. 固化 CustomGeometry、Surface Shader、法线空间的实验结果；
2. 以后改体素材质时先读本文，不要再从关卡编辑器里猜。

证据等级：

- **已验证**：隔离实验室 `VoxelLookLab` 的真实 Preview 画面；
- **推断**：由画面反推引擎内部语义，未读引擎源码。

关卡编辑器里的石膏色体素当时“像没画出来”，主要是低对比 + 灰蓝雾底，不是几何丢失。本文不把关卡画面当成这条链路的最终验收。

## 稳定公式

正式 shader：`assets/Shaders/BLGL/TriPrismLook.shader`

```glsl
shader_type spatial;
render_mode shading_model_unlit, cull_back;

varying vec3 world_n;

void vertex() {
    // Original: transpose(mat3(MODEL_MATRIX)) * NORMAL
    // Not cross-platform: HLSL has no float3x3(float4x4).
    world_n = (transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    float t = clamp(dot(normalize(world_n), normalize(light_axis)), -1.0, 1.0);
    // t < 0: mix(color_neg, color_mid, t + 1)
    // t >= 0: mix(color_mid, color_pos, t)
    ALBEDO = pow(max(color, vec3(0.0)), vec3(2.2));
}
```

必须同时满足：

| 项 | 结论 |
|---|---|
| 着色模型 | Unlit。`dot(N, axis)` 已经编码明暗，Lit 会二次乘光 |
| 几何 | CustomGeometry 可以挂 Surface Shader，前提是不用 `world_vertex_coords` |
| 法线读取 | **只在 `vertex()` 读 `NORMAL`**。fragment 里的 `NORMAL` 对 CustomGeometry 不是网格法线 |
| 世界变换 | `(transpose(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz`。不要写 `mat3(MODEL_MATRIX)`，HLSL 没有 `float3x3(float4x4)`。正乘 `MODEL_MATRIX * vec4(NORMAL, 0.0)` 会把符号反掉。详见 `docs/surface-shader-mat3-cross-platform.md` |
| 轴 | `light_axis` 是世界轴。`+Y` 时顶面应是 `color_pos`，底面 `color_neg`，侧面 `color_mid` |

Lua 侧：

```lua
material:SetSurfaceShader("Shaders/BLGL/TriPrismLook.shader")
material:SetShaderParameter("color_neg", Variant(Color(...)))
material:SetShaderParameter("color_mid", Variant(Color(...)))
material:SetShaderParameter("color_pos", Variant(Color(...)))
material:SetShaderParameter("light_axis", Variant(Vector3(x, y, z)))
customGeometry:SetMaterial(material)
```

## 为什么必须隔离实验

关卡编辑器同时有雾、正交远看、石膏低对比色、Part 层级和 Overlay。单看“体素没了”无法区分：

- shader 没挂上；
- CustomGeometry 不画 Surface Shader；
- 画出来了但和背景糊在一起；
- 法线空间错了导致整块一个色。

实验室 `scripts/VoxelLookLab.lua` 把这些拆开：三列并排、RGB 高对比、可旋转相机、可把棱柱绕 X 躺 90°。

入口在实验分支上是 `scripts/main.lua` → `VoxelLookLab`。主分支关卡编辑器被冻结在不稳定 checkpoint `5b0f4f1`。

## 实验序列与结论

### 1. CustomGeometry 会画 Surface Shader

对照：PBR / 已验证 `PlayerSolid` Unlit / `TriPrismLook`。

画面：三列都有 Box 和三棱柱。石膏色列不是没画，是和灰蓝底对比太弱。

结论：CustomGeometry + Surface Shader **能出图**。关卡里“空了”不能直接当成几何失败。

### 2. fragment `NORMAL` 不是网格法线

高对比：红=朝下，绿=侧面，蓝=朝上，轴=`(0,1,0)`。

| 写法 | Box (StaticModel) | 棱柱 (CustomGeometry) | 旋转相机 |
|---|---|---|---|
| fragment `NORMAL` | 通体绿 | 通体绿 | 不变色 |
| `world_vertex_coords` + vertex 里存 `NORMAL` | 顶蓝底红 | **顶点被当成世界坐标，堆到原点/消失** | Box 不跟相机变 |

结论：

- fragment `NORMAL` 对 CustomGeometry 不是面法线，不能拿来做分面；
- 它也不跟着相机跑，所以也不是简单的视空间；
- `world_vertex_coords` 只适合 StaticModel，不适合本项目的 CustomGeometry 棱柱。

### 3. `vertex()` 里的 `NORMAL` 是物体空间网格法线

```glsl
void vertex() {
    obj_n = NORMAL;
}
```

直立棱柱：顶蓝、底红、侧面绿。旋转相机不变色。

把棱柱绕 X 躺 90° 后：原来的顶面跟着转到侧面（绿），朝上的面变成红。

结论：`vertex() NORMAL` 是**物体空间**。rotator / 节点旋转会带着明暗面一起转。

### 4. 世界法线公式

| 公式 | 躺倒棱柱朝上的面 |
|---|---|
| `mat3(MODEL_MATRIX) * NORMAL` | 变红（转了，但符号反） |
| `transpose(mat3(MODEL_MATRIX)) * NORMAL` | **保持蓝** |

`MODEL_MATRIX` 未写入 Surface Shader 公开文档，但是本实验室 Preview 已验证可用。正乘会反号，必须转置。

正式 shader 用转置公式后：直立和躺倒两列朝上的面都保持蓝。这才是纪念碑谷式“顶面永远亮”。

### 5. 顶点色烘焙法线是备用方案

把物体法线写入 `DefineColor((n+1)/2)`，shader 读 `COLOR.rgb * 2 - 1`。棱柱顶蓝底红可用，但右列 StaticModel Box 没有这套顶点色，会整面偏一种色。

优先用 `vertex() NORMAL` + `transpose(MODEL_MATRIX)`。只有这条在目标平台失败时，才退回 COLOR 烘焙。

## 语义上应该有，实际上没有 / 有了等于没有 / 有了是反的

这一节单独记录“按文档或图形学常识本该成立，实验室画面否定了它”的项。以后不要再用常识覆盖这些结论。

| 按语义应该怎样 | 实际 | 等级 | 怎么识别 |
|---|---|---|---|
| 文档把 `NORMAL` 写成 vertex / fragment 都能用的法线 | **fragment `NORMAL` 对 CustomGeometry（以及本实验室的 Box）不是网格面法线。** 高对比轴 `+Y` 时整块绿，俯视仰视都不变。写了 `dot(NORMAL, axis)` 等于没写分面 | 已验证 | RGB 分面实验，整块一个色且不跟相机变 |
| Godot / 常见引擎里 fragment `NORMAL` 常是视空间或世界空间，旋转相机会变 | 本实验室 fragment `NORMAL` **不跟相机变**，也不是面法线。既不能当视空间用，也不能当网格法线用 | 已验证 | RMB 旋转，通体绿不变 |
| `world_vertex_coords` 只改 `VERTEX` 空间，法线仍按网格走 | 对 StaticModel 可用；对 CustomGeometry **顶点被当世界坐标**，棱柱堆到原点，看起来像没画。法线实验还没开始，几何先没了 | 已验证 | 只有 Box 在，棱柱消失或叠在世界原点 |
| 文档示例 Unlit 在 fragment 写 `ALBEDO` 就够 | 对纯色可以。对分面不够：必须在 **`vertex()` 读 `NORMAL` 再 varying 出去**。省略 vertex 阶段 = 有 shader 无分面 | 已验证 | 石膏色能看见物体，但看不出顶面/侧面 |
| `MODEL_MATRIX` 是公开 Surface Shader 输入 | **公开文档的常用输入表里没有它。** 实验室能编过、能出图，但这是未文档化能力，换平台要再验 | 文档缺失 + 实验室可用 | 查 `surface-shader.md` 常用变量表 |
| `N_world = mat3(MODEL_MATRIX) * N_object`（常见正乘） | **符号反了。** 躺倒后朝上的面变成 `color_neg`（红），不是 `color_pos`（蓝） | 已验证 | 直立顶蓝、躺倒朝上变红 |
| 法线要用逆转置：`transpose(inverse(mat3(MODEL_MATRIX)))` | 均匀旋转下逆转置 = 原矩阵。实验室里 **`transpose(mat3(MODEL_MATRIX))` 才把朝上锁成蓝**，正乘和“该用的逆转置直觉”都不对 | 已验证画面，矩阵语义未读源码 | 躺倒棱柱朝上是否保持蓝 |
| `DefineNormal` 之后 fragment 一定能读到该法线 | CustomGeometry 的 `DefineNormal` **只稳定出现在 `vertex() NORMAL`**。fragment 读不到等价数据 | 已验证 | vertex 分面正确、fragment 通体绿 |
| 给顶点写了 `DefineColor((n+1)/2)`，所有模型都能用 COLOR 当法线 | 只对写了这套色的棱柱有效。同一材质打到普通 Box 上，Box 没有法线顶点色，整面偏一种色。**备用方案，不是通用材质** | 已验证 | 右列棱柱顶蓝底红，同列 Box 通蓝 |
| `SetSurfaceShader` 成功 = 画面语义正确 | 只说明编译/绑定成功。石膏低对比 + 错误法线空间时，**成功和失败看起来都像没分面或没画** | 已验证 | 必须用 RGB，并做直立/躺倒对照 |
| 不透明 Unlit 写 `ALPHA = 1.0` 无害 | 引擎警告：写了 ALPHA 却没有 `blend_mix`。对不透明材质 **写了等于制造噪声**，应删掉 | 引擎日志 | `SurfaceShader ... ALPHA is written but no transparent render_mode` |
| 关卡编辑器里看不见 = shader/几何坏了 | 实验室证明几何和 shader 都能画。关卡“空”更像 **浅石膏 + 灰蓝/米色雾底糊在一起** | 已验证（实验室）/ 关卡未复验 | 先换 RGB 或关雾，再判断丢失 |
| `FillModel` → StaticModel 才能用 Surface Shader | 不需要。根因是法线空间和 `world_vertex_coords`，不是 CustomGeometry 不能挂 shader | 已验证 | 实验室棱柱一直是 CustomGeometry |
| `CAMERA_POSITION_WORLD` 等文档变量可用来手搓世界法线 | 本实验室 **没有验证** 用相机位置重建法线。未验证就当没有 | 未验证 | 不要用它替代已验证公式 |

一句话对照：

```text
文档说 NORMAL 两阶段都能用
  -> 实际只有 vertex() 对 CustomGeometry 有网格法线

常识说 MODEL_MATRIX 正乘得世界法线
  -> 实际正乘反号，必须 transpose

文档没写 MODEL_MATRIX
  -> 实际能用，但是未文档化，要当实验结论而不是引擎保证

看起来没画
  -> 实际经常是画了但看不见，或画了但没有分面
```

## 禁止清单

以后不要再做这些事：

1. **不要在 fragment 里对 CustomGeometry 写 `dot(NORMAL, axis)`。** 会得到整块一个色。
2. **不要给 CustomGeometry 加 `world_vertex_coords`。** 局部顶点会被当成世界坐标，体素堆到原点，看起来像没画。
3. **不要用石膏低对比色在灰蓝雾底上判断“有没有画出来”。** 先用红/绿/蓝。
4. **不要用 `mat3(MODEL_MATRIX) * NORMAL` 当世界法线。** 会反号：朝上变 `color_neg`。
5. **不要把 Surface Shader 挂到 CustomGeometry 失败，直接改成 FillModel/StaticModel 当架构。** 根因是法线空间和 `world_vertex_coords`，不是 CustomGeometry 本身。
6. **不要写 `ALPHA = 1.0` 却不加 `blend_mix`。** 引擎会警告；不透明材质不要写 ALPHA。
7. **不要在关卡编辑器里同时改雾、色板、shader、几何。** 先实验室，再回关卡。

## 如何复现实验室

实验分支：`experiment/voxel-surface-shader`

```text
scripts/main.lua          -> require VoxelLookLab
scripts/VoxelLookLab.lua  -> 三列对照
assets/Shaders/BLGL/LabLook*.shader
```

操作：RMB 旋转，滚轮缩放。看朝上的面是不是蓝。

实验室 shader 可以留着当对照，不要当产品材质。产品只认 `TriPrismLook.shader`。

## 切回关卡前还没验收的部分

- 关卡编辑器 / Preview 用石膏色 + 关卡雾后，分面是否仍可读；
- rotator / mover 转过之后，世界顶面是否仍是 `color_pos`；
- `MODEL_MATRIX` 在发布目标平台是否与实验室一致；
- 主分支入口仍是关卡编辑器，不要把 `VoxelLookLab` 留在 `main.lua`。

切回主分支时：保留 `TriPrismLook.shader` 的世界法线公式，删除或停用实验室入口。
