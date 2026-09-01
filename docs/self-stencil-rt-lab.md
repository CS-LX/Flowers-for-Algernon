# 自研 Stencil RT 实验记录

## 文档定位

这是实验分支 `experiment/self-stencil-rt` 的**已验证结论**，不是关卡编辑器或 Path Graph 已经验收的产品状态。

目的有三个：

1. 回答 Lua 层有没有硬件 stencil 参考值；
2. 用离屏 RT + Surface Shader clip 做出物体外形遮罩；
3. 验证同一张 RT 能否按颜色通道切开多个物体。

证据等级：

- **已验证**：隔离实验室 `StencilRtLab` 的真实 Preview 画面；
- **推断**：由画面和绑定形状反推引擎内部语义，未读引擎源码。

入口在实验分支上是 `scripts/main.lua` → `StencilRtLab`。主分支玩法入口仍是 `GameApp`，本文不改变那条链路。

## 问题

Lua 游戏层能不能做：

```text
物体 A 当模具
  → 物体 B 只在 A 的屏幕覆盖处显示
  → A 自己可以不出现在主画面
```

标准 GPU stencil 是：

```text
Pass 1: 画 A，只写 stencil ref，不写颜色
Pass 2: 画 B，stencil equal / notequal
```

这条路在 UrhoX Lua 绑定里走不通。

## 引擎能力边界

### 有

| 能力 | 入口 |
|---|---|
| depth-stencil 缓冲 | `TEXTURE_DEPTHSTENCIL`、`GetDepthStencilFormat()` |
| Clear 模板常数 | `CLEAR_STENCIL`、`RenderPathCommand.clearStencil` |
| 场景通道打标 | `RenderPathCommand.markToStencil` |
| 离屏 RT | `Texture2D:SetSize(..., TEXTURE_RENDERTARGET)` |
| 给 RT 挂 Viewport | `RenderSurface:SetViewport` |

### 没有

| 缺口 | 说明 |
|---|---|
| `Material` / `Pass` / `Graphics` 的 stencil func / ref / op | 枚举 `StencilOp` 在，setter 不在 |
| Surface Shader `stencil_*` render_mode | 文档未列出 |
| `Material:GetShaderParameter` | 能写不能读 |
| 把 RT Viewport 放进屏幕槽 0 当“先画” | 用户会先看到整屏 RT |

`markToStencil` 服务的是内置光照通道，不是物体级模具。

## 替代方案

隔离实验室采用 **soft-stencil**：

```text
与主相机同变换的第二台相机
  → 只画模具到离屏 RT
  → 被裁物体用 SCREEN_UV 采样这张 RT
  → ALPHA_SCISSOR 丢掉不符合的片元
```

它比硬件 stencil 贵：多一张 RT、多一次采样。在 Lua 绑不到 stencil 的前提下，这是当前最便宜、也几乎是唯一成立的 GPU 方案。

必须同时满足：

```text
小 RT 或跟视口等比例
  + 瘦 RenderPath（只 Clear + ScenePass）
  + 模具尽量少
  + 不要 hint_screen_texture 回读屏幕
```

## 稳定公式

### RT 写入

- 模具物体 `viewMask = MASK_BIT`
- 世界物体 `viewMask = WORLD_BIT`
- RT 相机只看 `MASK_BIT`
- 主相机只看 `WORLD_BIT`
- Skybox 必须锁到世界 `viewMask`，否则 RT 背景会变成天空色
- Clear 必须 `useFogColor = false`，清成纯黑
- RT 挂在 `RenderSurface` 上，`SURFACE_UPDATEALWAYS`；屏幕 Viewport 0 只画世界

红 / 绿双通道时：

- 红色面片 Replace 写 R
- 绿色面片 Replace 写 G
- 两片几何只碰边，不要穿进对方厚度
- 不要用 Additive 叠通道，接缝会变成黄，两个 clip 会叠在一起

### 采样与 clip

已验证 shader：`assets/Shaders/BLGL/AlgernonRtClip.shader`

```glsl
shader_type spatial;
render_mode shading_model_unlit, cull_back;

uniform vec4 base_color : source_color = vec4(0.957, 0.945, 0.918, 1.0);
uniform sampler2D mask_rt : hint_default_black, filter_nearest, repeat_disable;
uniform float clip_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
    vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    float mask = texture(mask_rt, maskUv).r;
    ALBEDO = base_color.rgb;
    ALPHA = step(clip_threshold, mask);
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
```

必须同时满足：

| 项 | 结论 |
|---|---|
| 屏幕坐标 | 用引擎 `SCREEN_UV`，不要手投 `PROJECTION * VIEW * MODEL` |
| Y 轴 | `SCREEN_UV` 原点在左上，RT 纹理原点在左下，采样必须 `1.0 - uv.y` |
| clip | `ALPHA = step(threshold, mask)`，阈值固定 0.5。不要让 `ALPHA` 恒为 1 再靠阈值=1 |
| 深度 | clip 材质强制 `base` pass：`BLEND_REPLACE` + `depthWrite=true` |
| 屏幕纹理 | 调试 `SCREEN_UV` 时可以加 `hint_screen_texture`；正式 clip **必须删掉**，否则会把地面/天空喂回材质并冲白 |
| 体素色 | 实验室体素 clip 不要再 `pow(2.2)`。那条补偿是关卡 Unlit 对齐 Inspector 用的，叠在屏幕反馈上会爆白 |

Lua 侧：

```lua
material:SetSurfaceShader("Shaders/BLGL/AlgernonRtClip.shader")
material:SetShaderParameter("base_color", Variant(slotColor))
material:SetSurfaceTexture("mask_rt", rtTexture)
-- Material 没有 GetShaderParameter，槽色从资产 SlotLook 读。
```

格式查询是类静态方法：

```lua
Graphics:GetRGBAFormat()
Graphics:GetDepthStencilFormat()
```

`graphics:GetRGBAFormat()` 会报：`argument #1 is 'Graphics'; 'Graphics' expected.`

## 实验路径

实验室：`scripts/StencilRtLab.lua`  
自由相机：WASD 水平飞跃，右键观察，Space / C 升降。  
右下角 `BorderImage` 显示 RT，作为对照。

### 1. 硬件 stencil 不可用

绑定里没有物体级 stencil setter。能清缓冲，不能按物体写 ref。

### 2. 离屏 RT 可以先于世界更新

正确做法是 RT 挂 `RenderSurface`，不要占屏幕 Viewport 0。  
屏幕槽 0 放 RT 时，用户先看到整屏黑底白片。

### 3. 模具可以只进 RT

面片 `viewMask = MASK_BIT`，主画面看不见；RT 里是白剪影。  
Skybox / 雾色 Clear 不锁的话，RT 背景会变成天空蓝，不是黑。

### 4. 手投矩阵不是屏幕 UV

```glsl
clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
uv = ndc * 0.5 + 0.5;
```

Preview 结果：`(0,0)` 粘在老鼠身上，转相机 UV 跟着模型转。那是物体空间，不是屏幕空间。

### 5. `SCREEN_UV` 可用，但要 hint 打开，正式采样要翻 Y

调试：`hint_screen_texture` + `ALBEDO = vec3(SCREEN_UV, 0)`。  
画面上红绿交界贴在屏幕上，转相机时老鼠穿过色场。屏幕坐标成立。

采样直显时白块上下翻转。修法：

```glsl
vec2 maskUv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
```

翻转后白块和右下角 RT 对齐。

### 6. clip 比较必须让 ALPHA 真正变成 0

失败写法：`ALPHA = 1.0` 且黑区阈值也是 1，`1 < 1` 为假，整只老鼠都在。  
成功写法：`ALPHA = step(0.5, mask)`。

背面眼睛/耳朵 top-most：clip 材质进了不写深度的 pass。强制 `base` + `depthWrite=true` 后身体重新挡住五官。

### 7. 红 / 绿双通道成立

| 模具 | RT 写入 | 读取者 |
|---|---|---|
| 前方面片 | 红 `(1,0,0)` | 阿尔吉侬采 `.r` |
| 侧方面片 | 绿 `(0,0,1)` 的邻接竖直片 | 体素立方体采 `.g` |

两片组成 L。重叠时 RT 变黄，主画面里老鼠和立方体分界叠在一起。几何错开 + Replace 后，通道分开。

### 8. `hint_screen_texture` 会冲白地面

体素 clip 加了屏幕探针后，整片地变成刺眼白。地面颜色和雾都没改，是屏幕颜色反馈。  
去掉 `hint_screen_texture` 和体素 `pow(2.2)` 后，地面回到实验成功时的浅黄。

不要把「地面变白」先怪到雾距离或地面 hex。先查有没有新 shader 在读屏幕。

## 验收清单

已在 Preview 确认：

- [x] 主画面看不见模具面片
- [x] 右下角 RT 是黑底 + 模具色
- [x] 阿尔吉侬只出现在红通道覆盖处，槽颜色保留
- [x] 体素立方体只出现在绿通道覆盖处，分面色可读
- [x] 转相机时裁切跟着屏幕模具走，不贴模型 UV
- [x] 地面不再被 clip shader 冲白
- [x] L 形接缝不再叠成黄

未做：

- [ ] 正交固定游戏相机下的对齐
- [ ] 旋转机关动画中途更新 RT
- [ ] 半透明模具
- [ ] 把这条链路接进正式关卡或 Path Graph

## 以后不要再走的弯路

1. 猜 `markToStencil` 当物体模具。
2. 把 RT Viewport 塞进 `renderer` 槽 0。
3. 用手投 `PROJECTION * VIEW * MODEL` 当屏幕 UV。
4. 用 `graphics:GetRGBAFormat()` 这种实例静态调用。
5. 从 `Material:GetShaderParameter` 回读槽色。
6. 正式 clip 里留着 `hint_screen_texture` 探针。
7. 两片模具靠 Additive 叠通道。
8. 为了“地面太亮”去改雾，却不先看新 shader 有没有读屏幕。

## 对玩法的边界

这条链路只证明：**表现层可以用屏幕覆盖图裁物体。**

它不能：

- 定义 Path Graph 连接；
- 替代固定相机下的视觉接缝评估；
- 当作关卡数据真相源。

错视连接仍只由关卡配置、机关 Snap 和固定游戏相机评估生成。shader clip 是洞，不是路。

## 关键文件

| 文件 | 职责 |
|---|---|
| `scripts/StencilRtLab.lua` | 隔离实验室 |
| `scripts/main.lua` | 实验分支临时入口 |
| `assets/Shaders/BLGL/AlgernonRtClip.shader` | 阿尔吉侬认红通道 |
| `assets/Shaders/BLGL/VoxelRtClip.shader` | 体素立方体认绿通道 |

## 最终原则

```text
先证明屏幕 UV
  → 再证明 RT 采样对齐（含 Y 翻转）
  → 再让 ALPHA 真正变成 0
  → 最后才分通道

模具只进 RT，世界只进主视口。
shader 可以挖洞，不能定义道路。
```
