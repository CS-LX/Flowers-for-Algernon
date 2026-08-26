# OverlayViewManager 正式执行方案

## 落地状态

职责分离已闭环：`OverlayViewManager` 拥有 Overlay Viewport；`PlayerController` 不持有 Drawable；编辑器 Gizmo 仍走 Editor Overlay。角色置顶不再切 Preview Overlay 相机，改为主场景 `depth_test_disabled` Surface Shader + `SetRenderOrder(255)`，避免 Clone RenderPath 丢失 Tonemap。下文若仍写“玩家进入 Overlay Viewport”，以本节为准。

## 目标

建立唯一的 Overlay View 所有者，彻底隔离编辑器辅助 Overlay、Preview 玩家 Overlay 与角色逻辑 Model，避免多个模块抢占 Viewport、重复创建玩家 Drawable、重复绘制角色和光照链路不一致。

本方案当前阶段的玩家表现使用**纯色非光照材质**。不接入 PBR、LightGroup、Zone、阴影、Occlusion 或自研 Shader。自研 Shader 作为后续独立阶段，不改变 Model、PathRuntime 或 Viewport 所有权架构。

## 最终职责边界

```text
PlayerModel / PlayerController
  只负责位置、旋转、PathNode、BFS 路径、行走状态和 viewState

GamePreview
  只负责 Preview 主场景、点击目标、调用 BFS、更新 PlayerModel

OverlayViewManager
  唯一负责所有 Overlay Scene、Camera、Viewport 和 View 生命周期

EditorOverlayRenderer
  只负责编辑器 Grid、Gizmo、PathNode、Candidate、Selection 的几何表现

PlayerView
  只负责玩家模型、纯色材质和自身表现节点
```

禁止以下依赖：

- `PlayerModel` 创建 `Node`、`Component`、`Material` 或 `Viewport`。
- `GamePreview` 创建或销毁 Overlay Scene、Overlay Camera 或 Overlay Viewport。
- `LevelEditor` 直接调用 `renderer:SetViewport` 或 `renderer:SetNumViewports` 管理 Overlay。
- `EditorOverlayRenderer` 创建或管理玩家 View。
- 玩家 View 反向修改 PathRuntime、BFS 或关卡数据。

## Viewport 拓扑

### 编辑器模式

```text
Viewport 0: MainEditorViewport
  Level Editor 主场景

Viewport 1: EditorOverlayViewport
  Grid / Gizmo / PathNode / Candidate / Selection
```

### Preview 模式

```text
Viewport 0: MainPreviewViewport
  Preview 关卡主场景

Viewport 1: PreviewOverlayViewport
  Preview 专用 Overlay 内容
```

Preview Overlay 与 Editor Overlay 必须是两个独立的 Overlay Layer，但由同一个 `OverlayViewManager` 统一创建、绑定、切换和清理。业务模块不得各自创建 Viewport。

`PreviewOverlayViewport` 继续服务 Preview 辅助 Overlay。玩家角色始终留在主场景：

- 普通路径：`PlayerSolid.shader`，正常深度。
- 候选路径置顶：`PlayerSolidTopmost.shader`（`depth_test_disabled` + `depth_draw_never`）和 `SetRenderOrder(255)`。
- 颜色继续走主相机后处理，不因置顶切换 Overlay 相机。

## PlayerModel 接口

Model 不持有任何表现对象，只保存：

```text
position
rotation
currentNodeKey
targetKey
path
pathIndex
walking
currentEdgeIsCandidate
viewState
```

建议公开接口：

```lua
PlayerModel.New(pathRuntime, spawnNodeKey)
PlayerModel:Start()
PlayerModel:Stop()
PlayerModel:Update(timeStep)
PlayerModel:MoveTo(path, targetKey)
PlayerModel:IsWalking()
PlayerModel:GetCurrentNodeKey()
PlayerModel:GetPosition()
PlayerModel:GetRotation()
PlayerModel:GetViewState() -- "normal" / "topmost"
```

`viewState` 只由当前有效 Path Graph 的边类型决定：

```text
当前边为 local_fixed       -> normal
当前边为跨 Part candidate  -> topmost
```

寻路只消费 `PathRuntime` 的当前有效 Graph，不扫描 Scene、Mesh 或物理碰撞。

## OverlayViewManager 接口

`OverlayViewManager` 是唯一的 Overlay 所有者，负责：

```lua
OverlayViewManager.New()
OverlayViewManager:Start(mainViewport, mainCamera)
OverlayViewManager:EnterEditorMode(mainViewport, camera)
OverlayViewManager:EnterPreviewMode(mainViewport, camera)
OverlayViewManager:SyncCamera(camera)
OverlayViewManager:PresentEditorOverlay(editorData)
OverlayViewManager:PresentPlayer(playerModel)
OverlayViewManager:ClearPlayer()
OverlayViewManager:ClearEditorOverlay()
OverlayViewManager:Stop()
```

调用者只提交数据和状态，不直接操作 Scene/Viewport。

## PlayerView 生命周期

第一版不使用两个玩家 View 长期共存。状态切换必须保证同一时刻最多一个玩家 View/Drawable：

### normal -> topmost

```text
1. 从 PlayerController 读取 position / rotation。
2. 销毁当前 PlayerView。
3. 在 MainPreviewScene 重建唯一 PlayerView。
4. 绑定 PlayerSolidTopmost.shader，SetRenderOrder(255)。
```

### topmost -> normal

```text
1. 从 PlayerController 读取 position / rotation。
2. 销毁当前 PlayerView。
3. 在 MainPreviewScene 重建唯一 PlayerView。
4. 绑定普通 PlayerSolid.shader，恢复默认 RenderOrder。
```

不使用“两个角色同时存在再切换 `enabled`”作为唯一性保证。`enabled` 只能作为额外显示状态，不能替代 View 生命周期清理。

## PlayerView 材质

当前阶段统一使用纯色非光照材质：

```text
Technique: Techniques/NoTextureUnlit.xml
```

普通状态：

```text
DepthTest: 正常
DepthWrite: true
```

Topmost 状态：

```text
DepthTest: CMP_ALWAYS
DepthWrite: false
```

普通状态和 Topmost 状态使用同样的几何体、尺寸、颜色和姿态。两者唯一差异是渲染承载层和深度策略，不引入光照差异。

## EditorOverlayRenderer 重构边界

现有编辑器 Overlay 几何代码可以保留，但应从 Viewport 所有权中拆出：

```text
OverlayViewManager
  owns EditorOverlayScene / EditorOverlayCamera / EditorOverlayViewport
  calls EditorOverlayRenderer to rebuild geometry
```

`EditorOverlayRenderer` 不再负责：

- 创建 Overlay Scene。
- 创建 Overlay Camera。
- 创建 Overlay Viewport。
- 管理 renderer 的 Viewport 数量。
- 创建玩家 View。

## GamePreview 流程

```text
Start
  -> 校验出生点
  -> 创建 Preview 主场景和主相机
  -> 创建 PathRuntime
  -> 构建有效 Graph
  -> 创建 PlayerModel
  -> 请求 OverlayViewManager 进入 Preview 模式

Update
  -> 处理点击
  -> PlayerModel:Update(timeStep)
  -> OverlayViewManager:PresentPlayer(PlayerModel)

Stop
  -> 停止 PlayerModel
  -> OverlayViewManager:ClearPlayer()
  -> 清理 Preview 主场景
  -> 恢复 Editor 模式
```

## 分阶段实施与验收证据

### 阶段 1：Viewport 探针

只创建主场景体素和 PreviewOverlayViewport 中的纯色 Box，验证：

- Viewport 顺序正确。
- Overlay 不清主场景颜色。
- Overlay 内容可稳定出现在体素上方。
- Editor Overlay 与 Preview Overlay 不互相抢占。

### 阶段 2：单一 PlayerView

不接 BFS，只验证：

- normal 只存在 MainPreviewScene PlayerView。
- topmost 只存在 PreviewOverlayScene PlayerView。
- 多次 normal/topmost 切换不出现双角色。
- 多次进入/退出 Preview 不累积 Node/Drawable。
- Preview 退出后 Overlay 场景和玩家 View 完全清理。

### 阶段 3：接 PlayerModel 状态

把：

```text
PlayerModel:GetViewState()
```

接入 `OverlayViewManager:PresentPlayer()`，验证：

- 普通路径使用正常深度。
- 候选路径使用 Topmost。
- 候选边结束后恢复正常路径表现。

### 阶段 4：接真实 BFS 与点击

最后接入：

- 点击 PathNode。
- `PathRuntime:FindPath()`。
- PlayerModel 路径移动。
- 跨 Part 候选边状态。

每一阶段都必须分别验证 LSP、构建、真实像素和节点数量，不能用构建成功代替行为验证。

## 当前明确不做

- 不使用 PBR 或实时光照。
- 不使用 `SetViewOverrideFlags`。
- 不使用两个玩家实例长期共存。
- 不通过抬高世界坐标模拟置顶。
- 不把玩家 View 放进 EditorOverlayRenderer。
- 不让 GamePreview 直接管理 Overlay Viewport。
- 不使用 UI/NanoVG 替代 3D 玩家 View。
- 不在未完成 Viewport 探针前接完整角色功能。

## 验收标准

重构完成后必须满足：

```text
Overlay Viewport 的创建、销毁和顺序只有 OverlayViewManager 负责。
PlayerModel 不引用任何引擎表现类型。
EditorOverlayRenderer 不创建玩家对象。
GamePreview 不直接操作 Overlay Viewport。
正常路径最多一个玩家 Drawable。
候选路径最多一个玩家 Drawable。
正常路径允许体素遮挡玩家。
候选路径玩家仍在主场景，使用 depth_test_disabled 画在体素之上。
玩家普通和 Topmost 状态都使用纯色 Surface Shader，颜色走主相机后处理。
```
