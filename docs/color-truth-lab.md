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

## 四盒对照（2026-08-28 第二轮）

档 1 画面：左上 raw SS、右上内置 Unlit、左下 `pow(2.2)`、右下当时是 `pow(1/2.2)`。

| 位置 | 档 1 | 档 4 |
|---|---|---|
| UI 色块 | 正红 `#F44336` | 同左 |
| 左上 raw SS | 中等饱和粉红 | 比档 1 稍饱和，仍粉 |
| 右上 NoTextureUnlit | 与左上同档惨白 | 同左上 |
| 左下 `pow(color, 2.2)` | **最接近 UI 红** | 仍接近，略更饱和 |
| 右下 `pow(color, 1/2.2)` | 最白 | 仍最白 |

结论：

- 冲白是 **整条 3D Unlit 输出**，不是 Surface Shader 独有。内置 `NoTextureUnlit` 和 raw SS 一样粉。
- 方向是 **sRGB 数字被当线性 ALBEDO 写出，显示时再当 sRGB 编码**。补偿是 `ALBEDO = pow(srgb, 2.2)`，不是 `pow(srgb, 1/2.2)`。
- 分面色应在 Inspector 的 sRGB 里 mix，最后一步再 `pow(2.2)`。不要先转线性再 mix，除非后续证明 `source_color` 已经是线性。

稳定写出：

```glsl
ALBEDO = pow(max(color, vec3(0.0)), vec3(2.2));
```

`color` 是 Inspector hex 对应的 0–1 值。

## 未闭合

像素拾取仍未做。`source_color` 是否已把 hex 转成线性未单独证明；四盒里 raw 与 `source_color` 第一轮无差别，所以当前按「Lua Color 已是 sRGB 0–1」处理。

冲白发生在 **Unlit ALBEDO 写出之后、UI 合成之前**。业务侧补偿已验证：`pow(srgb, 2.2)`。引擎内部是缺 sRGB framebuffer 还是把 ALBEDO 当线性，未读源码。

仍未做：像素拾取；关卡雾叠在 `pow(2.2)` 之后会不会再次掺色。

## 对关卡的含义

- Inspector 色板走 NanoVG sRGB。体素 Unlit 必须在写出前 `pow(2.2)`，否则色板和体素对不上。
- 只关 HDR、只关雾、只删 `source_color` 都不够。
- 内置 `NoTextureUnlit` 同样漂白，换 Technique 解决不了。
- 正式 `TriPrismLook.shader` 在 sRGB 里 mix 分面色，最后 `pow(2.2)`。
