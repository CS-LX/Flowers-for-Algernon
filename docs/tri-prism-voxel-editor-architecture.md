# 三棱柱体素编辑器架构计划

## 目标

基于 `docs/voxel-spec.md` 的三棱柱体素规范，构建一个真正可用的地编编辑器，而不是把立方体体素编辑器的表面功能拼接到三棱柱模型上。

核心目标是：

```text
用户可以像使用成熟体素编辑器或建模软件一样
可靠地创建、选择、修改、撤销、保存和继续编辑三棱柱地形。
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
TriPrismVoxelEditor
│
├── EditorDocument       文档、材质、图层、版本、JSON
├── TriPrismGrid         三棱柱网格、拓扑、拾取、坐标转换
├── EditorContext        当前帧编辑上下文
├── Modifier             工具总协调器
├── Brush                工具行为和生命周期
├── Preview              临时编辑结果
├── Selection            选择集和选择策略
├── History              命令、撤销、重做
├── Viewport             视口输入和射线
├── EditorCamera         旋转、平移、缩放、投影
├── SceneRenderer        三棱柱、预览、选中态、网格
├── EditorUI             Yoga UI 面板和工具栏
└── RuntimeExporter      编辑文档到游戏关卡数据
```

## 模块职责

### 1. `EditorDocument`

唯一的数据真相源，负责：

- 三棱柱体素记录；
- 材质和调色板；
- 图层；
- 关卡元数据；
- 文档版本；
- JSON 保存和加载；
- 脏状态；
- 文档重建。

场景节点永远是派生显示结果：

```text
EditorDocument = 真相源
SceneNode / Mesh = 派生结果
```

### 2. `TriPrismGrid`

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

### 3. `EditorContext`

类似 Vengi 的 `BrushContext`，集中保存当前编辑帧上下文：

```lua
{
    tool = ...,
    modifier = ...,
    ray = ...,
    hitCell = ...,
    hitFace = ...,
    hitNormal = ...,
    placementCell = ...,
    cursorCell = ...,
    activeLayer = ...,
    gridResolution = ...,
    lockedAxis = ...,
    selection = ...,
    projection = ...,
    isDragging = ...,
    isPreviewing = ...,
}
```

工具不直接到处读取输入、相机和文档，而是消费统一上下文。

### 4. `Modifier`

负责：

- 当前工具；
- 当前操作语义；
- 工具切换；
- Place / Erase / Paint / Pick；
- 按下、拖动、释放；
- 提交、取消；
- 快捷键；
- UI 输入和场景输入优先级。

建议将工具形状与操作语义分离：

```text
BrushType:
    Brush / Shape / Select / Fill / Transform / Extrude

ModifierType:
    Place / Erase / Paint / Pick
```

### 5. `Brush`

所有工具统一生命周期：

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

工具只产生变化描述，不直接创建 Node：

```lua
VoxelChanges = {
    { key = "...", before = oldCell, after = newCell },
}
```

首批工具：

```text
Brush
Erase
Shape
Select
Fill
Transform
Picker
```

后续工具：

```text
Extrude
Line
Mirror
Stamp
Lasso
```

### 6. `Preview`

严格区分：

```text
CommittedDocument
PendingEdit
PreviewScene
```

拖拽流程：

```text
按下
  -> 保存起点
  -> 生成 pending changes
  -> 根据鼠标更新 pending changes
  -> 只更新预览
  -> 松开
  -> 提交整个操作
  -> 写入 History
```

预览必须表达：

- 将要放置；
- 将要删除；
- 非法位置；
- 重叠；
- 超出范围；
- 笔刷范围；
- 选择范围；
- 变换结果。

### 7. `Selection`

使用策略模式，将选择交互和选择算法分离：

```text
Single
Box
Lasso
Connected
Surface
SameMaterial
Layer
All
PaintSelection
```

选择策略只返回 `SelectionSet`，不直接修改文档。

### 8. `History`

命令边界：

```text
BeginCommand
AccumulateChanges
CommitCommand
CancelCommand
Undo
Redo
```

一整次拖拽、框选移动、复制、旋转、镜像都应是一次撤销命令。

### 9. `Viewport` 与 `EditorCamera`

负责：

- 视口输入；
- 鼠标位置；
- 相机旋转、平移、缩放；
- 正交/透视切换；
- 顶视、前视、侧视；
- 聚焦选中对象；
- 重置视图；
- 射线生成和拾取。

项目规范保持不变：

```text
正交 30° 相机是游戏地编基准
透视模式只作为编辑辅助视图
```

### 10. `EditorUI`

使用 UrhoX Yoga UI 实现：

```text
顶部工具栏
左侧工具面板
右侧属性面板
图层面板
材质/调色板
文件菜单
视图控制
底部状态栏
```

UI 只调用编辑器服务：

```lua
editor:SetTool(...)
editor:SetModifier(...)
editor:Undo()
editor:Redo()
editor:Save()
editor:Load()
```

UI 不直接修改文档或场景节点。

### 11. `SceneRenderer`

只负责：

- 三棱柱渲染；
- 临时预览；
- 选择高亮；
- 网格辅助线；
- 命中面高亮；
- 材质颜色；
- 可见面；
- dirty region 更新；
- 后续 Chunk Mesh。

不负责输入、邻接和编辑规则。

### 12. `RuntimeExporter`

将编辑器文档转换为游戏关卡数据：

```text
EditorDocument
  -> RuntimeLevelData
```

运行时数据可以包含：

- 游戏体素；
- 逻辑网格；
- 可通行图；
- 机关；
- 错视连接；
- 关卡实体。

编辑器和游戏运行时保持解耦。

## 数据流

```text
鼠标输入
  ↓
Viewport / EditorCamera
  ↓
TriPrismGrid Raycast
  ↓
EditorContext
  ↓
Modifier
  ↓
Brush
  ↓
PreviewChanges
  ↓
用户释放
  ↓
Command / History
  ↓
EditorDocument
  ↓
SceneRenderer
  ↓
JSON 保存 / Runtime 导出
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

### 阶段一：三棱柱核心

- 固定三棱柱单元定义；
- 完成无缝铺砌坐标；
- 完成五面邻接；
- 完成三棱柱射线拾取；
- 完成几何占据和重叠验证；
- 用测试数据验证无缝、无重叠。

### 阶段二：编辑器内核

- 实现 `EditorContext`；
- 实现 `Modifier`；
- 实现 Brush 生命周期；
- 实现 Preview 与 Commit 分离；
- 实现 Command History。

### 阶段三：基础工具

- Brush；
- Erase；
- Select；
- Shape；
- Fill；
- Picker。

### 阶段四：建模工具

- Box Select；
- Copy/Paste；
- Move；
- Rotate；
- Mirror；
- Extrude；
- Lasso。

### 阶段五：编辑器工作流

- 图层；
- 材质面板；
- 属性面板；
- 正交/透视视图；
- 顶/前/侧视图；
- 保存/加载；
- 文档恢复；
- Runtime 导出。

### 阶段六：渲染优化

- 可见面剔除；
- dirty region；
- Chunk Mesh；
- 材质批处理；
- 大场景性能验证。

## 验收标准

编辑器至少应形成以下闭环：

```text
新建文档
  -> 选择工具
  -> 稳定 hover
  -> 三棱柱单元吸附
  -> 预览合法性
  -> 拖拽编辑
  -> 一次提交
  -> 撤销/重做
  -> 保存 JSON
  -> 加载 JSON
  -> 结果一致
```

并且必须满足：

- 三棱柱严格符合 `docs/voxel-spec.md`；
- 不出现逻辑不重叠但几何重叠；
- 不把透视相机当作游戏基准；
- 不让 UI、Node 或浮点位置成为数据真相源；
- 不在不同模块重复实现三棱柱拓扑；
- 不把三个参考项目的实现混合成四不像。
