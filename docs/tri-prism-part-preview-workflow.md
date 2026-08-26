# 三棱柱体素关卡 Part 与预览工作流

## 落地状态

工作流已闭环。Level Object Tree、Part 局部编辑、Editor Camera 与 Game Preview 固定相机分离、Preview 旋转塔拖动-Snap、点击/拖动手势分流、角色跟随可动 Part，均已按本文实现。Mesh Bake 仍未做，不影响当前白盒工作流。


## 目标

在保持三棱柱体素编辑精度与六边形错视基准的前提下，建立类似 Unity 的关卡物体树工作流：

```text
Level Object Tree
  -> Part
    -> 局部体素编辑
    -> 非破坏性 Mesh Bake
  -> Transform / Behavior
  -> 固定镜头 Preview
```

该工作流解决两个问题：

1. 不依赖外部建模软件，也能在 TapTap Maker 内搭建复杂的关卡建筑；
2. 避免单一全局体素世界无法自然表达平移、旋转、父子层级与机关组件的问题。

## 纪念碑谷式关卡原则

### 固定游戏镜头

游戏预览以固定的正交/轴测镜头为基准：

```text
projection = Orthographic
pitch = 30°
yaw = 30°
rotation = 固定的关卡设计角度
```

### 编辑预览相机与固定游戏镜头分离

Level Object Tree 的 **Editor Preview Camera** 用于总装检查，类似 Unity Scene View。它可以自由旋转、平移、缩放，并支持正交/透视切换：

```text
RMB 拖动：绕焦点旋转
MMB 拖动：沿屏幕平面平移
滚轮：缩放
投影按钮：正交 / 透视
聚焦：对焦当前选中 Part
重置：恢复固定 30° 正交基准
```

它的状态只属于 `LevelEditor` 的临时工作区状态：

```text
editorCamera = {
    projection,
    focus,
    yaw,
    pitch,
    distance,
    orthoSize,
    fov,
}
```

禁止 Editor Preview Camera 改写 `LevelDocument.fixedCamera`。后者仍然是后续 **Game Preview** 与运行时使用的固定 30° 正交镜头：

```text
Editor Preview Camera：自由观察，只服务编辑
Game Preview Camera：固定投影，只服务玩法验证
```

这两个相机可以共享同一个场景中的 Camera 节点，但不能共享或混淆状态数据。

### Game Preview 旋转塔

Game Preview 的旋转塔遵循纪念碑谷式拖动-Snap，不复用编辑器立刻改 Yaw 的逻辑：

```text
按下可动 Part
  -> 先进入 pending，不立即旋转也不立即寻路
拖过死区
  -> 确认为旋转手势，绕 Pivot Y 轴持续转动表现层
  -> Path Graph 保持上一份合法状态
原地松开
  -> 确认为点击手势，交给 PathNode 寻路
旋转松手
  -> Snap 到最近 allowedSteps * 60°
  -> 提交 rotator.state / yawSteps
  -> 再刷新当前有效 Path Graph

角色正在该可动 Part（或其子 Part）上走路
  -> 禁止开始拖动机关
角色静止站在该可动 Part（或其子 Part）的路径节点上
  -> 允许拖动该机关
  -> 拖动和 Snap 过程中角色相对 Part 静止并跟随 Transform
机关正在运动
  -> 角色不得开始新的走路
```

### 视觉连接与逻辑连接分离

```text
视觉重合 \!= 自动可通行
```

两个 Part 在固定镜头下看起来对齐，只是视觉评估输入。角色是否可通过，由当前有效 Path Graph 决定：

```text
关卡配置的跨 Part 候选
  + 机关合法 Snap 状态
  + 固定游戏相机下投影面边正长度重合
  -> CurrentEffectiveGraph
  -> 寻路
```

设计者配置候选范围，不手写每个 Snap 状态的错视边。显式条件边只作固定连接、白盒兜底或设计者覆盖。

## Part 是编辑与运行时边界

### 为什么不能只有全局体素文档

单一全局体素世界中的每一个单元都直接使用世界坐标：

```text
全局三棱柱体素
  -> 旋转需要重写全部格子坐标
  -> 平移需要重写全部格子坐标
  -> 缩放会破坏体素尺寸与网格对齐
  -> 动画需要持续修改正式文档
```

这不适合机关和可动建筑。

### Part 定义

每个 `Part` 是一个具有局部坐标系、局部体素源数据、Transform 和可组合能力的关卡物件，概念上类似 Unity 的 `GameObject / Prefab Instance`。

Part 不再通过 `static / rotator / slider` 等互斥类型描述，而是由四部分组成：

```text
Part
├── localVoxelPath
├── Transform
├── Pivot：origin / cell_center / custom（Rotator 默认 cell_center）
├── transformCapabilities
└── behaviorModes + behaviors
```

```lua
{
    id = "part_rotator_tower",
    name = "旋转塔",
    localVoxelPath = "parts/rotator-tower.json",

    transform = {
        position = { x = 0, y = 0, z = 0 },
        rotation = {
            yawSteps = 0,
            pitchSteps = 0,
            rollSteps = 0,
        },
        scale = { x = 1, y = 1, z = 1 },
    },

    transformCapabilities = {
        move = true,
        rotate = true,
        scale = false,
    },

    behaviorModes = { "rotator", "triggerable" },
    behaviors = {
        rotator = {
            axis = "Y",
            stepDegrees = 60,
            allowedSteps = { 0, 1, 2, 3, 4, 5 },
            state = 0,
            duration = 0.45,
        },
    },
}
```

`static` 不再是 Part 类型，而是没有行为模式的普通 Part。`rotator`、`slider`、`elevator` 和 `triggerable` 都是可以组合的行为模式。

## 双层编辑工作流

### 1. Object Tree / Level Editor

关卡总装层负责：

```text
- 创建、复制、删除 Part
- 物体树与父子层级
- 当前 Part 选择
- Part Transform
- Part 类型与机关参数
- 逻辑连接图
- 固定镜头 Preview
```

推荐层级：

```text
LevelRoot
├── StaticGeometry
│   ├── Part_Gate
│   └── Part_Stair
├── RotatorTower
├── MovingBridge
├── LogicGraph
└── FixedPreviewCamera
```

### 2. Part Voxel Editor

局部建模层复用现有三棱柱体素编辑器，负责：

```text
- 只编辑当前 Part 的 localVoxelDocument
- 使用局部三棱柱网格
- 放置、擦除、选择、变换局部体素
- 保存 Part 体素源数据
- 请求重新烘焙
- 返回 Object Tree
```

进入 Part 编辑模式相当于 Unity 的 Prefab Mode：

```text
Object Tree
  -> Open Part
  -> Part Voxel Editor
  -> Save / Bake
  -> Back to Object Tree
```

Part 编辑器不直接修改 Level 中其他 Part 的体素数据。

## 非破坏性烘焙

### 真相源规则

```text
Part.localVoxelDocument = 唯一可编辑真相源
BakedMesh = 可随时重新生成的派生缓存
Preview Node = 可销毁并重建的显示结果
```

禁止以下破坏性流程：

```text
体素编辑
  -> 转成最终 mesh
  -> 删除体素源数据
```

该流程会使后续局部编辑、组件边界恢复、逻辑调试与机关调整变得困难。

### 正确 Bake 流程

```text
Part Voxel Edit
  -> localVoxelDocument dirty
  -> BakePartMesh(part)
  -> 生成或替换 Part Root 下的 BakedMesh
  -> Preview 刷新
```

初版可以先保持每个体素一个渲染节点，并将其挂在 `PartRoot` 下，以先验证组件层级和机关行为。

Mesh 合并、可见面剔除、材质批处理是后续 Bake 优化，不应阻塞 Part 层级和 Preview 闭环。

## Transform 规则

### 可安全支持的 Transform

```text
平移：安全
绕 Y 轴按 60° 离散旋转：安全，符合六向规范
父子层级：安全
```

运行时只变更 Part Root，不改写局部体素源数据：

```lua
partRoot.position = runtimePosition
partRoot.rotation = Quaternion(rotationSteps * 60.0, Vector3.UP)
```

### 缩放规则

三棱柱规范依赖：

```text
a = 1.0m
h = 1 / sqrt(3)m
h = a * tan(30°)
```

`scale` 是每个 Part Transform 的正式字段，但是否可以编辑由 `transformCapabilities.scale` 决定。

Gameplay Part 初版默认保持：

```text
scale = (1, 1, 1)
transformCapabilities.scale = false
```

装饰性 Part 可以支持均匀缩放；初版禁止非均匀缩放。原因是任意缩放会破坏：

```text
- 六边形密铺
- 三棱柱比例
- 30° 投影对齐
- 错视连接基准
- 导航与视觉一致性
```

因此不删除缩放属性，而是将它从“所有 Part 都能自由缩放”改为“由能力控制的 Transform 属性”。

### Part 总装位置与网格吸附

Part 的局部体素可以随 `PartRoot` 平移，但参与三棱柱密铺、错视连接或玩法导航的 Part，不能使用任意 `X/Y/Z = 1m` 的笛卡尔步进。这样会产生半高、半前进或接缝错位。

关卡总装的合法吸附位置由 `TriPrismGrid` 的轴坐标派生：

```text
Grid Position = (hexQ, hexR, layer)

底层 `PartDefinition.transform.position` 始终是任意浮点世界坐标；`Q/R/Layer` 的吸附刻度属于 Editor 工作区策略，不属于数据存储约束。当前 Editor 默认：

```text
snapStep = 0.5
Q / R / Layer 均可使用 0.5 的倍数
Layer 允许负数
```

完整格点时的基础位移关系仍为：

```text
ΔQ = (1.5a, 0, -sqrt(3)/2 * a)
ΔR = (0, 0, -sqrt(3) * a)
ΔLayer = (0, h, 0)
```

因此 Transform Inspector 的编辑模型是：

```text
可编辑：Q / R / Layer / Yaw Step
只读：派生 World Position
Yaw Step：0..5，对应 0°..300°
```

Inspector 提供 `Snap Current to Tri-Prism Grid`，用于修正历史数据或手工导入造成的非对齐位置。`PartDefinition.transform.position` 仍保存最终世界坐标，保证 Preview 与运行时无需重复解算；但它必须由网格吸附服务生成，而不是由自由笛卡尔按钮累积。

## Preview 模块

Preview 不是编辑器相机的另一种显示方式，而是游戏规则验证环境。

它负责：

```text
- 固定 30° 正交游戏相机
- 从 PartDefinition 创建 Preview Node Hierarchy
- 加载每个 Part 的 Bake 结果
- 执行 Part 的离散机关状态
- 计算并显示逻辑连接图
- 显示可通行节点、条件边与错视连接 Debug
```

Preview 节点建议：

```text
PreviewRoot
├── StaticGeometry
│   └── Static baked mesh
├── Components
│   ├── Rotator_Tower_A
│   │   ├── BakedMesh
│   │   ├── PivotGizmo
│   │   └── RotatorBehavior
│   ├── Slider_Bridge_B
│   │   ├── BakedMesh
│   │   └── SliderBehavior
│   └── Elevator_C
│       ├── BakedMesh
│       └── ElevatorBehavior
├── NavigationGraphDebug
└── FixedPreviewCamera
```

## 实施顺序

### 阶段 A：Level 与 Part 数据模型

```text
- LevelDocument
- PartDefinition
- Part localVoxelDocument
- Transform：position / rotation / scale
- transformCapabilities：move / rotate / scale
- behaviorModes + behaviors
- Static 不再作为互斥 Part 类型
- Rotator 作为可组合行为模式
- Part 与体素集合的所有权
```

目标：明确哪些局部体素属于哪个 Part，并让 Part 的变换、编辑能力与运行时行为解耦，不更改现有三棱柱拓扑。

### 阶段 B：Object Tree Editor

```text
- Hierarchy 面板
- 创建 / 选择 / 删除 Part
- Open Part / Back to Level
- Part Inspector
- Transform：平移、旋转、缩放能力与当前值
- behaviorModes 组合配置
- 平移与 60° 离散旋转
```

初版 Inspector 不允许 Gameplay Part 修改非单位缩放；能力关闭时对应 Transform 控件必须禁用。

### 阶段 C：初版 Preview

```text
- 固定 30° 正交镜头
- Part Root 层级
- 用局部体素节点构成 Preview
- Rotator Part 按 60° 离散旋转
- Part 状态可切换
```

### 阶段 D：Logic Graph 与角色验证

```text
- Walk nodes
- Conditional edges
- 连接图 Debug
- 小角色寻路
- 机关状态改变后更新路径
```

### 阶段 E：Bake 优化

```text
- 按 Part 合并 mesh
- 可见面剔除
- 材质批处理
- dirty Part 增量重烘焙
- 运行时导出
```

## 最小验收闭环

```text
在 Object Tree 创建 Rotator Part
  -> 打开 Part Voxel Editor
  -> 用三棱柱体素搭出一座塔
  -> 返回 Object Tree
  -> 自动生成该 Part 的派生显示结果
  -> 固定 30° 正交 Preview
  -> 操作 Part 旋转 60°
  -> Preview 中塔以 Part Root 为中心旋转
  -> 局部体素源数据保持不变
```

完成该闭环后，再接入逻辑图和小角色寻路，验证纪念碑谷式错视连接。
