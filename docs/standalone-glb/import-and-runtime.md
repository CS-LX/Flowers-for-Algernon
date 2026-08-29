# Standalone GLB 导入与运行时能力

## 文档定位

本文记录本项目独立 3D 资产（门、角色剪影、花、窗等）的源格式选择和引擎能力边界。可走面、台阶、旋转/平移 Part 仍用三棱柱体素，不把 GLB 当成 Path Graph 数据源。

结论分级：

- **公开能力**：导入工具和运行时 API 已文档化；
- **运行时存在、导入未证明**：API 有，导入链路未写明；
- **本项目约定**：结合错视玩法给出的使用边界。

## 1. 源格式与运行时格式

推荐源格式是 **GLB / glTF**。FBX 也可导入，本项目默认 GLB。

游戏里不直接加载 GLB。导入后运行的是：

```text
Meshes/*.mdl
Materials/*_00_Name.xml
Textures/*_00_D/N/S/E.*
Prefabs/*.prefab          （可选）
Animations/<name>/*.ani   （可选，需 --import-anim）
```

导入命令：

```bash
/workspace/.cli/UrhoXCLI import-gltf \
  -i /workspace/assets/Raw/character.glb \
  -o /workspace/assets/Meshes/character.mdl \
  --material-dir /workspace/assets/Materials \
  --texture-dir /workspace/assets/Textures \
  --prefab /workspace/assets/Prefabs/character.prefab \
  --import-anim /workspace/assets/Animations/character
```

导入器会做：右手系 → 左手系、UV 翻转、米制单位。路径必须用绝对路径。不传的输出参数不会生成对应产物。默认 3 级 LOD。

运行时组件：

| 资产 | 组件 |
|---|---|
| 静态建筑 / StillObject | `StaticModel` |
| 骨骼动画 / 形态键 | `AnimatedModel` + `AnimationController` |

单位是米，与三棱柱网格一致：边长 `a = 1.0 m`，竖直高度 `h ≈ 0.577 m`。

## 2. GLB 能带进引擎的内容

| 内容 | 状态 |
|---|---|
| 网格 / 子网格 | 支持，写入 MDL geometry 槽 |
| BaseColor / Normal / Specular / Emissive 贴图 | 支持，导出到 Textures |
| PBR 材质 XML | 支持；有顶点色时走 `PBRDiffVCol` |
| 骨骼与骨骼动画 | 支持，需 `--import-anim` 才出 `.ani` |
| Prefab | 可选 |
| LOD | 默认开启 |
| Morph target / 形态键 | 运行时 API 有，导入是否写入 MDL **未文档化** |

独立模型可以走导入材质，不要和 Part 的 Unlit look shader 绑死。可走面继续用体素。

## 3. Blender 动画导入与驱动

**支持。** 这是正式能力。

```text
Blender 骨骼动画
  → GLB（armature + action / NLA，Bake Animation，Y-up，米）
  → import-gltf --import-anim
  → AnimatedModel + AnimationController:PlayExclusive(".../idle.ani")
```

角色用 FSM / BlendSpace；门开关、一次性状态用 `AnimationController` 即可。

```lua
local node = scene:CreateChild("Character")
local animModel = node:CreateComponent("AnimatedModel")
animModel:SetModel(cache:GetResource("Model", "Meshes/character.mdl"))
local animCtrl = node:CreateComponent("AnimationController")
animCtrl:PlayExclusive("Animations/character/idle.ani", 0, true, 0.2)
```

## 4. Blender 形态键导入与驱动

运行时可以调权重：

```lua
model.numMorphs
animModel:SetMorphWeight("Smile", 0.5)
animModel:ResetMorphWeights()
```

`import-gltf` 文档只写了网格、材质、贴图、骨骼动画，**没有写 morph target**。因此：

- 不要把形态键当 P0 必过能力；
- 门、花、角色剪影优先用骨骼或显隐；
- 若要用，导入后立刻 `model-info` 看 morph 数；为 0 说明这条 GLB 没带进来。

## 5. 子 mesh

**支持。** MDL 按 geometry 槽保存。

```lua
model:GetNumGeometries()
staticModel:GetNumGeometries()
```

Blender 里多个 mesh / 多个材质槽，导入后通常变成多个 geometry。`model-info` 会列出 `Geometry 0/1/...`。

这是子网格槽，不是同一套三角形叠两份材质。

## 6. 按 mesh 给材质

**支持。** `index` 从 0 开始，对应导入材质序号 `00/01/...`。

```lua
staticModel:SetMaterial(material)            -- 整模型一份
staticModel:SetMaterial(index, material)     -- 第 index 个子网格
staticModel:ApplyMaterialList("xxx.txt")     -- 按槽批量
```

门框/门扇、窗框/玻璃、花茎/花瓣应拆成不同 mesh + 不同材质槽。

## 7. 本项目建模约定

1. 源文件放 `assets/Raw/*.glb`，导入到 `Meshes/Materials/Textures`。
2. 单位米，对齐三棱柱网格。
3. 门框、门扇、角色、花分开文件，或至少分 mesh。
4. 动画用骨骼，不要赌形态键。
5. GLB 只做 StillObject / 叙事焦点，不带 PathNode，不生成 Path Graph 边。
6. 导入后用 `model-info` 核对包围盒、geometry 数、骨骼、morph 数。

相关文档：

- `docs/voxel-spec.md` — 三棱柱尺度
- `docs/hexagonal-monument-valley-p0-standalone-3d-assets.md` — P0 资产清单
- `docs/standalone-glb/stencil-mask.md` — shader stencil mask 能力
