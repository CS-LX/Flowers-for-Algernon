# 三棱柱体素编辑器架构计划

## 目标

基于 `docs/voxel-spec.md` 的三棱柱体素规范，构建一个真正可用的地编编辑器，而不是把立方体体素编辑器的表面功能拼接到三棱柱模型上。

核心目标是：

```text
用户可以像使用成熟体素编辑器或建模软件一样
可靠地创建、选择、修改、撤销、保存和继续编辑三棱柱地形。
```

## 当前架构定位

本计划已按 `docs/tri-prism-part-preview-workflow.md` 更新。

原先将 `EditorDocument` 视为整张关卡的全局体素文档；现在将已有体素编辑器定位为 **Part Voxel Editor**：它编辑一个 Part 的局部三棱柱源数据，而不是直接承担整张关卡的层级、机关与运行时状态。

```text
LevelDocument
  -> ObjectTreeEditor
  -> PartDefinition
  -> PartVoxelDocument
  -> 派生 Preview / Bake 结果
```

其中：

```text
PartVoxelDocument = 可编辑真相源
BakedMesh / Preview Node = 可销毁并重建的派生显示结果
```

## 参考项目的正交分工

三个参考项目只负责各自擅长的模块，不在同一个模块内混合实现，避免形成四不像。

### Vengi / VoxEdit：编辑器内核

参考职责：

- 工具总协调器 `Modifier`；
- Brush 生命周期；
- 工具类型与操作语义分离；
- 预览、执行、提交、取消；
- 连续拖拽；
- 多阶段工具；
- 脏区域与增量刷新；
- 选择策略；
- 撤销/重做边界；
- 图层和场景组织。

典型数据流：

```text
Modifier
  -> BrushContext
  -> Brush:Begin
  -> Brush:Update / Preview
  -> Brush:Execute
  -> Brush:Commit / Abort
  -> History
```

Vengi 只负责“编辑器如何工作”，不负责三棱柱几何，也不作为 UI 视觉参考。

### Goxel：编辑操作手感

参考职责：

- 画笔和橡皮擦；
- 半径和形状；
- 连续拖动；
- 低延迟预览；
- 临时编辑体积；
- 松开鼠标后一次提交；
- 颜色拾取；
- 直接的体素编辑反馈。

典型数据流：

```text
CommittedDocument
  + PendingEdit
  -> Preview
  -> PointerRelease
  -> CommitCommand
```

Goxel 只负责“编辑操作的手感”，不负责文档布局，也不直接提供三棱柱拓扑。

### VoxelShop：建模软件式工作流

参考职责：

- 视口和工具栏布局；
- 图层面板；
- 属性面板；
- 当前对象和当前层；
- 文件新建、打开、保存；
- 模型组织；
- 编辑状态反馈；
- 相机和视图控制面板。

VoxelShop 只负责“编辑器如何组织和呈现”，不负责 Brush 算法和三棱柱网格。

## 总体架构

```text
TriPrismMonumentLevel
│
├── LevelDocument        关卡真相源：Part、层级、机关、逻辑图、固定镜头
├── ObjectTreeEditor     场景树、Part 选择、Transform、行为配置、打开 Part
├── PartDefinition       一个可复用的局部建筑/机关组件定义
├── PartVoxelDocument    一个 Part 的局部体素真相源、材质、版本、JSON
├── TriPrismGrid         三棱柱局部网格、拓扑、拾取、坐标转换
├── EditorContext        当前 Part 编辑帧上下文
├── Modifier             Part 编辑工具总协调器
├── Brush                局部体素工具行为和生命周期
├── Preview              临时局部编辑结果
├── Selection            局部体素选择集和选择策略
├── History              Part 编辑命令、撤销、重做
├── PartViewport         Part 编辑视口输入和辅助相机
├── EditorCamera         Part 编辑相机：旋转、平移、缩放、投影
├── PartRenderer         局部体素、预览、选中态、网格辅助显示
├── EditorUI             Yoga UI：Object Tree 与 Part 编辑面板
├── PartBakeService      从局部体素生成可重建的 Part 显示缓存
├── PreviewScene         固定 30° 正交镜头下的 Part 运行时层级
├── LogicGraph           显式可通行节点、条件边与机关状态
└── RuntimeExporter      已验证关卡到游戏运行时数据的最终导出
```

### 核心数据边界

```text
LevelDocument
  ├── PartDefinition[]
  ├── hierarchy
  ├── mechanisms
  ├── LogicGraph
  └── fixedCamera

PartDefinition
  ├── localVoxelDocument
  ├── local Transform / parent
  ├── behavior
  └── bake metadata
```

关卡级 Part Transform 在 Preview 中作用于 `PartRoot`，而不是改写局部体素格子。

```lua
partRoot.position = runtimePosition
partRoot.rotation = Quaternion(rotationSteps * 60.0, Vector3.UP)
```

## 模块职责

### 1. `LevelDocument`

关卡级唯一真相源，负责：

- Part 定义、名称、父子层级与顺序；
- Part Transform 与行为参数；
- 固定游戏镜头；
- 机关状态定义；
- 显式 LogicGraph；
- 关卡元数据、版本与 JSON 持久化。

`LevelDocument` 不直接承担一个 Part 内部的三棱柱编辑细节。

### 2. `PartVoxelDocument`

原 `EditorDocument` 调整为一个 Part 的局部体素文档，负责：

- 局部三棱柱体素记录；
- 局部材质与调色板；
- 局部编辑历史所需版本数据；
- 局部 JSON 保存和加载；
- 局部源数据 dirty 状态。

场景节点和 Bake Mesh 永远是派生结果：

```text
PartVoxelDocument = 真相源
PartRoot / BakedMesh = 派生显示结果
```

### 3. `PartDefinition`

定义一个可移动、可复用的关卡物件。Part 不通过互斥类型表达行为，而是由 Transform、Transform 能力和可组合行为模式组成：

```text
- id / name
- parentId
- localVoxelDocument 引用
- Transform：position / rotation / scale
- transformCapabilities：move / rotate / scale
- behaviorModes[]
- behaviors{}
- bake metadata
```

概念示例：

```lua
{
    id = "part_rotator_tower",
    localVoxelPath = "parts/rotator-tower.json",
    transform = {
        position = { x = 0, y = 0, z = 0 },
        rotation = { yawSteps = 0, pitchSteps = 0, rollSteps = 0 },
        scale = { x = 1, y = 1, z = 1 },
    },
    transformCapabilities = { move = true, rotate = true, scale = false },
    behaviorModes = { "rotator", "triggerable" },
    behaviors = {
        rotator = { axis = "Y", stepDegrees = 60, state = 0 },
    },
}
```

`static` 不是 Part 类型，而是没有行为模式的普通 Part。`rotator`、`slider`、`elevator` 和 `triggerable` 是可组合行为。Gameplay Part 的 scale 字段保留，但初版由能力规则锁定为 `(1, 1, 1)`；装饰 Part 将来可以支持均匀缩放。

### 4. `TriPrismGrid`

项目专属核心，不能从立方体编辑器直接复制。唯一负责：

- 三棱柱离散坐标；
- 最密堆积/无缝铺砌规则；
- 三角形单元类型和朝向；
- 层级关系；
- 六向方向和规范旋转；
- 三棱柱五个面的定义；
- 面到邻居的映射；
- 世界坐标与网格坐标转换；
- 三棱柱射线拾取；
- 合法性和重叠检测；
- 三棱柱几何和 Mesh 顶点生成。

其他模块不得自行推导三棱柱邻居或坐标。

统一接口方向：

```lua
grid:GetNeighbor(cell, face)
grid:GetPlacementCell(hit)
grid:TransformCell(cell, transform)
grid:Raycast(ray)
grid:IsValid(cell)
```

### 5. `EditorContext`

类似 Vengi 的 `BrushContext`，集中保存当前 **Part Voxel Editor** 的编辑帧上下文：

```lua
{
    tool = ...,
    modifier = ...,
    ray = ...,
    hitCell = ...,
    hitFace = ...,
    placementCell = ...,
    cursorCell = ...,
    activeLayer = ...,
    selection = ...,
    projection = ...,
    isDragging = ...,
    isPreviewing = ...,
}
```

工具不直接到处读取输入、相机和局部体素文档，而是消费统一上下文。

### 6. `Modifier` 与 `Brush`

负责 Part 内部体素编辑的工具生命周期：

```text
BrushType:
    Brush / Shape / Select / Fill / Transform / Extrude

ModifierType:
    Place / Erase / Paint / Pick
```

统一生命周期：

```lua
tool:Activate(context)
tool:Begin(context)
tool:Update(context, dt)
tool:Preview(context)
tool:Execute(context)
tool:End(context)
tool:Commit(context)
tool:Abort(context)
tool:Deactivate(context)
```

工具只产生局部变化描述，不直接创建 Node：

```lua
VoxelChanges = {
    { key = "...", before = oldCell, after = newCell },
}
```

### 7. `PendingEdit`、`Selection` 与 `History`

严格区分 Part 内部编辑状态：

```text
PartVoxelDocument
PendingEdit
SelectionSet
History
PartRenderer
```

- `PendingEdit` 只保存拖拽、放置、删除等尚未提交的局部变化；
- `Selection` 使用 Single、Box、Connected、Surface、SameMaterial、Layer、All 等策略，只返回集合；
- `History` 的命令边界是一次笔刷拖拽、一次框选变换、一次复制或一次镜像；
- 所有提交都更新局部体素源数据，而不是直接修改 Preview Scene。

### 8. `PartViewport` 与 `EditorCamera`

负责 Part 编辑模式的辅助相机：

```text
- 视口输入、鼠标位置、射线生成
- 相机旋转、平移、缩放
- 正交/透视切换
- 局部网格拾取
- 聚焦当前 Part
```

Part 编辑相机可以自由观察；它不是游戏镜头。

### 9. `ObjectTreeEditor` 与 `EditorUI`

`ObjectTreeEditor` 负责关卡总装工作流：

```text
- Hierarchy：Part 创建、选择、复制、删除、父子关系
- Inspector：Part 名称、类型、Transform、行为参数
- Open Part：进入 Part Voxel Editor
- Back to Level：保存局部源数据并请求重新 Bake
```

`EditorUI` 使用 Yoga UI 实现 Object Tree、Part 编辑工具栏、Inspector 与状态栏。

UI 只调用编辑器服务：

```lua
editor:OpenPart(partId)
editor:SavePart()
editor:SetPartTransform(...)
editor:SetTool(...)
editor:Undo()
editor:Redo()
```

UI 不直接修改局部体素文档、LevelDocument 或场景节点。

### 10. `PartRenderer` 与 `PartBakeService`

`PartRenderer` 只负责局部体素编辑显示：

```text
- 局部三棱柱渲染
- PendingEdit 预览
- 选择高亮
- 网格与命中面辅助绘制
```

`PartBakeService` 将局部体素源数据转为可重建的 Part 显示缓存：

```text
PartVoxelDocument dirty
  -> BakePartMesh(part)
  -> 替换 PartRoot 下的派生显示结果
```

初版允许将每个局部体素节点挂在 `PartRoot` 下，先验证层级与机关；合并 Mesh、可见面剔除和材质批处理后置。

### 11. `PreviewScene`

Preview 是游戏规则验证环境，不是编辑器视口的另一个相机模式。

它负责：

```text
- 固定 30° 正交游戏镜头
- 从 LevelDocument 构建 PartRoot 层级
- 加载 Part Bake 结果
- 执行 Rotator 等离散机关状态
- 显示 LogicGraph、条件边和错视连接 Debug
```

固定镜头下，Part 的状态变化只更新 `PartRoot` Transform；局部体素源数据保持不变。

### 12. `LogicGraph` 与 `RuntimeExporter`

`LogicGraph` 保存显式可通行节点与条件边：

```text
视觉重合 != 自动可通行
Mechanism State -> Conditional Edge -> Walkability
```

`RuntimeExporter` 只导出已经在 Preview 中验证过的关卡数据：

```text
LevelDocument
  -> RuntimeLevelData
```

运行时数据包含 Part、逻辑图、机关、错视连接和关卡实体；编辑器与游戏运行时保持解耦。

## 数据流

### Part 局部编辑

```text
鼠标输入
  ↓
PartViewport / EditorCamera
  ↓
TriPrismGrid Raycast
  ↓
EditorContext
  ↓
Modifier / Brush
  ↓
PendingEdit / Selection Preview
  ↓
用户释放
  ↓
History
  ↓
PartVoxelDocument
  ↓
PartRenderer / BakePartMesh
```

### 关卡总装与游戏预览

```text
ObjectTreeEditor
  ↓
LevelDocument / PartDefinition
  ↓
PartRoot Hierarchy
  ↓
PreviewScene 固定 30° 正交相机
  ↓
Mechanism State
  ↓
LogicGraph Conditional Edges
  ↓
角色寻路与关卡验证
```

## 避免四不像的硬规则

1. 一个模块只采用一个参考项目的职责：
   - Vengi：编辑器内核；
   - Goxel：笔刷手感；
   - VoxelShop：桌面工作流；
   - 当前项目：三棱柱拓扑。

2. 参考项目只提供行为和架构参考，不直接提供三棱柱数据模型。

3. 工具不允许直接改场景，必须产出预览变化或提交变化。

4. 预览、正式文档和撤销历史必须分离。

5. UI 不能成为逻辑中心，只能调用编辑器服务。

6. 三棱柱拓扑只能在 `TriPrismGrid` 中实现，所有工具统一调用它。

7. 只复制用户可感知的行为：拖拽、预览、选择、提交、撤销、保存和相机手感，不复制无关的 C++、C 或 Java 内存结构。

## 实施顺序

### 阶段一：三棱柱核心（已完成）

- 固定三棱柱单元定义；
- 完成无缝铺砌坐标；
- 完成五面邻接；
- 完成三棱柱射线拾取；
- 用测试数据验证无缝、无重叠。

### 阶段二：Part Voxel Editor 内核（大部分已完成）

- `EditorContext`、`Modifier`、Brush 生命周期；
- PendingEdit 与 Commit 分离；
- Part 局部 History；
- 笔刷、擦除、选择、填充、吸管；
- 框选、选择策略与 EditorUI；
- 局部 JSON 保存和加载。

已有体素编辑器在此阶段正式定位为 `Part Voxel Editor`，不再继续扩展为单一全局关卡文档。

### 阶段三：LevelDocument 与 Part 数据模型

- `LevelDocument` JSON；
- `PartDefinition`：id、名称、parentId、局部体素引用；
- 统一 Transform：position、rotation、scale；
- Transform 能力：move、rotate、scale；
- 可组合 `behaviorModes` 与 `behaviors`；
- Static 不再作为互斥 Part 类型；
- Rotator 作为第一种可组合行为；
- Part 所有权与局部体素资源路径；
- 固定 30° 正交游戏镜头配置。

Gameplay Part 初版 scale 保持单位值并禁用缩放编辑；装饰 Part 后续可支持均匀缩放。

### 阶段四：Object Tree Editor

- Hierarchy 面板；
- 创建、选择、复制、删除 Part；
- 父子层级；
- Part Inspector；
- 平移与 60° 离散旋转；
- Open Part / Back to Level 工作流。

可动 Gameplay Part 初版不支持缩放；错视连接 Part 必须保持 `scale = (1, 1, 1)`。

### 阶段五：Part 派生显示与初版 Preview

- 为每个 Part 创建 `PartRoot`；
- 将局部体素派生显示结果挂到 `PartRoot`；
- dirty Part 重新生成派生结果；
- PreviewScene 固定 30° 正交镜头；
- Rotator Part 每次绕 Y 轴旋转 60°；
- 编辑器相机与游戏 Preview 相机严格分离。

初版可以逐体素显示，不以最终合并 Mesh 为前置条件。

### 阶段六：LogicGraph 与角色路径验证

- Walk Node；
- Conditional Edge；
- 机关状态到逻辑边的映射；
- 图 Debug；
- 小角色寻路；
- Rotator 状态变化后更新可通行路径；
- 验证视觉错视与逻辑连通分离。

### 阶段七：更多机关组件

- Slider；
- Elevator；
- Trigger；
- 组件父子联动；
- 机关状态持久化。

### 阶段八：Bake 优化与 Runtime Export

- 按 Part 合并 Mesh；
- 可见面剔除；
- dirty Part 增量重烘焙；
- 材质批处理；
- 已验证 LevelDocument 到 RuntimeLevelData 导出；
- 大场景性能验证。

## 验收标准

### Part Voxel Editor 闭环

```text
打开一个 Part
  -> 三棱柱局部网格吸附
  -> 笔刷/擦除/框选/选择策略
  -> 一次拖拽一次提交
  -> 撤销/重做
  -> 保存局部 JSON
  -> 加载后结果一致
```

### 首个纪念碑谷式 Part / Preview 闭环

```text
在 Object Tree 创建 Rotator Part
  -> Open Part
  -> 用三棱柱体素搭出一座塔
  -> Save / Bake / Back to Level
  -> Preview 固定 30° 正交镜头
  -> 操作 Rotator 旋转 60°
  -> Preview 中 PartRoot 绕自身 Pivot 旋转
  -> 局部体素源数据保持不变
  -> LogicGraph 显示对应状态下的条件连接
```

并且必须满足：

- 三棱柱局部网格严格符合 `docs/voxel-spec.md`；
- `PartVoxelDocument` 与 `LevelDocument` 都是数据真相源，Mesh 和 Node 都是派生结果；
- 不出现逻辑不重叠但几何重叠；
- 不把透视相机当作游戏基准；
- 游戏 Preview 固定使用 30° 正交镜头；
- 视觉重合不自动等于逻辑连通；
- 不让 UI、Node 或浮点位置成为体素和逻辑数据真相源；
- 不在不同模块重复实现三棱柱拓扑；
- 可动 Gameplay Part 初版不允许缩放；
- 不把三个参考项目的实现混合成四不像。
