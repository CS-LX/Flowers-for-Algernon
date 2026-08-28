# Unlit 真实 RGB / 雾 / HDR / Tonemap 实验记录

## 文档定位

实验分支：`experiment/true-rgb-color-pipeline`  
隔离场景：`scripts/ColorTruthLab.lua`  
入口已切离关卡编辑器。不加载 LightGroup，脚本自建 Zone，开关雾、HDR、`tonemapMode`。

目标色 `#F44336`（Inspector / NanoVG 色块）。对照三路：

| 位置 | 路径 |
|---|---|
| 左上 UI 色块 | NanoVG `backgroundColor = {244, 67, 54}` |
| 中盒 | Unlit Surface Shader + `uniform vec4 base_color : source_color` |
| 右盒 | Unlit Surface Shader + `uniform vec4 base_color`（无 `source_color`） |

证据等级：Preview 画面。未读引擎源码，未做像素拾取。

## 预设

| 键 | 设定 |
|---|---|
| 1 基线 | 无雾，`hdrRendering=false`，`TONEMAP_MODE_NONE`，fogStart=1000 density=0 |
| 2 亮蓝雾 | fogColor `#1F94F3`，start=8，finish=42，density=0.85（关卡截图同款） |
| 3 雾推远 | 同亮蓝雾色，start=1000，density=0 |
| 4 HDR 开 | 无雾，`hdrRendering=true`，`TONEMAP_MODE_NONE` |
| 5 ACES | 无雾，`hdrRendering=true`，`TONEMAP_MODE_ACES` |

Bloom / Vignette / AutoExposure / LUT / SSR / SSGI / MotionBlur / FXAA / volumetricFog 全部关闭。

## Preview 结果（2026-08-28）

截图：

- 档 1：`_uploads/bb40fbb950e4ef9fc2ce69f7f85732ac304e7b487bb7510c9990f3e8311484b7.jpg`
- 档 4：`_uploads/8db981fed54a0fd45406ac35fe73c949327acd613bf4df99ca498642886f3e7b.jpg`

观察：

| 档 | 中盒 / 右盒相对 UI 色块 | 中 vs 右 |
|---|---|---|
| 1 基线 | 惨白粉红，饱和度明显掉 | 看不出差别 |
| 2 亮蓝雾 | 与 1 基本一致，惨白 | 看不出差别 |
| 3 雾推远 | 与 1/2 基本一致 | 看不出差别 |
| 4 HDR + NONE | 比 1/2/3/5 更饱和，仍偏白，对不上 `#F44336` | 看不出差别 |
| 5 HDR + ACES | 与 1/2/3 基本一致，惨白 | 看不出差别 |

UI 色块始终是正红。两个 3D 盒子始终比 UI 浅、粉。

## 已排除

1. **雾不是这一轮冲白的主因。** 档 1 无雾已经惨白；档 2 与档 1 几乎一样。关卡编辑器里亮蓝雾仍可能再掺一层，但隔离场景里关掉雾并不能回到 UI 红。
2. **`source_color` 不是这一轮冲白的主因。** 中盒（有 hint）和右盒（无 hint）在所有档都一样。
3. **关 HDR 不能拿到真 RGB。** 档 1 就是关 HDR + `TONEMAP_NONE`，仍然惨白。
4. **ACES 不是唯一漂白源。** 档 5 和档 1 接近；档 4（HDR 开、NONE）反而更饱和。说明默认 LDR 路径和 ACES 都会压饱和，HDR+NONE 少压一档，但仍不是直出。

## 未闭合

冲白发生在 **Unlit ALBEDO 写出之后、UI 合成之前** 的 3D 路径上。候选且本轮没拆开：

| 候选 | 为何还没排除 |
|---|---|
| Surface Shader Unlit 默认当线性色写出，framebuffer 当 sRGB 显示（或反过来） | 无雾基线就白，符合“线性当 sRGB 显示”的观感；未做 `pow(c, 1/2.2)` 对照 |
| 引擎默认 Zone / Renderer 仍有未文档化的色调或 sRGB 帧缓冲 | 自建 Zone + `TONEMAP_NONE` 仍白 |
| 内置 `NoTextureUnlit` 是否同样漂白 | 本轮只有 Surface Shader 两盒，没有内置 Technique 对照 |
| 手机浏览器 / WASM 预览合成 | 未在桌面和像素拾取下复核 |

## 对关卡的含义

- Inspector 色板走 NanoVG，体素走 3D Unlit。两边现在不是同一条颜色空间。
- 只关 `hdrRendering`、只关雾、只删 `source_color`，都不足以让体素等于色板。
- 档 4 相对最接近，但仍不是真 RGB。不要把 HDR+NONE 当成已验收方案。

## 下一轮最小对照

1. 第三盒改走 `Techniques/NoTextureUnlit.xml` + `MatDiffColor`。若它和 UI 对齐、Surface Shader 仍白 → 问题在 Surface Shader Unlit。若三盒一起白 → 整条 3D 输出。
2. 在 shader 里写 `ALBEDO = pow(base_color.rgb, vec3(1.0/2.2))` 或 `pow(..., 2.2)`。哪边对齐 UI，就确定是 gamma 方向。
3. 像素拾取 UI 色块和盒子中心，不要只靠观感。
